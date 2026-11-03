-- Migration 14: challenging (rejecting) the arbitrator.
-- The right of a party to challenge an arbitrator comes from the law and the platform rules cannot waive it (arbitration rules, art. 3.5).
-- This gives the right a path on the platform: the party files the grounds, the arbitrator decides with reasons. If he accepts, he steps
-- down and the file returns to arbitrator selection. If he rejects, the party's remedy before the competent court is OUTSIDE the platform.
-- The grounds are stored in a column named "body" so the audit trigger keeps the text out of the audit log (hash and status only).
create table public.arb_challenges (
  id uuid primary key default gen_random_uuid(),
  arbitration_id uuid not null references public.arbitrations(id) on delete cascade,
  arbitrator_id uuid not null references public.profiles(id),
  challenger_id uuid not null references public.profiles(id),
  body text not null,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'rejected')),
  response_body text,
  decided_at timestamptz,
  created_at timestamptz not null default now()
);
create index arb_challenges_arb on public.arb_challenges (arbitration_id);

alter table public.arb_challenges enable row level security;
create policy arb_challenges_select on public.arb_challenges for select to authenticated using (public.arb_can_read(arbitration_id));
revoke all on public.arb_challenges from anon;
revoke insert, update, delete, truncate on public.arb_challenges from authenticated;

create or replace function public.audit_arb_slim() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare v_old jsonb; v_new jsonb; v_row jsonb;
begin
  if tg_op in ('UPDATE', 'DELETE') then v_old := to_jsonb(old) - 'draft_text' - 'body' - 'signed_record' - 'response_body'; end if;
  if tg_op in ('INSERT', 'UPDATE') then v_new := to_jsonb(new) - 'draft_text' - 'body' - 'signed_record' - 'response_body'; end if;
  v_row := coalesce(v_new, v_old);
  insert into public.audit_logs (event_type, actor_id, dispute_id, entity_type, entity_id, previous_state, new_state)
  values (tg_table_name || '.' || tg_op, auth.uid(), (v_row->>'arbitration_id')::uuid, tg_table_name, (v_row->>'id')::uuid, v_old, v_new);
  return null;
end $$;
create trigger audit_arb_challenges after insert or update or delete on public.arb_challenges for each row execute function public.audit_arb_slim();

create or replace function public.challenge_arbitrator(p_arb uuid, p_grounds text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); a public.arbitrations; v_id uuid;
begin
  select * into a from public.arbitrations where id = p_arb for update;
  if not found or (v_uid is distinct from a.claimant_id and v_uid is distinct from a.respondent_id) then raise exception 'غير مصرح'; end if;
  if not public.arb_has_rules(p_arb, v_uid) then raise exception 'يجب قبول قواعد التحكيم أولًا'; end if;
  if a.arbitrator_id is null or a.status not in ('active', 'deliberation') then raise exception 'لا يُطلب رد المحكّم في هذه المرحلة'; end if;
  if length(trim(coalesce(p_grounds, ''))) < 30 then raise exception 'اكتب أسباب طلب الرد (30 حرفًا على الأقل)'; end if;
  if exists (select 1 from public.arb_challenges where arbitration_id = p_arb and arbitrator_id = a.arbitrator_id and status = 'pending') then
    raise exception 'يوجد طلب رد قيد النظر';
  end if;
  insert into public.arb_challenges (arbitration_id, arbitrator_id, challenger_id, body)
  values (p_arb, a.arbitrator_id, v_uid, trim(p_grounds)) returning id into v_id;
  return v_id;
end $$;

create or replace function public.decide_challenge(p_challenge uuid, p_accept boolean, p_reasons text) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); c public.arb_challenges; a public.arbitrations;
begin
  perform public.require_mfa();
  select * into c from public.arb_challenges where id = p_challenge for update;
  if not found then raise exception 'الطلب غير موجود'; end if;
  select * into a from public.arbitrations where id = c.arbitration_id for update;
  if a.arbitrator_id is distinct from v_uid or c.arbitrator_id <> v_uid then raise exception 'غير مصرح'; end if;
  if c.status <> 'pending' then raise exception 'تم البت في هذا الطلب'; end if;
  if length(trim(coalesce(p_reasons, ''))) < 20 then raise exception 'اكتب أسباب قرارك (20 حرفًا على الأقل)'; end if;
  if p_accept then
    update public.arb_assignments set status = 'ended', responded_at = now(), ended_reason = 'رد المحكّم'
     where arbitration_id = a.id and arbitrator_id = v_uid and status = 'accepted';
    update public.arb_hearings set status = 'cancelled' where arbitration_id = a.id and status = 'scheduled' and scheduled_at > now();
    delete from public.arb_awards where arbitration_id = a.id and status = 'draft';
    update public.arbitrations set arbitrator_id = null, status = 'selection' where id = a.id;
    update public.arb_challenges set status = 'accepted', response_body = trim(p_reasons), decided_at = now() where id = c.id;
  else
    update public.arb_challenges set status = 'rejected', response_body = trim(p_reasons), decided_at = now() where id = c.id;
  end if;
end $$;

revoke execute on function public.challenge_arbitrator(uuid, text), public.decide_challenge(uuid, boolean, text) from public, anon, authenticated;
grant execute on function public.challenge_arbitrator(uuid, text), public.decide_challenge(uuid, boolean, text) to authenticated;
