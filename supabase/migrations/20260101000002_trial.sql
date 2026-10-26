-- =====================================================================
-- Hayah ADR — closed-trial additions. Run ONCE, AFTER schema.sql.
--   1. Versioned legal documents (terms, privacy, mediation agreement)
--   2. Recorded consents (who accepted which version, when, from where)
--   3. Agreement gate enforced in the database for every state change
--   4. admin_metrics(): trial KPIs computed from the audit log
-- =====================================================================

-- ---------------------------------------------------------------- tables
create table public.legal_documents (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('terms', 'privacy', 'mediation_agreement')),
  version int not null,
  title text not null,
  body text not null,
  body_hash text not null,
  is_current boolean not null default true,
  is_placeholder boolean not null default false,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  unique (kind, version)
);
create unique index one_current_legal_doc on public.legal_documents (kind) where is_current;

create table public.consents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  document_id uuid not null references public.legal_documents(id),
  dispute_id uuid references public.disputes(id) on delete cascade,
  body_hash text not null,
  accepted_at timestamptz not null default now(),
  ip_address text,
  user_agent text
);
create unique index consents_once on public.consents
  (user_id, document_id, coalesce(dispute_id, '00000000-0000-0000-0000-000000000000'::uuid));
create index consents_dispute on public.consents (dispute_id);

-- ------------------------------------------------------------- functions
create or replace function public.has_agreement(p_dispute uuid, p_user uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.consents c join public.legal_documents l on l.id = c.document_id
    where c.user_id = p_user and c.dispute_id = p_dispute and l.kind = 'mediation_agreement');
$$;

create or replace function public.has_platform_consent() returns boolean
language sql stable security definer set search_path = public as $$
  select (
    select count(*) from public.legal_documents l
    where l.is_current and l.kind in ('terms', 'privacy')
      and exists (select 1 from public.consents c where c.document_id = l.id and c.user_id = auth.uid())
  ) = 2;
$$;

create or replace function public.publish_legal_document(p_kind text, p_title text, p_body text, p_placeholder boolean default false)
returns int language plpgsql security definer set search_path = public, extensions as $$
declare v int;
begin
  if not public.is_admin() then raise exception 'غير مصرح'; end if;
  if length(trim(p_body)) < 20 or length(trim(p_title)) < 3 then raise exception 'العنوان أو النص قصير جدًا'; end if;
  select coalesce(max(version), 0) + 1 into v from public.legal_documents where kind = p_kind;
  update public.legal_documents set is_current = false where kind = p_kind and is_current;
  insert into public.legal_documents (kind, version, title, body, body_hash, is_placeholder, created_by)
  values (p_kind, v, trim(p_title), p_body, encode(digest(convert_to(p_body, 'UTF8'), 'sha256'), 'hex'), p_placeholder, auth.uid());
  return v;
end $$;

create or replace function public.accept_legal(p_document uuid, p_dispute uuid, p_ip text, p_ua text) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); l public.legal_documents; v_dispute uuid := p_dispute;
begin
  if v_uid is null then raise exception 'يجب تسجيل الدخول'; end if;
  select * into l from public.legal_documents where id = p_document;
  if not found or not l.is_current then raise exception 'هذه النسخة لم تعد سارية. أعد تحميل الصفحة'; end if;
  if l.kind = 'mediation_agreement' then
    if v_dispute is null then raise exception 'اتفاقية الوساطة خاصة بنزاع محدد'; end if;
    if public.is_admin() or not public.is_dispute_member(v_dispute) then raise exception 'غير مصرح'; end if;
  else
    v_dispute := null;
  end if;
  insert into public.consents (user_id, document_id, dispute_id, body_hash, ip_address, user_agent)
  values (v_uid, l.id, v_dispute, l.body_hash, left(p_ip, 100), left(p_ua, 300))
  on conflict do nothing;
end $$;

-- Placeholders: the admin must replace them (admin page shows a warning until then).
insert into public.legal_documents (kind, version, title, body, body_hash, is_placeholder) values
 ('terms', 1, 'شروط استخدام المنصة (نص مؤقت)', '[نص مؤقت: يُستبدل بشروط الاستخدام المعتمدة قانونيًا قبل أول حالة حقيقية.]',
   encode(extensions.digest('terms-placeholder', 'sha256'), 'hex'), true),
 ('privacy', 1, 'سياسة الخصوصية (نص مؤقت)', '[نص مؤقت: يُستبدل بسياسة الخصوصية المعتمدة قانونيًا قبل أول حالة حقيقية.]',
   encode(extensions.digest('privacy-placeholder', 'sha256'), 'hex'), true),
 ('mediation_agreement', 1, 'اتفاقية الوساطة (نص مؤقت)', '[نص مؤقت: يُستبدل باتفاقية الوساطة المعتمدة قانونيًا قبل أول حالة حقيقية.]',
   encode(extensions.digest('mediation-placeholder', 'sha256'), 'hex'), true);

-- ----------------------------------------- the gate, enforced in the database
create or replace function public.propose_mediator(p_dispute uuid, p_mediator uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); d public.disputes;
begin
  select * into d from public.disputes where id = p_dispute for update;
  if not found or v_uid not in (d.claimant_id, d.respondent_id) then raise exception 'غير مصرح'; end if;
  if not public.has_agreement(p_dispute, v_uid) then raise exception 'يجب قبول اتفاقية الوساطة أولًا'; end if;
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
  if not public.has_agreement(a.dispute_id, v_uid) then raise exception 'يجب قبول اتفاقية الوساطة أولًا'; end if;
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
  if p_accept and not public.has_agreement(a.dispute_id, v_uid) then
    raise exception 'اقرأ اتفاقية الوساطة واقبلها قبل قبول المهمة';
  end if;
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
  if not (public.has_agreement(p_dispute, d.claimant_id) and public.has_agreement(p_dispute, d.respondent_id)
          and public.has_agreement(p_dispute, d.mediator_id)) then
    raise exception 'لا يمكن جدولة جلسة قبل قبول الطرفين والوسيط لاتفاقية الوساطة';
  end if;
  if p_at < now() - interval '1 hour' then raise exception 'موعد الجلسة في الماضي'; end if;
  select coalesce(max(session_number), 0) + 1 into v_no from public.sessions where dispute_id = p_dispute;
  insert into public.sessions (dispute_id, session_number, scheduled_at, duration_minutes)
  values (p_dispute, v_no, p_at, p_minutes) returning id into v_id;
  return v_id;
end $$;

create or replace function public.submit_settlement(p_dispute uuid) returns void
language plpgsql security definer set search_path = public as $$
declare d public.disputes;
begin
  select * into d from public.disputes where id = p_dispute for update;
  if not found or d.mediator_id is distinct from auth.uid() then raise exception 'غير مصرح'; end if;
  if not (public.has_agreement(p_dispute, d.claimant_id) and public.has_agreement(p_dispute, d.respondent_id)
          and public.has_agreement(p_dispute, d.mediator_id)) then
    raise exception 'لا يُفتح الاتفاق للتوقيع قبل قبول الجميع لاتفاقية الوساطة';
  end if;
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
  if not public.has_agreement(p_dispute, v_uid) then raise exception 'يجب قبول اتفاقية الوساطة أولًا'; end if;
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

drop policy documents_insert on public.documents;
create policy documents_insert on public.documents for insert to authenticated
  with check (uploaded_by = auth.uid() and public.is_dispute_member(dispute_id)
              and (public.is_admin() or public.has_agreement(dispute_id, auth.uid())));

-- ------------------------------------------------------- RLS and auditing
alter table public.legal_documents enable row level security;
alter table public.consents enable row level security;
create policy legal_select on public.legal_documents for select to authenticated using (true);
create policy consents_select on public.consents for select to authenticated
  using (user_id = auth.uid() or public.is_admin()
         or (dispute_id is not null and public.is_dispute_member(dispute_id)));
revoke all on public.legal_documents, public.consents from anon;
revoke insert, update, delete, truncate on public.legal_documents, public.consents from authenticated;

create trigger audit_legal after insert or update or delete on public.legal_documents
  for each row execute function public.audit_changes();
create trigger audit_consents after insert or update or delete on public.consents
  for each row execute function public.audit_changes();

-- --------------------------------------------------------------- metrics
create or replace function public.admin_metrics() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  if not public.is_admin() then raise exception 'غير مصرح'; end if;
  with stage as (
    select dispute_id, new_state->>'status' as st, min(created_at) as at
    from public.audit_logs
    where event_type = 'disputes.UPDATE' and dispute_id is not null
      and (new_state->>'status') is distinct from (previous_state->>'status')
    group by dispute_id, new_state->>'status'
  ),
  reach as (
    select d.id, d.created_at as t_created,
      max(s.at) filter (where s.st = 'accepted') as t_accepted,
      max(s.at) filter (where s.st = 'active') as t_active,
      max(s.at) filter (where s.st = 'settlement_draft') as t_draft,
      max(s.at) filter (where s.st = 'signed') as t_signed
    from public.disputes d left join stage s on s.dispute_id = d.id
    group by d.id, d.created_at
  )
  select jsonb_build_object(
    'funnel', jsonb_build_object(
      'created', count(*), 'accepted', count(t_accepted), 'active', count(t_active),
      'draft', count(t_draft), 'signed', count(t_signed)),
    'median_secs', jsonb_build_object(
      'to_accept',    percentile_cont(0.5) within group (order by extract(epoch from t_accepted - t_created)),
      'to_mediator',  percentile_cont(0.5) within group (order by extract(epoch from t_active - t_accepted)),
      'to_signature', percentile_cont(0.5) within group (order by extract(epoch from t_signed - t_active)),
      'total',        percentile_cont(0.5) within group (order by extract(epoch from t_signed - t_created)))
  ) into r from reach;

  return r || jsonb_build_object(
    'value_total', (select coalesce(sum(dispute_value_egp), 0) from public.disputes),
    'value_settled', (select coalesce(sum(dispute_value_egp), 0) from public.disputes where status in ('signed', 'closed')),
    'sessions_total', (select count(*) from public.sessions),
    'sessions_per_settled', (select round(avg(c), 1) from (
        select count(*) c from public.sessions s join public.disputes d on d.id = s.dispute_id
        where d.status in ('signed', 'closed') group by s.dispute_id) x),
    'documents_total', (select count(*) from public.documents),
    'invitations_sent', (select count(*) from public.invitations),
    'invitations_accepted', (select count(*) from public.invitations where status = 'accepted'),
    'placeholder_docs', (select count(*) from public.legal_documents where is_current and is_placeholder),
    'verified_mediators', (select count(*) from public.profiles where role = 'mediator' and kyc_status = 'verified'),
    'users_total', (select count(*) from public.profiles)
  );
end $$;
