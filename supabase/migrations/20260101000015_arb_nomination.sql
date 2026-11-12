-- Migration 15: arbitrator nomination by the platform (founder's decision).
-- Order: (1) the parties agree on an arbitrator themselves (propose / approve flow, unchanged);
--        (2) either party asks the platform to nominate: it draws AT RANDOM at most 5 eligible arbitrators and each party picks one;
--        (3) if the two picks do not match (or a party accepts none), both parties sign an acknowledgment and the platform draws one
--            of the nominees at random.
-- The draw is random and its seed is stored, so anyone can re-run it; nominees are never ranked by the outcome of their awards and no
-- commercial consideration enters the selection. The chosen arbitrator still has to accept and file his declaration of independence
-- (arbitrator_respond, unchanged), and the parties keep the right to challenge him (migration 14).

alter table public.arb_assignments
  add column appointed_by text not null default 'parties_proposal'
  check (appointed_by in ('parties_proposal', 'parties_nomination', 'platform_draw'));

create table public.arb_nominations (
  id uuid primary key default gen_random_uuid(),
  arbitration_id uuid not null references public.arbitrations(id) on delete cascade,
  round integer not null,
  requested_by uuid not null references public.profiles(id),
  draw_seed text not null,                 -- re-running "order by md5(seed || id)" over the eligible pool reproduces the nominees
  eligible_count integer not null,
  nominees uuid[] not null,
  status text not null default 'open' check (status in ('open', 'agreed', 'no_agreement', 'appointed', 'cancelled')),
  ack_text_hash text,                      -- SHA-256 of the acknowledgment text both parties signed (platform appointment)
  platform_draw_seed text,
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  unique (arbitration_id, round)
);

create table public.arb_nomination_choices (
  id uuid primary key default gen_random_uuid(),
  arbitration_id uuid not null references public.arbitrations(id) on delete cascade,
  nomination_id uuid not null references public.arb_nominations(id) on delete cascade,
  party_id uuid not null references public.profiles(id),
  choice uuid references public.profiles(id),   -- null: the party accepts none of the nominees
  chosen_at timestamptz not null default now(),
  unique (nomination_id, party_id)
);

create table public.arb_appointment_acks (
  id uuid primary key default gen_random_uuid(),
  arbitration_id uuid not null references public.arbitrations(id) on delete cascade,
  nomination_id uuid not null references public.arb_nominations(id) on delete cascade,
  party_id uuid not null references public.profiles(id),
  text_hash text not null,
  acked_at timestamptz not null default now(),
  unique (nomination_id, party_id)
);

alter table public.arb_nominations enable row level security;
alter table public.arb_nomination_choices enable row level security;
alter table public.arb_appointment_acks enable row level security;

create policy arb_nominations_select on public.arb_nominations for select to authenticated using (public.arb_can_read(arbitration_id));
-- a party's pick stays private to him (and the admin) until the nomination is decided; the state function shows both afterwards
create policy arb_choices_select on public.arb_nomination_choices for select to authenticated using (party_id = auth.uid() or public.is_admin());
create policy arb_acks_select on public.arb_appointment_acks for select to authenticated using (public.arb_can_read(arbitration_id));
revoke all on public.arb_nominations, public.arb_nomination_choices, public.arb_appointment_acks from anon;
revoke insert, update, delete, truncate on public.arb_nominations, public.arb_nomination_choices, public.arb_appointment_acks from authenticated;

create trigger audit_arb_nominations after insert or update or delete on public.arb_nominations for each row execute function public.audit_changes();
create trigger audit_arb_choices after insert or update or delete on public.arb_nomination_choices for each row execute function public.audit_changes();
create trigger audit_arb_acks after insert or update or delete on public.arb_appointment_acks for each row execute function public.audit_changes();

-- ---------------------------------------------------------------- the acknowledgment text both parties sign (its hash is stored)
create or replace function public.arb_appointment_ack_text() returns text
language sql immutable set search_path = public as $$
  select 'أقرّ بأنني لم أتفق مع الطرف الآخر على محكّم من قائمة الترشيح التي عرضتها المنصة، وأوافق موافقة صريحة ومستقلة على أن تختار المنصة المحكّم بقرعة عشوائية موثّقة من بين المرشحين المعروضين على الطرفين. '
      || 'وأعلم أن القرعة تجري بين محكّمين معتمدين لا تعارض بينهم وبين الطرفين، دون أي اعتبار تجاري ودون ترتيب بحسب نتائج أحكامهم، وأن للمحكّم المختار أن يرفض المهمة، وأن حق كل طرف في طلب رد المحكّم يبقى قائمًا وفق قواعد التحكيم والقانون.';
$$;

-- ---------------------------------------------------------------- eligible pool (internal)
create or replace function public.arb_eligible_pool(p_arb uuid) returns uuid[]
language plpgsql stable security definer set search_path = public as $$
declare a public.arbitrations; v_pool uuid[];
begin
  select * into a from public.arbitrations where id = p_arb;
  if not found then return '{}'; end if;
  select coalesce(array_agg(p.id), '{}') into v_pool
    from public.profiles p
   where p.role = 'arbitrator' and p.kyc_status = 'verified'
     and p.id not in (a.claimant_id, a.respondent_id)
     -- whoever mediated the earlier file may not arbitrate it
     and not (a.source_dispute_id is not null and (
            exists (select 1 from public.disputes d where d.id = a.source_dispute_id and d.mediator_id = p.id)
         or exists (select 1 from public.mediator_assignments m where m.dispute_id = a.source_dispute_id and m.mediator_id = p.id and m.status in ('approved', 'accepted', 'ended'))))
     -- nor anyone who already declined, was rejected by a party, or stepped down in this very file
     and not exists (select 1 from public.arb_assignments s where s.arbitration_id = p_arb and s.arbitrator_id = p.id and s.status in ('rejected', 'ended'));
  return v_pool;
end $$;

-- ---------------------------------------------------------------- 1. a party asks the platform to nominate
create or replace function public.request_nomination(p_arb uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); a public.arbitrations; v_pool uuid[]; v_seed text; v_nominees uuid[]; v_round integer; v_id uuid;
begin
  select * into a from public.arbitrations where id = p_arb for update;
  if not found or (v_uid is distinct from a.claimant_id and v_uid is distinct from a.respondent_id) then raise exception 'غير مصرح'; end if;
  if not public.arb_has_rules(p_arb, v_uid) then raise exception 'يجب قبول قواعد التحكيم أولًا'; end if;
  if a.status <> 'selection' then raise exception 'لا يُطلب الترشيح في هذه المرحلة'; end if;
  if exists (select 1 from public.arb_assignments where arbitration_id = p_arb and status in ('proposed', 'approved')) then
    raise exception 'يوجد اقتراح محكّم قيد الانتظار';
  end if;
  if exists (select 1 from public.arb_nominations where arbitration_id = p_arb and status in ('open', 'no_agreement')) then
    raise exception 'يوجد ترشيح قائم لم يُحسم بعد';
  end if;
  v_pool := public.arb_eligible_pool(p_arb);
  if coalesce(array_length(v_pool, 1), 0) = 0 then raise exception 'لا يوجد محكّمون مؤهلون للترشيح حاليًا'; end if;
  v_seed := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  select array_agg(id) into v_nominees from (
    select id from unnest(v_pool) as id order by md5(v_seed || id::text) limit 5) x;
  select coalesce(max(round), 0) + 1 into v_round from public.arb_nominations where arbitration_id = p_arb;
  insert into public.arb_nominations (arbitration_id, round, requested_by, draw_seed, eligible_count, nominees)
  values (p_arb, v_round, v_uid, v_seed, array_length(v_pool, 1), v_nominees) returning id into v_id;
  return v_id;
end $$;

-- ---------------------------------------------------------------- 2. each party picks one nominee (or none)
create or replace function public.choose_nominee(p_nomination uuid, p_choice uuid) returns text
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); n public.arb_nominations; a public.arbitrations;
        v_c1 uuid; v_c2 uuid; v_cnt integer; v_first uuid;
begin
  select * into n from public.arb_nominations where id = p_nomination for update;
  if not found then raise exception 'الترشيح غير موجود'; end if;
  select * into a from public.arbitrations where id = n.arbitration_id for update;
  if v_uid is distinct from a.claimant_id and v_uid is distinct from a.respondent_id then raise exception 'غير مصرح'; end if;
  if not public.arb_has_rules(a.id, v_uid) then raise exception 'يجب قبول قواعد التحكيم أولًا'; end if;
  if n.status <> 'open' or a.status <> 'selection' then raise exception 'تم حسم هذا الترشيح'; end if;
  if p_choice is not null and not (p_choice = any (n.nominees)) then raise exception 'المحكّم المختار ليس من قائمة الترشيح'; end if;
  if exists (select 1 from public.arb_nomination_choices where nomination_id = n.id and party_id = v_uid) then
    raise exception 'سبق أن سجّلت اختيارك';
  end if;
  insert into public.arb_nomination_choices (arbitration_id, nomination_id, party_id, choice) values (a.id, n.id, v_uid, p_choice);
  select count(*) into v_cnt from public.arb_nomination_choices where nomination_id = n.id;
  if v_cnt < 2 then return 'waiting'; end if;

  select choice into v_c1 from public.arb_nomination_choices where nomination_id = n.id and party_id = a.claimant_id;
  select choice into v_c2 from public.arb_nomination_choices where nomination_id = n.id and party_id = a.respondent_id;
  if v_c1 is not null and v_c1 = v_c2 then
    if exists (select 1 from public.arb_assignments where arbitration_id = a.id and status in ('proposed', 'approved')) then
      update public.arb_nominations set status = 'cancelled', decided_at = now() where id = n.id;
      return 'superseded';
    end if;
    select party_id into v_first from public.arb_nomination_choices where nomination_id = n.id order by chosen_at, id limit 1;
    insert into public.arb_assignments (arbitration_id, arbitrator_id, proposed_by, status, responded_at, appointed_by)
    values (a.id, v_c1, v_first, 'approved', now(), 'parties_nomination');
    update public.arb_nominations set status = 'agreed', decided_at = now() where id = n.id;
    return 'agreed';
  end if;
  update public.arb_nominations set status = 'no_agreement', decided_at = now() where id = n.id;
  return 'no_agreement';
end $$;

-- ---------------------------------------------------------------- 3. both sign the acknowledgment; the platform then draws
create or replace function public.ack_platform_appointment(p_nomination uuid) returns text
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); n public.arb_nominations; a public.arbitrations;
        v_hash text; v_cnt integer; v_pick uuid; v_seed text; v_pool uuid[];
begin
  select * into n from public.arb_nominations where id = p_nomination for update;
  if not found then raise exception 'الترشيح غير موجود'; end if;
  select * into a from public.arbitrations where id = n.arbitration_id for update;
  if v_uid is distinct from a.claimant_id and v_uid is distinct from a.respondent_id then raise exception 'غير مصرح'; end if;
  if not public.arb_has_rules(a.id, v_uid) then raise exception 'يجب قبول قواعد التحكيم أولًا'; end if;
  if n.status <> 'no_agreement' or a.status <> 'selection' then raise exception 'لا يُطلب هذا الإقرار في هذه المرحلة'; end if;
  v_hash := encode(sha256(convert_to(public.arb_appointment_ack_text(), 'UTF8')), 'hex');
  if exists (select 1 from public.arb_appointment_acks where nomination_id = n.id and party_id = v_uid) then raise exception 'سبق أن وقّعت هذا الإقرار'; end if;
  insert into public.arb_appointment_acks (arbitration_id, nomination_id, party_id, text_hash) values (a.id, n.id, v_uid, v_hash);
  select count(*) into v_cnt from public.arb_appointment_acks where nomination_id = n.id;
  if v_cnt < 2 then return 'waiting'; end if;

  -- both parties consented: the platform draws one of the nominees at random (those still eligible)
  if exists (select 1 from public.arb_assignments where arbitration_id = a.id and status in ('proposed', 'approved')) then
    update public.arb_nominations set status = 'cancelled', decided_at = now(), ack_text_hash = v_hash where id = n.id;
    return 'superseded';
  end if;
  v_pool := public.arb_eligible_pool(a.id);
  v_seed := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  select id into v_pick from unnest(n.nominees) as id where id = any (v_pool) order by md5(v_seed || id::text) limit 1;
  if v_pick is null then
    update public.arb_nominations set status = 'cancelled', decided_at = now(), ack_text_hash = v_hash, platform_draw_seed = v_seed where id = n.id;
    return 'no_eligible';
  end if;
  insert into public.arb_assignments (arbitration_id, arbitrator_id, proposed_by, status, responded_at, appointed_by)
  values (a.id, v_pick, n.requested_by, 'approved', now(), 'platform_draw');
  update public.arb_nominations set status = 'appointed', decided_at = now(), ack_text_hash = v_hash, platform_draw_seed = v_seed where id = n.id;
  return 'appointed';
end $$;

-- ---------------------------------------------------------------- state for the screen
create or replace function public.arb_nomination_state(p_arb uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); a public.arbitrations; n public.arb_nominations; v_decided boolean; v_other uuid;
        v_my_chose boolean; v_other_chose boolean; v_my_choice uuid; v_other_choice uuid; v_my_ack boolean; v_other_ack boolean;
begin
  if v_uid is null or not public.arb_can_read(p_arb) then return null; end if;
  select * into a from public.arbitrations where id = p_arb;
  if not found then return null; end if;
  select * into n from public.arb_nominations where arbitration_id = p_arb order by round desc limit 1;
  if not found then return null; end if;
  v_other := case when v_uid = a.claimant_id then a.respondent_id else a.claimant_id end;
  v_decided := n.status <> 'open';
  select exists (select 1 from public.arb_nomination_choices where nomination_id = n.id and party_id = v_uid) into v_my_chose;
  select exists (select 1 from public.arb_nomination_choices where nomination_id = n.id and party_id = v_other) into v_other_chose;
  select choice into v_my_choice from public.arb_nomination_choices where nomination_id = n.id and party_id = v_uid;
  if v_decided then select choice into v_other_choice from public.arb_nomination_choices where nomination_id = n.id and party_id = v_other; end if;
  select exists (select 1 from public.arb_appointment_acks where nomination_id = n.id and party_id = v_uid) into v_my_ack;
  select exists (select 1 from public.arb_appointment_acks where nomination_id = n.id and party_id = v_other) into v_other_ack;
  return jsonb_build_object(
    'id', n.id, 'round', n.round, 'status', n.status, 'eligible_count', n.eligible_count,
    'requested_by_me', n.requested_by = v_uid,
    'nominees', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.full_name, 'bio', m.bio,
                   'specializations', m.specializations, 'years_experience', m.years_experience) order by p.full_name)
                from unnest(n.nominees) as u(id) join public.profiles p on p.id = u.id left join public.mediator_profiles m on m.id = p.id), '[]'::jsonb),
    'i_chose', v_my_chose, 'other_chose', v_other_chose, 'my_choice', v_my_choice,
    'other_choice', case when v_decided then v_other_choice end,
    'i_acked', v_my_ack, 'other_acked', v_other_ack,
    'ack_text', public.arb_appointment_ack_text(),
    'draw_seed', case when v_decided then n.draw_seed end,
    'platform_draw_seed', n.platform_draw_seed);
end $$;

revoke execute on function public.arb_eligible_pool(uuid) from public, anon, authenticated;
revoke execute on function public.arb_appointment_ack_text(), public.request_nomination(uuid), public.choose_nominee(uuid, uuid),
  public.ack_platform_appointment(uuid), public.arb_nomination_state(uuid) from public, anon, authenticated;
grant execute on function public.arb_appointment_ack_text(), public.request_nomination(uuid), public.choose_nominee(uuid, uuid),
  public.ack_platform_appointment(uuid), public.arb_nomination_state(uuid) to authenticated;
