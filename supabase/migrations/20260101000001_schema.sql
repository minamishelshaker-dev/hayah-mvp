-- =====================================================================
-- Hayah ADR MVP — database schema (run ONCE in Supabase SQL Editor)
-- Design rules:
--   * Users can only READ tables directly. Every state change goes through
--     SECURITY DEFINER functions (RPC) that re-check who the caller is.
--   * Every change is written to audit_logs by DB triggers (not by app code),
--     in a SHA-256 hash chain, and audit_logs cannot be updated or deleted.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------- tables
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text unique not null,
  full_name text not null,
  phone text,
  role text not null default 'party' check (role in ('party','lawyer','mediator','admin')),
  requested_role text check (requested_role in ('party','lawyer','mediator')),
  bar_number text,
  kyc_status text not null default 'pending' check (kyc_status in ('pending','verified','rejected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.mediator_profiles (
  id uuid primary key references public.profiles(id) on delete cascade,
  bio text,
  specializations text[] not null default '{}',
  years_experience int
);

create sequence public.dispute_seq;

create table public.disputes (
  id uuid primary key default gen_random_uuid(),
  dispute_number text unique not null default (
    'HAYAH-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('public.dispute_seq')::text, 4, '0')
  ),
  title text not null,
  description text not null,
  dispute_type text not null check (dispute_type in ('commercial','civil','labor','other')),
  dispute_value_egp numeric(15,2) not null check (dispute_value_egp > 0),
  status text not null default 'invited' check (status in (
    'invited','accepted','mediator_selection','active','settlement_draft','signed','closed','cancelled')),
  created_by uuid not null references public.profiles(id),
  claimant_id uuid not null references public.profiles(id),
  respondent_id uuid references public.profiles(id),
  mediator_id uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.invitations (
  id uuid primary key default gen_random_uuid(),
  dispute_id uuid not null references public.disputes(id) on delete cascade,
  invited_email text not null,
  invited_phone text,
  token text unique not null,
  status text not null default 'pending' check (status in ('pending','accepted','expired')),
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

create table public.mediator_assignments (
  id uuid primary key default gen_random_uuid(),
  dispute_id uuid not null references public.disputes(id) on delete cascade,
  mediator_id uuid not null references public.profiles(id),
  proposed_by uuid not null references public.profiles(id),
  -- proposed: waiting for the other party; approved: waiting for the mediator
  status text not null default 'proposed' check (status in ('proposed','approved','accepted','rejected')),
  responded_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.documents (
  id uuid primary key default gen_random_uuid(),
  dispute_id uuid not null references public.disputes(id) on delete cascade,
  uploaded_by uuid not null references public.profiles(id),
  file_name text not null,
  file_path text unique not null,
  file_size bigint not null,
  mime_type text not null,
  sha256_hash text not null,
  document_type text not null default 'other' check (document_type in ('contract','evidence','correspondence','other')),
  created_at timestamptz not null default now()
);

create table public.sessions (
  id uuid primary key default gen_random_uuid(),
  dispute_id uuid not null references public.disputes(id) on delete cascade,
  session_number int not null,
  scheduled_at timestamptz not null,
  duration_minutes int not null default 60 check (duration_minutes between 15 and 240),
  daily_room_name text,
  daily_room_url text,
  status text not null default 'scheduled' check (status in ('scheduled','in_progress','completed','cancelled')),
  created_at timestamptz not null default now(),
  unique (dispute_id, session_number)
);

create table public.settlements (
  id uuid primary key default gen_random_uuid(),
  dispute_id uuid not null unique references public.disputes(id) on delete cascade,
  content text not null,
  content_hash text not null,
  version int not null default 1,
  status text not null default 'draft' check (status in ('draft','pending_signatures','signed')),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.settlement_signatures (
  id uuid primary key default gen_random_uuid(),
  settlement_id uuid not null references public.settlements(id) on delete cascade,
  dispute_id uuid not null references public.disputes(id) on delete cascade,
  user_id uuid not null references public.profiles(id),
  party_role text not null check (party_role in ('claimant','respondent')),
  content_hash text not null,
  signed_at timestamptz not null default now(),
  ip_address text,
  user_agent text,
  unique (settlement_id, user_id)
);

create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  seq bigint unique not null default 0,
  event_type text not null,
  actor_id uuid,
  dispute_id uuid,
  entity_type text,
  entity_id uuid,
  previous_state jsonb,
  new_state jsonb,
  prev_hash text,
  row_hash text,
  created_at timestamptz not null default now()
);
create index idx_audit_dispute on public.audit_logs(dispute_id, seq);
create index idx_disputes_status on public.disputes(status);
create index idx_documents_dispute on public.documents(dispute_id);

-- ------------------------------------------------------- helper functions
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

create or replace function public.is_dispute_member(p_dispute uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and (
    public.is_admin()
    or exists (select 1 from public.disputes d where d.id = p_dispute
               and auth.uid() in (d.created_by, d.claimant_id, d.respondent_id, d.mediator_id))
    -- a proposed mediator only sees the file after BOTH parties approved him
    or exists (select 1 from public.mediator_assignments a where a.dispute_id = p_dispute
               and a.mediator_id = auth.uid() and a.status in ('approved','accepted'))
  );
$$;

create or replace function public.can_see_profile(p_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and (
    p_id = auth.uid()
    or public.is_admin()
    or exists (select 1 from public.profiles p where p.id = p_id and p.role = 'mediator')
    or exists (select 1 from public.disputes d where public.is_dispute_member(d.id)
               and p_id in (d.created_by, d.claimant_id, d.respondent_id, d.mediator_id))
  );
$$;

-- ----------------------------------------------- profile creation / safety
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_req text := new.raw_user_meta_data->>'requested_role';
begin
  -- The role is ALWAYS 'party' here. Never trust metadata sent by the browser.
  insert into public.profiles (id, email, full_name, phone, bar_number, requested_role)
  values (
    new.id, new.email,
    coalesce(nullif(new.raw_user_meta_data->>'full_name', ''), 'مستخدم جديد'),
    nullif(new.raw_user_meta_data->>'phone', ''),
    nullif(new.raw_user_meta_data->>'bar_number', ''),
    case when v_req in ('party','lawyer','mediator') then v_req else 'party' end
  );
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.protect_profile() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := now();
  -- Only an admin (or the service role / SQL editor, where auth.uid() is null) can change these.
  if auth.uid() is not null and not public.is_admin() then
    new.role := old.role;
    new.kyc_status := old.kyc_status;
    new.email := old.email;
    new.requested_role := old.requested_role;
  end if;
  return new;
end $$;

create trigger profiles_protect before update on public.profiles
  for each row execute function public.protect_profile();

create or replace function public.ensure_mediator_profile() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.role = 'mediator' then
    insert into public.mediator_profiles (id) values (new.id) on conflict do nothing;
  end if;
  return new;
end $$;

create trigger profiles_mediator after insert or update of role on public.profiles
  for each row execute function public.ensure_mediator_profile();

create or replace function public.touch_updated_at() returns trigger
language plpgsql as $$ begin new.updated_at := now(); return new; end $$;

create trigger disputes_touch before update on public.disputes
  for each row execute function public.touch_updated_at();
create trigger settlements_touch before update on public.settlements
  for each row execute function public.touch_updated_at();

-- ------------------------------------------------- tamper-evident audit log
create or replace function public.audit_row_hash(a public.audit_logs) returns text
language sql stable set search_path = public, extensions as $$
  select encode(digest(
    a.seq::text || '|' || coalesce(a.prev_hash, '') || '|' || a.event_type || '|' ||
    coalesce(a.entity_id::text, '') || '|' || coalesce(a.new_state::text, '') || '|' ||
    extract(epoch from a.created_at)::text, 'sha256'), 'hex');
$$;

create or replace function public.audit_chain() returns trigger
language plpgsql set search_path = public, extensions as $$
declare last_row public.audit_logs;
begin
  perform pg_advisory_xact_lock(84720011);          -- one writer at a time keeps the chain linear
  select * into last_row from public.audit_logs order by seq desc limit 1;
  new.seq := coalesce(last_row.seq, 0) + 1;
  new.prev_hash := last_row.row_hash;
  new.row_hash := public.audit_row_hash(new);
  return new;
end $$;

create trigger audit_chain_insert before insert on public.audit_logs
  for each row execute function public.audit_chain();

create or replace function public.audit_immutable() returns trigger
language plpgsql as $$ begin raise exception 'audit_logs is append-only'; end $$;

create trigger audit_no_change before update or delete on public.audit_logs
  for each row execute function public.audit_immutable();
create trigger audit_no_truncate before truncate on public.audit_logs
  for each statement execute function public.audit_immutable();

create or replace function public.audit_changes() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare v_old jsonb; v_new jsonb; v_row jsonb; v_dispute uuid;
begin
  if tg_op in ('UPDATE','DELETE') then v_old := to_jsonb(old); end if;
  if tg_op in ('INSERT','UPDATE') then v_new := to_jsonb(new); end if;
  v_row := coalesce(v_new, v_old);
  if tg_table_name = 'disputes' then v_dispute := (v_row->>'id')::uuid;
  elsif v_row ? 'dispute_id' then v_dispute := (v_row->>'dispute_id')::uuid;
  end if;
  insert into public.audit_logs (event_type, actor_id, dispute_id, entity_type, entity_id, previous_state, new_state)
  values (tg_table_name || '.' || tg_op, auth.uid(), v_dispute, tg_table_name, (v_row->>'id')::uuid, v_old, v_new);
  return null;
end $$;

create trigger audit_disputes after insert or update or delete on public.disputes
  for each row execute function public.audit_changes();
create trigger audit_invitations after insert or update or delete on public.invitations
  for each row execute function public.audit_changes();
create trigger audit_assignments after insert or update or delete on public.mediator_assignments
  for each row execute function public.audit_changes();
create trigger audit_documents after insert or update or delete on public.documents
  for each row execute function public.audit_changes();
create trigger audit_sessions after insert or update or delete on public.sessions
  for each row execute function public.audit_changes();
create trigger audit_settlements after insert or update or delete on public.settlements
  for each row execute function public.audit_changes();
create trigger audit_signatures after insert or update or delete on public.settlement_signatures
  for each row execute function public.audit_changes();
create trigger audit_profiles_ins after insert on public.profiles
  for each row execute function public.audit_changes();
create trigger audit_profiles_upd after update of role, kyc_status on public.profiles
  for each row execute function public.audit_changes();

create or replace function public.verify_audit_chain() returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare r public.audit_logs; prev text := null; n bigint := 0;
begin
  if not public.is_admin() then raise exception 'غير مصرح'; end if;
  for r in select * from public.audit_logs order by seq loop
    n := n + 1;
    if r.prev_hash is distinct from prev or r.row_hash <> public.audit_row_hash(r) then
      return jsonb_build_object('ok', false, 'bad_seq', r.seq, 'total', n);
    end if;
    prev := r.row_hash;
  end loop;
  return jsonb_build_object('ok', true, 'total', n);
end $$;

-- ------------------------------------------------------- business functions
create or replace function public.create_dispute(
  p_title text, p_description text, p_type text, p_value numeric, p_email text, p_phone text
) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_email text; d public.disputes; v_token text;
begin
  if v_uid is null then raise exception 'يجب تسجيل الدخول'; end if;
  select email into v_email from public.profiles where id = v_uid;
  if lower(trim(p_email)) = lower(v_email) then
    raise exception 'لا يمكنك دعوة نفسك كطرف ثانٍ في النزاع';
  end if;
  insert into public.disputes (title, description, dispute_type, dispute_value_egp, created_by, claimant_id)
  values (p_title, p_description, p_type, p_value, v_uid, v_uid) returning * into d;
  v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  insert into public.invitations (dispute_id, invited_email, invited_phone, token, expires_at)
  values (d.id, lower(trim(p_email)), nullif(trim(p_phone), ''), v_token, now() + interval '7 days');
  return jsonb_build_object('id', d.id, 'dispute_number', d.dispute_number, 'token', v_token);
end $$;

create or replace function public.invitation_preview(p_token text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'dispute_number', d.dispute_number,
    'claimant_name', p.full_name,
    'invited_email', i.invited_email,
    'status', case when i.status = 'pending' and i.expires_at < now() then 'expired' else i.status end)
  from public.invitations i
  join public.disputes d on d.id = i.dispute_id
  join public.profiles p on p.id = d.claimant_id
  where i.token = p_token;
$$;
grant execute on function public.invitation_preview(text) to anon, authenticated;

create or replace function public.accept_invitation(p_token text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_email text; inv public.invitations; d public.disputes;
begin
  if v_uid is null then raise exception 'يجب تسجيل الدخول'; end if;
  select * into inv from public.invitations where token = p_token for update;
  if not found then raise exception 'رابط الدعوة غير صالح'; end if;
  if inv.status <> 'pending' then raise exception 'تم استخدام هذه الدعوة من قبل'; end if;
  if inv.expires_at < now() then raise exception 'انتهت صلاحية الدعوة'; end if;
  select email into v_email from public.profiles where id = v_uid;
  if lower(v_email) <> inv.invited_email then
    raise exception 'هذه الدعوة موجّهة إلى بريد إلكتروني آخر (%). سجّل الدخول بالحساب الصحيح', inv.invited_email;
  end if;
  select * into d from public.disputes where id = inv.dispute_id for update;
  if d.claimant_id = v_uid then raise exception 'لا يمكن لمقدّم النزاع قبول دعوته'; end if;
  update public.invitations set status = 'accepted' where id = inv.id;
  update public.disputes set respondent_id = v_uid, status = 'accepted' where id = d.id and status = 'invited';
  return d.id;
end $$;

create or replace function public.propose_mediator(p_dispute uuid, p_mediator uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); d public.disputes;
begin
  select * into d from public.disputes where id = p_dispute for update;
  if not found or v_uid not in (d.claimant_id, d.respondent_id) then raise exception 'غير مصرح'; end if;
  if d.status not in ('accepted','mediator_selection') then raise exception 'لا يمكن اختيار وسيط في هذه المرحلة'; end if;
  if not exists (select 1 from public.profiles where id = p_mediator and role = 'mediator') then
    raise exception 'الوسيط غير موجود';
  end if;
  if exists (select 1 from public.mediator_assignments where dispute_id = p_dispute and status in ('proposed','approved')) then
    raise exception 'يوجد اقتراح وسيط قيد الانتظار';
  end if;
  insert into public.mediator_assignments (dispute_id, mediator_id, proposed_by) values (p_dispute, p_mediator, v_uid);
  update public.disputes set status = 'mediator_selection' where id = p_dispute;
end $$;

create or replace function public.party_respond_mediator(p_assignment uuid, p_approve boolean) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); a public.mediator_assignments; d public.disputes;
begin
  select * into a from public.mediator_assignments where id = p_assignment for update;
  if not found then raise exception 'الاقتراح غير موجود'; end if;
  select * into d from public.disputes where id = a.dispute_id;
  if v_uid not in (d.claimant_id, d.respondent_id) or v_uid = a.proposed_by then
    raise exception 'الرد على الاقتراح من حق الطرف الآخر فقط';
  end if;
  if a.status <> 'proposed' then raise exception 'تم الرد على هذا الاقتراح'; end if;
  update public.mediator_assignments
    set status = case when p_approve then 'approved' else 'rejected' end, responded_at = now()
    where id = a.id;
end $$;

create or replace function public.mediator_respond(p_assignment uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); a public.mediator_assignments;
begin
  select * into a from public.mediator_assignments where id = p_assignment for update;
  if not found or a.mediator_id <> v_uid then raise exception 'غير مصرح'; end if;
  if a.status <> 'approved' then raise exception 'الاقتراح لم يُعتمد من الطرفين بعد'; end if;
  if p_accept then
    update public.mediator_assignments set status = 'accepted', responded_at = now() where id = a.id;
    update public.disputes set mediator_id = v_uid, status = 'active' where id = a.dispute_id;
  else
    update public.mediator_assignments set status = 'rejected', responded_at = now() where id = a.id;
  end if;
end $$;

create or replace function public.schedule_session(p_dispute uuid, p_at timestamptz, p_minutes int) returns uuid
language plpgsql security definer set search_path = public as $$
declare d public.disputes; v_id uuid; v_no int;
begin
  select * into d from public.disputes where id = p_dispute for update;
  if not found or d.mediator_id is distinct from auth.uid() then raise exception 'الوسيط وحده يحدد الجلسات'; end if;
  if d.status not in ('active','settlement_draft') then raise exception 'لا يمكن جدولة جلسة في هذه المرحلة'; end if;
  if p_at < now() - interval '1 hour' then raise exception 'موعد الجلسة في الماضي'; end if;
  select coalesce(max(session_number), 0) + 1 into v_no from public.sessions where dispute_id = p_dispute;
  insert into public.sessions (dispute_id, session_number, scheduled_at, duration_minutes)
  values (p_dispute, v_no, p_at, p_minutes) returning id into v_id;
  return v_id;
end $$;

create or replace function public.save_settlement(p_dispute uuid, p_content text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare d public.disputes; s public.settlements; v_hash text;
begin
  select * into d from public.disputes where id = p_dispute for update;
  if not found or d.mediator_id is distinct from auth.uid() then raise exception 'الوسيط وحده يصيغ اتفاق التسوية'; end if;
  if d.status not in ('active','settlement_draft') then raise exception 'لا يمكن تعديل الاتفاق في هذه المرحلة'; end if;
  if length(trim(p_content)) < 50 then raise exception 'نص الاتفاق قصير جدًا'; end if;
  v_hash := encode(digest(convert_to(p_content, 'UTF8'), 'sha256'), 'hex');
  select * into s from public.settlements where dispute_id = p_dispute for update;
  if not found then
    insert into public.settlements (dispute_id, content, content_hash, created_by)
    values (p_dispute, p_content, v_hash, auth.uid());
  else
    if s.status <> 'draft' then raise exception 'الاتفاق مُغلق للتوقيع ولا يمكن تعديله'; end if;
    update public.settlements set content = p_content, content_hash = v_hash, version = s.version + 1 where id = s.id;
  end if;
  update public.disputes set status = 'settlement_draft' where id = p_dispute;
end $$;

create or replace function public.submit_settlement(p_dispute uuid) returns void
language plpgsql security definer set search_path = public as $$
declare d public.disputes;
begin
  select * into d from public.disputes where id = p_dispute for update;
  if not found or d.mediator_id is distinct from auth.uid() then raise exception 'غير مصرح'; end if;
  update public.settlements set status = 'pending_signatures' where dispute_id = p_dispute and status = 'draft';
  if not found then raise exception 'لا توجد مسودة اتفاق لإرسالها للتوقيع'; end if;
end $$;

create or replace function public.sign_settlement(p_dispute uuid, p_ip text, p_ua text) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); d public.disputes; s public.settlements; v_role text; n int;
begin
  select * into d from public.disputes where id = p_dispute for update;
  if not found then raise exception 'النزاع غير موجود'; end if;
  v_role := case when v_uid = d.claimant_id then 'claimant' when v_uid = d.respondent_id then 'respondent' end;
  if v_role is null then raise exception 'التوقيع للأطراف فقط'; end if;
  select * into s from public.settlements where dispute_id = p_dispute for update;
  if not found or s.status <> 'pending_signatures' then raise exception 'الاتفاق غير مفتوح للتوقيع'; end if;
  insert into public.settlement_signatures (settlement_id, dispute_id, user_id, party_role, content_hash, ip_address, user_agent)
  values (s.id, p_dispute, v_uid, v_role, s.content_hash, left(p_ip, 100), left(p_ua, 300));
  select count(distinct party_role) into n from public.settlement_signatures where settlement_id = s.id;
  if n = 2 then
    update public.settlements set status = 'signed' where id = s.id;
    update public.disputes set status = 'signed' where id = p_dispute;
  end if;
exception when unique_violation then
  raise exception 'وقّعت على هذا الاتفاق من قبل';
end $$;

-- ------------------------------------------------------------------- RLS
alter table public.profiles enable row level security;
alter table public.mediator_profiles enable row level security;
alter table public.disputes enable row level security;
alter table public.invitations enable row level security;
alter table public.mediator_assignments enable row level security;
alter table public.documents enable row level security;
alter table public.sessions enable row level security;
alter table public.settlements enable row level security;
alter table public.settlement_signatures enable row level security;
alter table public.audit_logs enable row level security;

create policy profiles_select on public.profiles for select to authenticated using (public.can_see_profile(id));
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid() or public.is_admin()) with check (id = auth.uid() or public.is_admin());
create policy mediator_profiles_select on public.mediator_profiles for select to authenticated using (true);
create policy mediator_profiles_update on public.mediator_profiles for update to authenticated
  using (id = auth.uid() or public.is_admin()) with check (id = auth.uid() or public.is_admin());

create policy disputes_select on public.disputes for select to authenticated using (public.is_dispute_member(id));
create policy invitations_select on public.invitations for select to authenticated
  using (public.is_admin() or exists (select 1 from public.disputes d where d.id = dispute_id and d.created_by = auth.uid()));
create policy assignments_select on public.mediator_assignments for select to authenticated using (public.is_dispute_member(dispute_id));
create policy documents_select on public.documents for select to authenticated using (public.is_dispute_member(dispute_id));
create policy documents_insert on public.documents for insert to authenticated
  with check (uploaded_by = auth.uid() and public.is_dispute_member(dispute_id));
create policy sessions_select on public.sessions for select to authenticated using (public.is_dispute_member(dispute_id));
create policy settlements_select on public.settlements for select to authenticated using (public.is_dispute_member(dispute_id));
create policy signatures_select on public.settlement_signatures for select to authenticated using (public.is_dispute_member(dispute_id));
create policy audit_select on public.audit_logs for select to authenticated
  using (public.is_admin() or (dispute_id is not null and public.is_dispute_member(dispute_id)));

-- Defense in depth: even without RLS, these roles cannot write these tables directly.
revoke all on all tables in schema public from anon;
revoke insert, update, delete, truncate on
  public.disputes, public.invitations, public.mediator_assignments, public.sessions,
  public.settlements, public.settlement_signatures, public.audit_logs
  from authenticated;
revoke update, delete, truncate on public.documents from authenticated;
revoke insert, delete, truncate on public.profiles, public.mediator_profiles from authenticated;

-- --------------------------------------------------------------- storage
insert into storage.buckets (id, name, public, file_size_limit)
values ('documents', 'documents', false, 10485760)
on conflict (id) do nothing;

create policy documents_obj_read on storage.objects for select to authenticated
  using (bucket_id = 'documents' and public.is_dispute_member(((storage.foldername(name))[1])::uuid));
create policy documents_obj_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'documents' and public.is_dispute_member(((storage.foldername(name))[1])::uuid));
