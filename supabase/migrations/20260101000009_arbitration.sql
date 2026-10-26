-- =====================================================================
-- Hayah ADR — arbitration, phase A. Run AFTER 008.
--
-- Positioning (decided with the owner): ad-hoc arbitration under Law 27/1994 where the platform is a
-- TOOL for case management and records, not an institution, and not the place where an enforceable award is
-- "issued". The award is signed on paper; the platform records the signed scan and its hash.
--
-- Rules enforced here, in the database:
--  * An arbitration is a NEW file linked to the mediation file. Nothing said, offered or drafted in mediation is
--    copied into it. Only the two parties carry over, and the claim is typed afresh.
--  * Escalation is consensual: the other party must accept.
--  * Nobody who acted as mediator in the source dispute can be proposed or accepted as arbitrator. No override.
--  * The arbitration agreement is signed OUTSIDE the platform (wet ink or a licensed e-signature); a scan is
--    uploaded and BOTH parties confirm the same file. The platform does not judge its validity.
--  * A sole arbitrator, chosen by both parties, must file a written independence declaration to accept.
--  * Every step has a deadline; a late statement is accepted but flagged, the tribunal decides what follows.
--  * The draft award is visible to the arbitrator ONLY (not to the parties, not to the admin) until issued, and
--    its text never enters the audit log.
--  * Role "arbitrator": promoted by an admin, verified, and subject to the same second-step (MFA) rule as mediators.
-- =====================================================================

-- ------------------------------------------------------------ roles and legal text
alter table public.profiles drop constraint profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role in ('party', 'lawyer', 'mediator', 'arbitrator', 'admin'));
alter table public.profiles drop constraint profiles_requested_role_check;
alter table public.profiles add constraint profiles_requested_role_check check (requested_role in ('party', 'lawyer', 'mediator', 'arbitrator'));

alter table public.legal_documents drop constraint legal_documents_kind_check;
alter table public.legal_documents add constraint legal_documents_kind_check
  check (kind in ('terms', 'privacy', 'mediation_agreement', 'arbitration_rules'));
insert into public.legal_documents (kind, version, title, body, body_hash, is_placeholder) values
  ('arbitration_rules', 1, 'قواعد استخدام المنصة في التحكيم (نص مؤقت)',
   '[نص مؤقت: يُستبدل بقواعد استخدام المنصة في التحكيم المعتمدة قانونيًا قبل أول حالة حقيقية.]',
   encode(extensions.digest('arbitration-rules-placeholder', 'sha256'), 'hex'), true);

-- ------------------------------------------------------------ tables
create sequence public.arb_seq;

create table public.arbitrations (
  id uuid primary key default gen_random_uuid(),
  arb_number text unique not null default ('HAYAH-ARB-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('public.arb_seq')::text, 4, '0')),
  source_dispute_id uuid references public.disputes(id),
  title text not null,
  summary text not null,
  dispute_value_egp numeric(15,2) not null check (dispute_value_egp > 0),
  prior_clause boolean not null default false,   -- the claimant says the contract already had an arbitration clause (a declaration, not a finding)
  status text not null default 'proposed' check (status in ('proposed', 'agreement', 'selection', 'active', 'deliberation', 'closed', 'cancelled')),
  claimant_id uuid not null references public.profiles(id),
  respondent_id uuid not null references public.profiles(id),
  arbitrator_id uuid references public.profiles(id),
  created_by uuid not null references public.profiles(id),
  rules_document_id uuid not null references public.legal_documents(id),
  outcome text check (outcome in ('award_issued', 'terminated', 'withdrawn', 'declined')),
  outcome_reason text,
  closed_at timestamptz,
  closed_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index arbitrations_source on public.arbitrations (source_dispute_id);
create trigger arbitrations_touch before update on public.arbitrations for each row execute function public.touch_updated_at();

create table public.arb_assignments (
  id uuid primary key default gen_random_uuid(),
  arbitration_id uuid not null references public.arbitrations(id) on delete cascade,
  arbitrator_id uuid not null references public.profiles(id),
  proposed_by uuid not null references public.profiles(id),
  status text not null default 'proposed' check (status in ('proposed', 'approved', 'accepted', 'rejected', 'ended')),
  disclosure text,               -- the arbitrator's written declaration of independence and impartiality
  disclosed_at timestamptz,
  ended_reason text,
  responded_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.arb_documents (
  id uuid primary key default gen_random_uuid(),
  arbitration_id uuid not null references public.arbitrations(id) on delete cascade,
  uploaded_by uuid not null references public.profiles(id),
  file_name text not null,
  file_path text unique not null,
  file_size bigint not null,
  mime_type text not null,
  sha256_hash text not null,
  doc_type text not null check (doc_type in ('arbitration_agreement', 'exhibit', 'procedural', 'award_signed', 'other')),
  created_at timestamptz not null default now()
);

create table public.arb_agreement_confirmations (
  id uuid primary key default gen_random_uuid(),
  arbitration_id uuid not null references public.arbitrations(id) on delete cascade,
  user_id uuid not null references public.profiles(id),
  document_id uuid not null references public.arb_documents(id),
  ip_address text,
  user_agent text,
  confirmed_at timestamptz not null default now(),
  unique (arbitration_id, user_id)
);

create table public.arb_steps (
  id uuid primary key default gen_random_uuid(),
  arbitration_id uuid not null references public.arbitrations(id) on delete cascade,
  seq int not null,
  kind text not null check (kind in ('statement_of_claim', 'statement_of_defence', 'reply', 'rejoinder', 'other')),
  party text not null check (party in ('claimant', 'respondent')),
  due_at timestamptz not null,
  note text,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  unique (arbitration_id, seq)
);

create table public.arb_submissions (
  id uuid primary key default gen_random_uuid(),
  step_id uuid not null unique references public.arb_steps(id) on delete cascade,
  arbitration_id uuid not null references public.arbitrations(id) on delete cascade,
  submitted_by uuid not null references public.profiles(id),
  body text not null,
  document_ids uuid[] not null default '{}',
  late boolean not null,
  submitted_at timestamptz not null default now()
);

create table public.arb_hearings (
  id uuid primary key default gen_random_uuid(),
  arbitration_id uuid not null references public.arbitrations(id) on delete cascade,
  number int not null,
  scheduled_at timestamptz not null,
  duration_minutes int not null default 120 check (duration_minutes between 15 and 480),
  daily_room_name text,
  daily_room_url text,
  status text not null default 'scheduled' check (status in ('scheduled', 'cancelled', 'completed')),
  created_at timestamptz not null default now(),
  unique (arbitration_id, number)
);

create table public.arb_awards (
  id uuid primary key default gen_random_uuid(),
  arbitration_id uuid not null unique references public.arbitrations(id) on delete cascade,
  draft_text text not null,
  draft_hash text not null,
  version int not null default 1,
  status text not null default 'draft' check (status in ('draft', 'issued')),
  signed_document_id uuid references public.arb_documents(id),
  award_date date,
  issued_at timestamptz,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger arb_awards_touch before update on public.arb_awards for each row execute function public.touch_updated_at();

-- consents can now belong to an arbitration (rules acceptance)
alter table public.consents add column arbitration_id uuid references public.arbitrations(id) on delete cascade;
drop index public.consents_once;
create unique index consents_once on public.consents
  (user_id, document_id, coalesce(dispute_id, '00000000-0000-0000-0000-000000000000'::uuid), coalesce(arbitration_id, '00000000-0000-0000-0000-000000000000'::uuid));

-- ------------------------------------------------------------ re-declared functions
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
    case when v_req in ('party','lawyer','mediator','arbitrator') then v_req else 'party' end
  );
  return new;
end $$;

create or replace function public.ensure_mediator_profile() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.role in ('mediator', 'arbitrator') then
    insert into public.mediator_profiles (id) values (new.id) on conflict do nothing;
  end if;
  return new;
end $$;

create or replace function public.mfa_satisfied() returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when auth.uid() is null then false
    when not public.mfa_required() then true
    when not exists (select 1 from public.profiles where id = auth.uid() and role in ('admin', 'mediator', 'arbitrator')) then true
    else coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
  end;
$$;

create or replace function public.mfa_status() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'required', public.mfa_required() and exists (select 1 from public.profiles where id = auth.uid() and role in ('admin', 'mediator', 'arbitrator')),
    'ok', public.mfa_satisfied());
$$;

-- ------------------------------------------------------------ access helpers
create or replace function public.arb_is_member(p_arb uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and public.mfa_satisfied() and (
    public.is_admin()
    or exists (select 1 from public.arbitrations a where a.id = p_arb and auth.uid() in (a.claimant_id, a.respondent_id, a.arbitrator_id))
    -- a proposed arbitrator sees the file only after BOTH parties approved him
    or exists (select 1 from public.arb_assignments s where s.arbitration_id = p_arb and s.arbitrator_id = auth.uid() and s.status in ('approved', 'accepted')));
$$;

create or replace function public.arb_has_rules(p_arb uuid, p_user uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.arb_is_member(p_arb) and exists (
    select 1 from public.consents c join public.arbitrations a on a.id = c.arbitration_id and a.rules_document_id = c.document_id
    where c.user_id = p_user and c.arbitration_id = p_arb);
$$;

create or replace function public.arb_can_read(p_arb uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and (public.is_admin() or (public.arb_is_member(p_arb) and public.arb_has_rules(p_arb, auth.uid())));
$$;

create or replace function public.arb_is_open(p_arb uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.arbitrations where id = p_arb and status not in ('closed', 'cancelled'));
$$;

-- ------------------------------------------------------------ audit
-- The case id (dispute OR arbitration) goes in audit_logs.dispute_id, which is already covered by the hash.
create or replace function public.audit_changes() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare v_old jsonb; v_new jsonb; v_row jsonb; v_case uuid;
begin
  if tg_op in ('UPDATE', 'DELETE') then v_old := to_jsonb(old); end if;
  if tg_op in ('INSERT', 'UPDATE') then v_new := to_jsonb(new); end if;
  v_row := coalesce(v_new, v_old);
  if tg_table_name in ('disputes', 'arbitrations') then v_case := (v_row->>'id')::uuid;
  else v_case := coalesce((v_row->>'dispute_id')::uuid, (v_row->>'arbitration_id')::uuid);
  end if;
  insert into public.audit_logs (event_type, actor_id, dispute_id, entity_type, entity_id, previous_state, new_state)
  values (tg_table_name || '.' || tg_op, auth.uid(), v_case, tg_table_name, (v_row->>'id')::uuid, v_old, v_new);
  return null;
end $$;

-- The text of a draft award and of a statement never enters the audit log (hash and status only).
create or replace function public.audit_arb_slim() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare v_old jsonb; v_new jsonb; v_row jsonb;
begin
  if tg_op in ('UPDATE', 'DELETE') then v_old := to_jsonb(old) - 'draft_text' - 'body'; end if;
  if tg_op in ('INSERT', 'UPDATE') then v_new := to_jsonb(new) - 'draft_text' - 'body'; end if;
  v_row := coalesce(v_new, v_old);
  insert into public.audit_logs (event_type, actor_id, dispute_id, entity_type, entity_id, previous_state, new_state)
  values (tg_table_name || '.' || tg_op, auth.uid(), (v_row->>'arbitration_id')::uuid, tg_table_name, (v_row->>'id')::uuid, v_old, v_new);
  return null;
end $$;

create trigger audit_arbitrations after insert or update or delete on public.arbitrations for each row execute function public.audit_changes();
create trigger audit_arb_assignments after insert or update or delete on public.arb_assignments for each row execute function public.audit_changes();
create trigger audit_arb_documents after insert or update or delete on public.arb_documents for each row execute function public.audit_changes();
create trigger audit_arb_confirmations after insert or update or delete on public.arb_agreement_confirmations for each row execute function public.audit_changes();
create trigger audit_arb_steps after insert or update or delete on public.arb_steps for each row execute function public.audit_changes();
create trigger audit_arb_hearings after insert or update or delete on public.arb_hearings for each row execute function public.audit_changes();
create trigger audit_arb_submissions after insert or update or delete on public.arb_submissions for each row execute function public.audit_arb_slim();
create trigger audit_arb_awards after insert or update or delete on public.arb_awards for each row execute function public.audit_arb_slim();

-- ------------------------------------------------------------ what is waiting for me, and names (re-declared with arbitration)
create or replace function public.my_actions() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(q.x order by q.x->>'dispute_number', q.x->>'code'), '[]'::jsonb) from (
    select jsonb_build_object('case_kind', 'dispute', 'case_id', d.id, 'dispute_id', d.id, 'dispute_number', d.dispute_number, 'code', 'accept_agreement') x
      from public.disputes d
      where auth.uid() is not null and not public.is_admin() and d.status not in ('closed', 'cancelled')
        and public.is_dispute_member(d.id) and not public.has_agreement(d.id, auth.uid())
    union all
    select jsonb_build_object('case_kind', 'dispute', 'case_id', d.id, 'dispute_id', d.id, 'dispute_number', d.dispute_number, 'code', 'approve_mediator')
      from public.mediator_assignments a join public.disputes d on d.id = a.dispute_id
      where a.status = 'proposed' and a.proposed_by <> auth.uid() and auth.uid() in (d.claimant_id, d.respondent_id)
        and public.has_agreement(d.id, auth.uid())
    union all
    select jsonb_build_object('case_kind', 'dispute', 'case_id', d.id, 'dispute_id', d.id, 'dispute_number', d.dispute_number, 'code', 'accept_assignment')
      from public.mediator_assignments a join public.disputes d on d.id = a.dispute_id
      where a.status = 'approved' and a.mediator_id = auth.uid() and d.status = 'mediator_selection'
    union all
    select jsonb_build_object('case_kind', 'dispute', 'case_id', d.id, 'dispute_id', d.id, 'dispute_number', d.dispute_number, 'code', 'choose_mediator')
      from public.disputes d
      where d.status in ('accepted', 'mediator_selection') and auth.uid() in (d.claimant_id, d.respondent_id)
        and public.has_agreement(d.id, auth.uid())
        and not exists (select 1 from public.mediator_assignments a where a.dispute_id = d.id and a.status in ('proposed', 'approved'))
    union all
    select jsonb_build_object('case_kind', 'dispute', 'case_id', d.id, 'dispute_id', d.id, 'dispute_number', d.dispute_number, 'code', 'renew_invitation')
      from public.disputes d join public.invitations i on i.dispute_id = d.id
      where d.status = 'invited' and d.claimant_id = auth.uid() and i.status = 'pending' and i.expires_at < now()
    union all
    select jsonb_build_object('case_kind', 'dispute', 'case_id', d.id, 'dispute_id', d.id, 'dispute_number', d.dispute_number, 'code', 'schedule_session')
      from public.disputes d
      where d.status = 'active' and d.mediator_id = auth.uid() and public.is_dispute_member(d.id)
        and not exists (select 1 from public.sessions s where s.dispute_id = d.id and s.status = 'scheduled')
    union all
    select jsonb_build_object('case_kind', 'dispute', 'case_id', d.id, 'dispute_id', d.id, 'dispute_number', d.dispute_number, 'code', 'sign_settlement')
      from public.settlements s join public.disputes d on d.id = s.dispute_id
      where s.status = 'pending_signatures' and auth.uid() in (d.claimant_id, d.respondent_id)
        and public.has_agreement(d.id, auth.uid())
        and not exists (select 1 from public.settlement_signatures g where g.settlement_id = s.id and g.user_id = auth.uid())
    union all
    select jsonb_build_object('case_kind', 'arbitration', 'case_id', a.id, 'dispute_number', a.arb_number, 'code', 'accept_arb_rules')
      from public.arbitrations a
      where auth.uid() is not null and not public.is_admin() and a.status not in ('closed', 'cancelled')
        and public.arb_is_member(a.id) and not public.arb_has_rules(a.id, auth.uid())
    union all
    select jsonb_build_object('case_kind', 'arbitration', 'case_id', a.id, 'dispute_number', a.arb_number, 'code', 'respond_escalation')
      from public.arbitrations a
      where a.status = 'proposed' and a.respondent_id = auth.uid() and public.arb_has_rules(a.id, auth.uid())
    union all
    select jsonb_build_object('case_kind', 'arbitration', 'case_id', a.id, 'dispute_number', a.arb_number, 'code', 'confirm_agreement')
      from public.arbitrations a
      where a.status = 'agreement' and auth.uid() in (a.claimant_id, a.respondent_id) and public.arb_has_rules(a.id, auth.uid())
        and not exists (select 1 from public.arb_agreement_confirmations c where c.arbitration_id = a.id and c.user_id = auth.uid())
    union all
    select jsonb_build_object('case_kind', 'arbitration', 'case_id', a.id, 'dispute_number', a.arb_number, 'code', 'choose_arbitrator')
      from public.arbitrations a
      where a.status = 'selection' and auth.uid() in (a.claimant_id, a.respondent_id) and public.arb_has_rules(a.id, auth.uid())
        and not exists (select 1 from public.arb_assignments s where s.arbitration_id = a.id and s.status in ('proposed', 'approved'))
    union all
    select jsonb_build_object('case_kind', 'arbitration', 'case_id', a.id, 'dispute_number', a.arb_number, 'code', 'approve_arbitrator')
      from public.arb_assignments s join public.arbitrations a on a.id = s.arbitration_id
      where s.status = 'proposed' and s.proposed_by <> auth.uid() and auth.uid() in (a.claimant_id, a.respondent_id)
        and public.arb_has_rules(a.id, auth.uid())
    union all
    select jsonb_build_object('case_kind', 'arbitration', 'case_id', a.id, 'dispute_number', a.arb_number, 'code', 'accept_arb_assignment')
      from public.arb_assignments s join public.arbitrations a on a.id = s.arbitration_id
      where s.status = 'approved' and s.arbitrator_id = auth.uid() and a.status = 'selection'
    union all
    select jsonb_build_object('case_kind', 'arbitration', 'case_id', a.id, 'dispute_number', a.arb_number, 'code', 'set_timetable')
      from public.arbitrations a
      where a.status = 'active' and a.arbitrator_id = auth.uid() and public.arb_is_member(a.id)
        and not exists (select 1 from public.arb_steps t where t.arbitration_id = a.id)
    union all
    select jsonb_build_object('case_kind', 'arbitration', 'case_id', a.id, 'dispute_number', a.arb_number, 'code', 'submit_statement')
      from public.arb_steps t join public.arbitrations a on a.id = t.arbitration_id
      where a.status = 'active' and t.party = case when auth.uid() = a.claimant_id then 'claimant' when auth.uid() = a.respondent_id then 'respondent' end
        and public.arb_has_rules(a.id, auth.uid())
        and not exists (select 1 from public.arb_submissions u where u.step_id = t.id)
    union all
    select jsonb_build_object('case_kind', 'arbitration', 'case_id', a.id, 'dispute_number', a.arb_number, 'code', 'issue_award')
      from public.arbitrations a
      where a.status = 'deliberation' and a.arbitrator_id = auth.uid() and public.arb_is_member(a.id)
  ) q;
$$;

create or replace function public.profile_names(p_ids uuid[]) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(p.id, p.full_name), '{}'::jsonb)
  from public.profiles p
  where auth.uid() is not null and p.id = any (p_ids) and (
    p.id = auth.uid() or public.is_admin()
    or exists (select 1 from public.disputes d where public.can_read_dispute(d.id)
               and p.id in (d.claimant_id, d.respondent_id, d.mediator_id, d.created_by))
    or exists (select 1 from public.mediator_assignments a where public.can_read_dispute(a.dispute_id) and a.mediator_id = p.id)
    or exists (select 1 from public.arbitrations r where public.arb_can_read(r.id)
               and p.id in (r.claimant_id, r.respondent_id, r.arbitrator_id))
    or exists (select 1 from public.arb_assignments s where public.arb_can_read(s.arbitration_id) and s.arbitrator_id = p.id));
$$;

-- ------------------------------------------------------------ escalation and lifecycle
create or replace function public.propose_escalation(p_dispute uuid, p_title text, p_summary text, p_value numeric, p_prior_clause boolean default false)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); d public.disputes; v_rules uuid; v_id uuid; v_resp uuid;
begin
  select * into d from public.disputes where id = p_dispute for update;
  if not found or (v_uid is distinct from d.claimant_id and v_uid is distinct from d.respondent_id) then raise exception 'غير مصرح'; end if;
  if not public.has_agreement(p_dispute, v_uid) then raise exception 'يجب قبول اتفاقية الوساطة أولًا'; end if;
  if not (d.status in ('active', 'settlement_draft') or (d.status = 'closed' and d.outcome = 'no_settlement')) then
    raise exception 'لا يُصعَّد إلى التحكيم إلا من وساطة جارية أو انتهت دون تسوية';
  end if;
  if exists (select 1 from public.arbitrations where source_dispute_id = p_dispute and status <> 'cancelled') then
    raise exception 'يوجد ملف تحكيم مرتبط بهذا النزاع';
  end if;
  if length(trim(coalesce(p_title, ''))) < 5 or length(trim(coalesce(p_summary, ''))) < 30 then
    raise exception 'اكتب عنوانًا وملخصًا للطلب (لا يُنقل شيء من ملف الوساطة تلقائيًا)';
  end if;
  if p_value is null or p_value <= 0 then raise exception 'قيمة النزاع غير صالحة'; end if;
  select id into v_rules from public.legal_documents where kind = 'arbitration_rules' and is_current;
  if v_rules is null then raise exception 'لا توجد قواعد تحكيم منشورة'; end if;
  v_resp := case when v_uid = d.claimant_id then d.respondent_id else d.claimant_id end;
  insert into public.arbitrations (source_dispute_id, title, summary, dispute_value_egp, prior_clause, claimant_id, respondent_id, created_by, rules_document_id)
  values (p_dispute, trim(p_title), trim(p_summary), p_value, coalesce(p_prior_clause, false), v_uid, v_resp, v_uid, v_rules)
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.respond_escalation(p_arb uuid, p_accept boolean, p_reason text default null) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); a public.arbitrations;
begin
  select * into a from public.arbitrations where id = p_arb for update;
  if not found or v_uid is distinct from a.respondent_id then raise exception 'غير مصرح'; end if;
  if a.status <> 'proposed' then raise exception 'تم الرد على هذا الطلب'; end if;
  if p_accept then
    if not public.arb_has_rules(p_arb, v_uid) then raise exception 'اقرأ قواعد التحكيم واقبلها قبل الموافقة'; end if;
    update public.arbitrations set status = 'agreement' where id = p_arb;
  else
    update public.arbitrations set status = 'cancelled', outcome = 'declined', closed_at = now(), closed_by = v_uid,
           outcome_reason = left(nullif(trim(p_reason), ''), 500) where id = p_arb;
  end if;
end $$;

create or replace function public.withdraw_arbitration(p_arb uuid, p_reason text default null) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); a public.arbitrations;
begin
  select * into a from public.arbitrations where id = p_arb for update;
  if not found or (v_uid is distinct from a.claimant_id and v_uid is distinct from a.respondent_id) then raise exception 'غير مصرح'; end if;
  if a.status not in ('proposed', 'agreement', 'selection') then
    raise exception 'لا يُسحب الملف بعد تعيين المحكّم؛ للمحكّم وحده إنهاء الإجراءات';
  end if;
  update public.arb_assignments set status = 'rejected', responded_at = now() where arbitration_id = p_arb and status in ('proposed', 'approved');
  update public.arbitrations set status = 'cancelled', closed_at = now(), closed_by = v_uid,
         outcome = case when v_uid = a.claimant_id then 'withdrawn' else 'declined' end,
         outcome_reason = left(nullif(trim(p_reason), ''), 500) where id = p_arb;
end $$;

-- ------------------------------------------------------------ evidence: server-only
create or replace function public.accept_arb_rules(p_document uuid, p_arb uuid, p_ip text, p_ua text) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); l public.legal_documents; a public.arbitrations;
begin
  if v_uid is null then raise exception 'يجب تسجيل الدخول'; end if;
  select * into l from public.legal_documents where id = p_document;
  if not found or l.kind <> 'arbitration_rules' then raise exception 'الوثيقة غير صحيحة'; end if;
  select * into a from public.arbitrations where id = p_arb;
  if not found or l.id <> a.rules_document_id then raise exception 'نسخة قواعد التحكيم لا تطابق النسخة المعتمدة لهذا الملف'; end if;
  if public.is_admin() or not public.arb_is_member(p_arb) then raise exception 'غير مصرح'; end if;
  insert into public.consents (user_id, document_id, arbitration_id, body_hash, ip_address, user_agent)
  values (v_uid, l.id, p_arb, l.body_hash, left(p_ip, 100), left(p_ua, 300)) on conflict do nothing;
end $$;

create or replace function public.accept_arb_rules_srv(p_actor uuid, p_aal text, p_document uuid, p_arb uuid, p_ip text, p_ua text)
returns void language plpgsql security definer set search_path = public as $$
begin perform public.act_as(p_actor, p_aal); perform public.accept_arb_rules(p_document, p_arb, p_ip, p_ua); end $$;

create or replace function public.register_arb_document_srv(
  p_actor uuid, p_aal text, p_arb uuid, p_path text, p_file_name text, p_mime text, p_size bigint, p_hash text, p_type text
) returns uuid language plpgsql security definer set search_path = public as $$
declare a public.arbitrations; v_id uuid;
begin
  perform public.act_as(p_actor, p_aal);
  if public.is_admin() or not public.arb_is_member(p_arb) then raise exception 'غير مصرح'; end if;
  if not public.arb_has_rules(p_arb, p_actor) then raise exception 'يجب قبول قواعد التحكيم أولًا'; end if;
  select * into a from public.arbitrations where id = p_arb;
  if a.status in ('closed', 'cancelled') then raise exception 'الملف منتهٍ: لا يمكن إضافة مستندات'; end if;
  if p_type not in ('arbitration_agreement', 'exhibit', 'procedural', 'award_signed', 'other') then raise exception 'نوع المستند غير صالح'; end if;
  if p_type = 'arbitration_agreement' then
    if p_actor not in (a.claimant_id, a.respondent_id) or a.status <> 'agreement' then raise exception 'يرفع أحد الطرفين اتفاق التحكيم في مرحلة الاتفاق فقط'; end if;
    if exists (select 1 from public.arb_agreement_confirmations where arbitration_id = p_arb) then raise exception 'أُكّد اتفاق التحكيم فلا يُستبدل'; end if;
  elsif p_type = 'award_signed' then
    if a.arbitrator_id is distinct from p_actor or a.status <> 'deliberation' then raise exception 'يرفع المحكّم الحكم الموقَّع في مرحلة المداولة فقط'; end if;
  elsif p_type = 'procedural' then
    if a.arbitrator_id is distinct from p_actor then raise exception 'المستندات الإجرائية من المحكّم'; end if;
  elsif p_type = 'exhibit' then
    if p_actor not in (a.claimant_id, a.respondent_id) or a.status <> 'active' then raise exception 'يرفع الطرفان المرفقات أثناء سير الإجراءات'; end if;
  end if;
  if p_path not like p_arb::text || '/%' then raise exception 'مسار الملف لا يخص هذا الملف'; end if;
  if p_hash !~ '^[0-9a-f]{64}$' then raise exception 'بصمة الملف غير صالحة'; end if;
  if not (p_mime = any (public.allowed_mime_types())) then raise exception 'نوع الملف غير مسموح'; end if;
  if p_size is null or p_size <= 0 or p_size > 10485760 then raise exception 'حجم الملف غير صالح'; end if;
  if not exists (select 1 from storage.objects where bucket_id = 'documents' and name = p_path) then raise exception 'الملف غير موجود في التخزين'; end if;
  insert into public.arb_documents (arbitration_id, uploaded_by, file_name, file_path, file_size, mime_type, sha256_hash, doc_type)
  values (p_arb, p_actor, left(p_file_name, 255), p_path, p_size, p_mime, p_hash, p_type) returning id into v_id;
  return v_id;
end $$;

create or replace function public.confirm_arb_agreement(p_arb uuid, p_doc uuid, p_ip text, p_ua text) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); a public.arbitrations; n int; k int;
begin
  select * into a from public.arbitrations where id = p_arb for update;
  if not found or (v_uid is distinct from a.claimant_id and v_uid is distinct from a.respondent_id) then raise exception 'غير مصرح'; end if;
  if a.status <> 'agreement' then raise exception 'ليس الملف في مرحلة اتفاق التحكيم'; end if;
  if not public.arb_has_rules(p_arb, v_uid) then raise exception 'يجب قبول قواعد التحكيم أولًا'; end if;
  if not exists (select 1 from public.arb_documents where id = p_doc and arbitration_id = p_arb and doc_type = 'arbitration_agreement') then
    raise exception 'اختر ملف اتفاق التحكيم المرفوع';
  end if;
  begin
    insert into public.arb_agreement_confirmations (arbitration_id, user_id, document_id, ip_address, user_agent)
    values (p_arb, v_uid, p_doc, left(p_ip, 100), left(p_ua, 300));
  exception when unique_violation then raise exception 'أكّدت من قبل';
  end;
  select count(distinct user_id), count(distinct document_id) into n, k from public.arb_agreement_confirmations where arbitration_id = p_arb;
  if n = 2 and k = 1 then update public.arbitrations set status = 'selection' where id = p_arb; end if;
end $$;

create or replace function public.confirm_arb_agreement_srv(p_actor uuid, p_aal text, p_arb uuid, p_doc uuid, p_ip text, p_ua text)
returns void language plpgsql security definer set search_path = public as $$
begin perform public.act_as(p_actor, p_aal); perform public.confirm_arb_agreement(p_arb, p_doc, p_ip, p_ua); end $$;

-- ------------------------------------------------------------ choosing the arbitrator
create or replace function public.propose_arbitrator(p_arb uuid, p_arbitrator uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); a public.arbitrations;
begin
  select * into a from public.arbitrations where id = p_arb for update;
  if not found or (v_uid is distinct from a.claimant_id and v_uid is distinct from a.respondent_id) then raise exception 'غير مصرح'; end if;
  if not public.arb_has_rules(p_arb, v_uid) then raise exception 'يجب قبول قواعد التحكيم أولًا'; end if;
  if a.status <> 'selection' then raise exception 'لا يُختار المحكّم في هذه المرحلة'; end if;
  if not exists (select 1 from public.profiles where id = p_arbitrator and role = 'arbitrator' and kyc_status = 'verified') then
    raise exception 'المحكّم غير موجود أو غير معتمد';
  end if;
  if p_arbitrator in (a.claimant_id, a.respondent_id) then raise exception 'لا يكون أحد الطرفين محكّمًا'; end if;
  if a.source_dispute_id is not null and (
       exists (select 1 from public.disputes d where d.id = a.source_dispute_id and d.mediator_id = p_arbitrator)
    or exists (select 1 from public.mediator_assignments m where m.dispute_id = a.source_dispute_id and m.mediator_id = p_arbitrator and m.status in ('approved', 'accepted', 'ended'))) then
    raise exception 'لا يجوز لمن عمل وسيطًا في الوساطة السابقة أن يكون محكّمًا في هذا الملف';
  end if;
  if exists (select 1 from public.arb_assignments where arbitration_id = p_arb and status in ('proposed', 'approved')) then
    raise exception 'يوجد اقتراح محكّم قيد الانتظار';
  end if;
  insert into public.arb_assignments (arbitration_id, arbitrator_id, proposed_by) values (p_arb, p_arbitrator, v_uid);
end $$;

create or replace function public.party_respond_arbitrator(p_assignment uuid, p_approve boolean) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); s public.arb_assignments; a public.arbitrations;
begin
  select * into s from public.arb_assignments where id = p_assignment for update;
  if not found then raise exception 'الاقتراح غير موجود'; end if;
  select * into a from public.arbitrations where id = s.arbitration_id;
  if (v_uid is distinct from a.claimant_id and v_uid is distinct from a.respondent_id) or v_uid = s.proposed_by then
    raise exception 'الرد على الاقتراح من حق الطرف الآخر فقط';
  end if;
  if not public.arb_has_rules(a.id, v_uid) then raise exception 'يجب قبول قواعد التحكيم أولًا'; end if;
  if s.status <> 'proposed' then raise exception 'تم الرد على هذا الاقتراح'; end if;
  update public.arb_assignments set status = case when p_approve then 'approved' else 'rejected' end, responded_at = now() where id = s.id;
end $$;

create or replace function public.arbitrator_respond(p_assignment uuid, p_accept boolean, p_disclosure text default null) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); s public.arb_assignments; a public.arbitrations;
begin
  perform public.require_mfa();
  select * into s from public.arb_assignments where id = p_assignment for update;
  if not found or s.arbitrator_id <> v_uid then raise exception 'غير مصرح'; end if;
  if s.status <> 'approved' then raise exception 'الاقتراح لم يُعتمد من الطرفين بعد'; end if;
  select * into a from public.arbitrations where id = s.arbitration_id for update;
  if p_accept then
    if not public.arb_has_rules(a.id, v_uid) then raise exception 'اقرأ قواعد التحكيم واقبلها قبل قبول المهمة'; end if;
    if length(trim(coalesce(p_disclosure, ''))) < 30 then
      raise exception 'اكتب إقرار الاستقلال والحياد (30 حرفًا على الأقل) متضمنًا أي علاقة بالطرفين أو بالنزاع';
    end if;
    update public.arb_assignments set status = 'accepted', responded_at = now(), disclosure = trim(p_disclosure), disclosed_at = now() where id = s.id;
    update public.arbitrations set arbitrator_id = v_uid, status = 'active' where id = a.id;
  else
    update public.arb_assignments set status = 'rejected', responded_at = now() where id = s.id;
  end if;
end $$;

create or replace function public.arbitrator_withdraw(p_arb uuid, p_reason text default null) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); a public.arbitrations;
begin
  perform public.require_mfa();
  select * into a from public.arbitrations where id = p_arb for update;
  if not found or a.arbitrator_id is distinct from v_uid then raise exception 'غير مصرح'; end if;
  if a.status not in ('active', 'deliberation') then raise exception 'لا يمكن الانسحاب في هذه المرحلة'; end if;
  update public.arb_assignments set status = 'ended', responded_at = now(), ended_reason = left(nullif(trim(p_reason), ''), 500)
   where arbitration_id = p_arb and arbitrator_id = v_uid and status = 'accepted';
  update public.arb_hearings set status = 'cancelled' where arbitration_id = p_arb and status = 'scheduled' and scheduled_at > now();
  delete from public.arb_awards where arbitration_id = p_arb and status = 'draft';   -- the departed arbitrator's draft is not handed on
  update public.arbitrations set arbitrator_id = null, status = 'selection' where id = p_arb;
end $$;

-- ------------------------------------------------------------ procedure
create or replace function public.set_arb_step(p_arb uuid, p_kind text, p_party text, p_due_at timestamptz, p_note text default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); a public.arbitrations; v_seq int; v_id uuid;
begin
  perform public.require_mfa();
  select * into a from public.arbitrations where id = p_arb for update;
  if not found or a.arbitrator_id is distinct from v_uid then raise exception 'المحكّم وحده يحدد الجدول الإجرائي'; end if;
  if a.status <> 'active' then raise exception 'لا تُضاف مواعيد في هذه المرحلة'; end if;
  if p_due_at <= now() then raise exception 'الموعد النهائي يجب أن يكون في المستقبل'; end if;
  select coalesce(max(seq), 0) + 1 into v_seq from public.arb_steps where arbitration_id = p_arb;
  insert into public.arb_steps (arbitration_id, seq, kind, party, due_at, note, created_by)
  values (p_arb, v_seq, p_kind, p_party, p_due_at, left(nullif(trim(p_note), ''), 500), v_uid) returning id into v_id;
  return v_id;
end $$;

create or replace function public.extend_arb_step(p_step uuid, p_due_at timestamptz) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); t public.arb_steps; a public.arbitrations;
begin
  perform public.require_mfa();
  select * into t from public.arb_steps where id = p_step for update;
  if not found then raise exception 'الخطوة غير موجودة'; end if;
  select * into a from public.arbitrations where id = t.arbitration_id;
  if a.arbitrator_id is distinct from v_uid or a.status <> 'active' then raise exception 'غير مصرح'; end if;
  if exists (select 1 from public.arb_submissions where step_id = p_step) then raise exception 'قُدِّمت المذكرة فلا يُمدَّد موعدها'; end if;
  if p_due_at <= now() then raise exception 'الموعد النهائي يجب أن يكون في المستقبل'; end if;
  update public.arb_steps set due_at = p_due_at where id = p_step;
end $$;

create or replace function public.submit_arb_statement(p_step uuid, p_body text, p_document_ids uuid[] default '{}') returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); t public.arb_steps; a public.arbitrations; v_role text; n int;
begin
  select * into t from public.arb_steps where id = p_step for update;
  if not found then raise exception 'الخطوة غير موجودة'; end if;
  select * into a from public.arbitrations where id = t.arbitration_id;
  v_role := case when v_uid = a.claimant_id then 'claimant' when v_uid = a.respondent_id then 'respondent' end;
  if v_role is null or v_role <> t.party then raise exception 'هذه الخطوة ليست من حقك'; end if;
  if a.status <> 'active' then raise exception 'انتهت مرحلة تبادل المذكرات'; end if;
  if not public.arb_has_rules(a.id, v_uid) then raise exception 'يجب قبول قواعد التحكيم أولًا'; end if;
  if exists (select 1 from public.arb_submissions where step_id = p_step) then raise exception 'قدّمت مذكرتك لهذه الخطوة من قبل'; end if;
  if length(trim(coalesce(p_body, ''))) < 20 then raise exception 'نص المذكرة قصير جدًا'; end if;
  select count(*) into n from public.arb_documents where id = any (p_document_ids) and arbitration_id = a.id and uploaded_by = v_uid;
  if n <> coalesce(array_length(p_document_ids, 1), 0) then raise exception 'مرفقات غير صالحة: لا يُرفق إلا ما رفعتَه في هذا الملف'; end if;
  insert into public.arb_submissions (step_id, arbitration_id, submitted_by, body, document_ids, late)
  values (p_step, a.id, v_uid, trim(p_body), coalesce(p_document_ids, '{}'), now() > t.due_at);
end $$;

create or replace function public.schedule_arb_hearing(p_arb uuid, p_at timestamptz, p_minutes int) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); a public.arbitrations; v_no int; v_id uuid;
begin
  perform public.require_mfa();
  select * into a from public.arbitrations where id = p_arb for update;
  if not found or a.arbitrator_id is distinct from v_uid then raise exception 'المحكّم وحده يحدد الجلسات'; end if;
  if a.status <> 'active' then raise exception 'لا تُجدول جلسات في هذه المرحلة'; end if;
  if not (public.arb_has_rules(p_arb, a.claimant_id) and public.arb_has_rules(p_arb, a.respondent_id) and public.arb_has_rules(p_arb, a.arbitrator_id)) then
    raise exception 'لا تُجدول جلسة قبل قبول الطرفين والمحكّم لقواعد التحكيم';
  end if;
  if p_at < now() - interval '1 hour' then raise exception 'موعد الجلسة في الماضي'; end if;
  select coalesce(max(number), 0) + 1 into v_no from public.arb_hearings where arbitration_id = p_arb;
  insert into public.arb_hearings (arbitration_id, number, scheduled_at, duration_minutes) values (p_arb, v_no, p_at, p_minutes) returning id into v_id;
  return v_id;
end $$;

create or replace function public.close_proceedings(p_arb uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); a public.arbitrations;
begin
  perform public.require_mfa();
  select * into a from public.arbitrations where id = p_arb for update;
  if not found or a.arbitrator_id is distinct from v_uid then raise exception 'غير مصرح'; end if;
  if a.status <> 'active' then raise exception 'ليس الملف في مرحلة الإجراءات'; end if;
  update public.arb_hearings set status = 'cancelled' where arbitration_id = p_arb and status = 'scheduled' and scheduled_at > now();
  update public.arbitrations set status = 'deliberation' where id = p_arb;
end $$;

-- ------------------------------------------------------------ the award (signed on paper, scan recorded here)
create or replace function public.save_award_draft(p_arb uuid, p_text text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare v_uid uuid := auth.uid(); a public.arbitrations; v_hash text;
begin
  perform public.require_mfa();
  select * into a from public.arbitrations where id = p_arb for update;
  if not found or a.arbitrator_id is distinct from v_uid then raise exception 'المحكّم وحده يصوغ مسودة الحكم'; end if;
  if a.status <> 'deliberation' then raise exception 'تُصاغ مسودة الحكم بعد إقفال الإجراءات'; end if;
  if length(trim(coalesce(p_text, ''))) < 100 then raise exception 'نص المسودة قصير جدًا'; end if;
  v_hash := encode(digest(convert_to(p_text, 'UTF8'), 'sha256'), 'hex');
  if exists (select 1 from public.arb_awards where arbitration_id = p_arb) then
    update public.arb_awards set draft_text = p_text, draft_hash = v_hash, version = version + 1
     where arbitration_id = p_arb and status = 'draft';
    if not found then raise exception 'صدر الحكم فلا تُعدَّل مسودته'; end if;
  else
    insert into public.arb_awards (arbitration_id, draft_text, draft_hash, created_by) values (p_arb, p_text, v_hash, v_uid);
  end if;
end $$;

create or replace function public.issue_award(p_arb uuid, p_signed_doc uuid, p_award_date date) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); a public.arbitrations; w public.arb_awards;
begin
  perform public.require_mfa();
  select * into a from public.arbitrations where id = p_arb for update;
  if not found or a.arbitrator_id is distinct from v_uid then raise exception 'غير مصرح'; end if;
  if a.status <> 'deliberation' then raise exception 'ليس الملف في مرحلة المداولة'; end if;
  select * into w from public.arb_awards where arbitration_id = p_arb for update;
  if not found or w.status <> 'draft' then raise exception 'لا توجد مسودة حكم'; end if;
  if w.draft_text ~ '\[[^\]]*\]' then raise exception 'مسودة الحكم تحتوي أقواسًا [..] لم تُستبدل'; end if;
  if not exists (select 1 from public.arb_documents where id = p_signed_doc and arbitration_id = p_arb and doc_type = 'award_signed' and uploaded_by = v_uid) then
    raise exception 'ارفع مسح الحكم الموقَّع أولًا';
  end if;
  if p_award_date is null or p_award_date > (now() at time zone 'Africa/Cairo')::date then raise exception 'تاريخ الحكم غير صالح'; end if;
  update public.arb_awards set status = 'issued', signed_document_id = p_signed_doc, award_date = p_award_date, issued_at = now() where id = w.id;
  update public.arbitrations set status = 'closed', outcome = 'award_issued', closed_at = now(), closed_by = v_uid where id = p_arb;
end $$;

create or replace function public.terminate_arbitration(p_arb uuid, p_reason text default null) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); a public.arbitrations;
begin
  perform public.require_mfa();
  select * into a from public.arbitrations where id = p_arb for update;
  if not found or a.arbitrator_id is distinct from v_uid then raise exception 'غير مصرح'; end if;
  if a.status not in ('active', 'deliberation') then raise exception 'لا يمكن إنهاء الإجراءات في هذه المرحلة'; end if;
  update public.arb_hearings set status = 'cancelled' where arbitration_id = p_arb and status = 'scheduled' and scheduled_at > now();
  update public.arbitrations set status = 'closed', outcome = 'terminated', closed_at = now(), closed_by = v_uid,
         outcome_reason = left(nullif(trim(p_reason), ''), 500) where id = p_arb;
end $$;

-- ------------------------------------------------------------ RLS
alter table public.arbitrations enable row level security;
alter table public.arb_assignments enable row level security;
alter table public.arb_documents enable row level security;
alter table public.arb_agreement_confirmations enable row level security;
alter table public.arb_steps enable row level security;
alter table public.arb_submissions enable row level security;
alter table public.arb_hearings enable row level security;
alter table public.arb_awards enable row level security;

create policy arbitrations_select on public.arbitrations for select to authenticated using (public.arb_can_read(id));
create policy arb_assignments_select on public.arb_assignments for select to authenticated using (public.arb_is_member(arbitration_id));
create policy arb_documents_select on public.arb_documents for select to authenticated using (public.arb_can_read(arbitration_id));
create policy arb_confirmations_select on public.arb_agreement_confirmations for select to authenticated using (user_id = auth.uid() or public.is_admin());
create policy arb_steps_select on public.arb_steps for select to authenticated using (public.arb_can_read(arbitration_id));
create policy arb_submissions_select on public.arb_submissions for select to authenticated using (public.arb_can_read(arbitration_id));
create policy arb_hearings_select on public.arb_hearings for select to authenticated using (public.arb_can_read(arbitration_id));
-- A draft is the arbitrator's alone (not the parties', not the admin's); an issued award is visible to those who may read the file.
create policy arb_awards_select on public.arb_awards for select to authenticated using (
  (status = 'draft' and exists (select 1 from public.arbitrations a where a.id = arbitration_id and a.arbitrator_id = auth.uid()) and public.mfa_satisfied())
  or (status = 'issued' and public.arb_can_read(arbitration_id)));

revoke all on public.arbitrations, public.arb_assignments, public.arb_documents, public.arb_agreement_confirmations,
  public.arb_steps, public.arb_submissions, public.arb_hearings, public.arb_awards from anon;
revoke insert, update, delete, truncate on public.arbitrations, public.arb_assignments, public.arb_documents, public.arb_agreement_confirmations,
  public.arb_steps, public.arb_submissions, public.arb_hearings, public.arb_awards from authenticated;

-- files of an arbitration live in the same private bucket, under <arbitration id>/
drop policy documents_obj_read on storage.objects;
create policy documents_obj_read on storage.objects for select to authenticated using (bucket_id = 'documents' and (
  public.can_read_dispute(((storage.foldername(name))[1])::uuid) or public.arb_can_read(((storage.foldername(name))[1])::uuid)));
drop policy documents_obj_insert on storage.objects;
create policy documents_obj_insert on storage.objects for insert to authenticated with check (bucket_id = 'documents' and (
  (public.can_read_dispute(((storage.foldername(name))[1])::uuid) and public.dispute_is_open(((storage.foldername(name))[1])::uuid))
  or (public.arb_can_read(((storage.foldername(name))[1])::uuid) and public.arb_is_open(((storage.foldername(name))[1])::uuid))));

-- ------------------------------------------------------------ read-only views (whitelisted)
create or replace function public.arb_gate_info(p_arb uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare a public.arbitrations; l public.legal_documents; v_uid uuid := auth.uid();
begin
  if v_uid is null or not public.arb_is_member(p_arb) then return null; end if;
  select * into a from public.arbitrations where id = p_arb;
  select * into l from public.legal_documents where id = a.rules_document_id;
  return jsonb_build_object(
    'number', a.arb_number, 'status', a.status, 'outcome', a.outcome,
    'accepted', public.is_admin() or public.arb_has_rules(p_arb, v_uid),
    'role', case when public.is_admin() then 'admin' when v_uid = a.claimant_id then 'claimant' when v_uid = a.respondent_id then 'respondent'
                 when v_uid = a.arbitrator_id then 'arbitrator' else 'arbitrator_candidate' end,
    'assignment_id', (select s.id from public.arb_assignments s where s.arbitration_id = p_arb and s.arbitrator_id = v_uid and s.status = 'approved' limit 1),
    'doc', jsonb_build_object('id', l.id, 'version', l.version, 'title', l.title, 'body', l.body, 'is_placeholder', l.is_placeholder));
end $$;

create or replace function public.arb_rules_status(p_arb uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('user_id', c.user_id, 'accepted_at', c.accepted_at)), '[]'::jsonb)
  from public.consents c join public.arbitrations a on a.id = c.arbitration_id and a.rules_document_id = c.document_id
  where c.arbitration_id = p_arb and public.arb_is_member(p_arb);
$$;

create or replace function public.arb_confirmations(p_arb uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('user_id', c.user_id, 'document_id', c.document_id, 'confirmed_at', c.confirmed_at) order by c.confirmed_at), '[]'::jsonb)
  from public.arb_agreement_confirmations c where c.arbitration_id = p_arb and public.arb_can_read(p_arb);
$$;

create or replace function public.arb_disclosures(p_arb uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('arbitrator_id', s.arbitrator_id, 'status', s.status, 'disclosure', s.disclosure, 'disclosed_at', s.disclosed_at) order by s.created_at), '[]'::jsonb)
  from public.arb_assignments s where s.arbitration_id = p_arb and s.status in ('accepted', 'ended') and public.arb_can_read(p_arb);
$$;

create or replace function public.arb_timeline(p_arb uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.arb_can_read(p_arb) then return '[]'::jsonb; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'seq', a.seq, 'event_type', a.event_type, 'created_at', a.created_at, 'row_hash', a.row_hash,
      'actor_name', case when a.actor_id is null then 'النظام' when ap.role = 'admin' then 'مدير المنصة' else ap.full_name end,
      'new_state', jsonb_strip_nulls(jsonb_build_object(
        'status', a.new_state->>'status', 'outcome', a.new_state->>'outcome', 'file_name', a.new_state->>'file_name',
        'sha256_hash', a.new_state->>'sha256_hash', 'version', a.new_state->'version', 'kind', a.new_state->>'kind',
        'party', a.new_state->>'party', 'late', a.new_state->'late', 'doc_type', a.new_state->>'doc_type',
        'number', a.new_state->'number', 'arb_number', a.new_state->>'arb_number')),
      'previous_state', jsonb_strip_nulls(jsonb_build_object('status', a.previous_state->>'status'))) order by a.seq)
    from public.audit_logs a left join public.profiles ap on ap.id = a.actor_id
    where a.dispute_id = p_arb), '[]'::jsonb);
end $$;

create or replace function public.arbitrator_directory() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'name', p.full_name, 'bio', m.bio,
           'specializations', m.specializations, 'years_experience', m.years_experience) order by p.full_name), '[]'::jsonb)
  from public.profiles p join public.mediator_profiles m on m.id = p.id
  where auth.uid() is not null and p.role = 'arbitrator' and p.kyc_status = 'verified';
$$;

-- arbitrations linked to a mediation file (number and status only: the content stays behind the arbitration's own gate)
create or replace function public.linked_arbitrations(p_dispute uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'arb_number', a.arb_number, 'status', a.status)), '[]'::jsonb)
  from public.arbitrations a
  where a.source_dispute_id = p_dispute and public.can_read_dispute(p_dispute)
    and (auth.uid() in (a.claimant_id, a.respondent_id) or public.is_admin());
$$;

create or replace function public.arb_metrics() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'غير مصرح'; end if;
  return jsonb_build_object(
    'total', (select count(*) from public.arbitrations),
    'by_status', coalesce((select jsonb_object_agg(status, n) from (select status, count(*) n from public.arbitrations group by status) x), '{}'::jsonb),
    'outcomes', jsonb_build_object(
      'award_issued', (select count(*) from public.arbitrations where outcome = 'award_issued'),
      'terminated', (select count(*) from public.arbitrations where outcome = 'terminated'),
      'withdrawn', (select count(*) from public.arbitrations where outcome = 'withdrawn'),
      'declined', (select count(*) from public.arbitrations where outcome = 'declined')),
    'escalated_from_mediation', (select count(*) from public.arbitrations where source_dispute_id is not null),
    'mediations_without_settlement', (select count(*) from public.disputes where outcome = 'no_settlement'),
    'late_statements', (select count(*) from public.arb_submissions where late));
end $$;

-- ------------------------------------------------------------ grants
revoke execute on function
  public.arb_is_member(uuid), public.arb_has_rules(uuid, uuid), public.arb_can_read(uuid), public.arb_is_open(uuid),
  public.propose_escalation(uuid, text, text, numeric, boolean), public.respond_escalation(uuid, boolean, text),
  public.withdraw_arbitration(uuid, text), public.propose_arbitrator(uuid, uuid), public.party_respond_arbitrator(uuid, boolean),
  public.arbitrator_respond(uuid, boolean, text), public.arbitrator_withdraw(uuid, text),
  public.set_arb_step(uuid, text, text, timestamptz, text), public.extend_arb_step(uuid, timestamptz),
  public.submit_arb_statement(uuid, text, uuid[]), public.schedule_arb_hearing(uuid, timestamptz, int),
  public.close_proceedings(uuid), public.save_award_draft(uuid, text), public.issue_award(uuid, uuid, date),
  public.terminate_arbitration(uuid, text), public.arb_gate_info(uuid), public.arb_rules_status(uuid),
  public.arb_confirmations(uuid), public.arb_disclosures(uuid), public.arb_timeline(uuid), public.arbitrator_directory(),
  public.linked_arbitrations(uuid), public.arb_metrics(), public.my_actions(), public.profile_names(uuid[]),
  public.accept_arb_rules(uuid, uuid, text, text), public.confirm_arb_agreement(uuid, uuid, text, text),
  public.accept_arb_rules_srv(uuid, text, uuid, uuid, text, text), public.confirm_arb_agreement_srv(uuid, text, uuid, uuid, text, text),
  public.register_arb_document_srv(uuid, text, uuid, text, text, text, bigint, text, text)
  from public, anon, authenticated;
grant execute on function
  public.arb_is_member(uuid), public.arb_has_rules(uuid, uuid), public.arb_can_read(uuid), public.arb_is_open(uuid),
  public.propose_escalation(uuid, text, text, numeric, boolean), public.respond_escalation(uuid, boolean, text),
  public.withdraw_arbitration(uuid, text), public.propose_arbitrator(uuid, uuid), public.party_respond_arbitrator(uuid, boolean),
  public.arbitrator_respond(uuid, boolean, text), public.arbitrator_withdraw(uuid, text),
  public.set_arb_step(uuid, text, text, timestamptz, text), public.extend_arb_step(uuid, timestamptz),
  public.submit_arb_statement(uuid, text, uuid[]), public.schedule_arb_hearing(uuid, timestamptz, int),
  public.close_proceedings(uuid), public.save_award_draft(uuid, text), public.issue_award(uuid, uuid, date),
  public.terminate_arbitration(uuid, text), public.arb_gate_info(uuid), public.arb_rules_status(uuid),
  public.arb_confirmations(uuid), public.arb_disclosures(uuid), public.arb_timeline(uuid), public.arbitrator_directory(),
  public.linked_arbitrations(uuid), public.arb_metrics(), public.my_actions(), public.profile_names(uuid[])
  to authenticated;
grant execute on function
  public.accept_arb_rules_srv(uuid, text, uuid, uuid, text, text), public.confirm_arb_agreement_srv(uuid, text, uuid, uuid, text, text),
  public.register_arb_document_srv(uuid, text, uuid, text, text, text, bigint, text, text) to service_role;
