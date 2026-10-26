-- =====================================================================
-- Hayah ADR — hardening. Run ONCE, AFTER schema.sql, trial.sql, record.sql.
--   1. Audit hash v2: covers actor, dispute, entity type and previous state.
--      (Old rows keep verifying under the v1 formula via hash_version.)
--   2. Audit anchor: head hash can be copied outside the database.
--   3. Each dispute is pinned to ONE version of the mediation agreement.
--   4. Reading a dispute (and its documents, sessions, settlement, timeline,
--      storage objects) requires accepting that agreement — enforced by RLS.
--   5. EXECUTE grants tightened; consent status can't be probed by outsiders.
-- =====================================================================

-- ------------------------------------------------------ 1. audit hash v2
alter table public.audit_logs add column hash_version smallint not null default 1;

create or replace function public.audit_row_hash(a public.audit_logs) returns text
language sql stable set search_path = public, extensions as $$
  select encode(digest(
    case when a.hash_version >= 2 then
      a.seq::text || '|' || coalesce(a.prev_hash, '') || '|' || a.event_type || '|' ||
      coalesce(a.entity_type, '') || '|' || coalesce(a.entity_id::text, '') || '|' ||
      coalesce(a.dispute_id::text, '') || '|' || coalesce(a.actor_id::text, '') || '|' ||
      coalesce(a.previous_state::text, '') || '|' || coalesce(a.new_state::text, '') || '|' ||
      extract(epoch from a.created_at)::text
    else
      a.seq::text || '|' || coalesce(a.prev_hash, '') || '|' || a.event_type || '|' ||
      coalesce(a.entity_id::text, '') || '|' || coalesce(a.new_state::text, '') || '|' ||
      extract(epoch from a.created_at)::text
    end, 'sha256'), 'hex');
$$;

create or replace function public.audit_chain() returns trigger
language plpgsql set search_path = public, extensions as $$
declare last_row public.audit_logs;
begin
  perform pg_advisory_xact_lock(84720011);
  select * into last_row from public.audit_logs order by seq desc limit 1;
  new.seq := coalesce(last_row.seq, 0) + 1;
  new.prev_hash := last_row.row_hash;
  new.hash_version := 2;
  new.row_hash := public.audit_row_hash(new);
  return new;
end $$;

-- ------------------------------------------------------- 2. audit anchor
create or replace function public.audit_head() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce((select jsonb_build_object('seq', seq, 'row_hash', row_hash, 'at', created_at)
                   from public.audit_logs order by seq desc limit 1), '{}'::jsonb);
$$;
-- Only the server (service role) reads the head; it is emailed to the owner by /api/cron/anchor.
revoke execute on function public.audit_head() from public, anon, authenticated;
grant execute on function public.audit_head() to service_role;

create or replace function public.check_audit_anchor(p_seq bigint, p_hash text) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare r public.audit_logs; v_hash text := lower(trim(p_hash));
begin
  if not public.is_admin() then raise exception 'غير مصرح'; end if;
  select * into r from public.audit_logs where seq = p_seq;
  if not found then return jsonb_build_object('ok', false, 'reason', 'missing'); end if;
  if r.row_hash <> v_hash then return jsonb_build_object('ok', false, 'reason', 'mismatch'); end if;
  if r.row_hash <> public.audit_row_hash(r) then return jsonb_build_object('ok', false, 'reason', 'row_altered'); end if;
  return jsonb_build_object('ok', true, 'reason', 'match');
end $$;

-- ------------------------------------------- 3. one agreement version per dispute
alter table public.disputes add column agreement_document_id uuid references public.legal_documents(id);
update public.disputes d set agreement_document_id = coalesce(
  (select c.document_id from public.consents c join public.legal_documents l on l.id = c.document_id
   where c.dispute_id = d.id and l.kind = 'mediation_agreement' order by c.accepted_at limit 1),
  (select id from public.legal_documents where kind = 'mediation_agreement' and is_current));
alter table public.disputes alter column agreement_document_id set not null;

create or replace function public.create_dispute(
  p_title text, p_description text, p_type text, p_value numeric, p_email text, p_phone text
) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_email text; d public.disputes; v_token text; v_agreement uuid;
begin
  if v_uid is null then raise exception 'يجب تسجيل الدخول'; end if;
  select id into v_agreement from public.legal_documents where kind = 'mediation_agreement' and is_current;
  if v_agreement is null then raise exception 'لا توجد اتفاقية وساطة منشورة'; end if;
  select email into v_email from public.profiles where id = v_uid;
  if lower(trim(p_email)) = lower(v_email) then
    raise exception 'لا يمكنك دعوة نفسك كطرف ثانٍ في النزاع';
  end if;
  insert into public.disputes (title, description, dispute_type, dispute_value_egp, created_by, claimant_id, agreement_document_id)
  values (p_title, p_description, p_type, p_value, v_uid, v_uid, v_agreement) returning * into d;
  v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  insert into public.invitations (dispute_id, invited_email, invited_phone, token, expires_at)
  values (d.id, lower(trim(p_email)), nullif(trim(p_phone), ''), v_token, now() + interval '7 days');
  return jsonb_build_object('id', d.id, 'dispute_number', d.dispute_number, 'token', v_token);
end $$;

-- Consent counts only if it is for the exact version pinned to the dispute, and only members can ask.
create or replace function public.has_agreement(p_dispute uuid, p_user uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_dispute_member(p_dispute) and exists (
    select 1 from public.consents c
    join public.disputes d on d.id = c.dispute_id and d.agreement_document_id = c.document_id
    where c.user_id = p_user and c.dispute_id = p_dispute);
$$;

create or replace function public.accept_legal(p_document uuid, p_dispute uuid, p_ip text, p_ua text) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); l public.legal_documents; v_dispute uuid := p_dispute;
begin
  if v_uid is null then raise exception 'يجب تسجيل الدخول'; end if;
  select * into l from public.legal_documents where id = p_document;
  if not found then raise exception 'الوثيقة غير موجودة'; end if;
  if l.kind = 'mediation_agreement' then
    if v_dispute is null then raise exception 'اتفاقية الوساطة خاصة بنزاع محدد'; end if;
    if public.is_admin() or not public.is_dispute_member(v_dispute) then raise exception 'غير مصرح'; end if;
    if l.id <> (select agreement_document_id from public.disputes where id = v_dispute) then
      raise exception 'نسخة الاتفاقية لا تطابق النسخة المعتمدة لهذا النزاع';
    end if;
  else
    if not l.is_current then raise exception 'هذه النسخة لم تعد سارية. أعد تحميل الصفحة'; end if;
    v_dispute := null;
  end if;
  insert into public.consents (user_id, document_id, dispute_id, body_hash, ip_address, user_agent)
  values (v_uid, l.id, v_dispute, l.body_hash, left(p_ip, 100), left(p_ua, 300))
  on conflict do nothing;
end $$;

-- ------------------------------------------------- 4. read gate in RLS
create or replace function public.can_read_dispute(p_dispute uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and (
    public.is_admin() or (public.is_dispute_member(p_dispute) and public.has_agreement(p_dispute, auth.uid())));
$$;

-- What a member may see BEFORE accepting: the file number and the agreement text, nothing else.
create or replace function public.dispute_gate_info(p_dispute uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d public.disputes; l public.legal_documents;
begin
  if auth.uid() is null or not public.is_dispute_member(p_dispute) then return null; end if;
  select * into d from public.disputes where id = p_dispute;
  select * into l from public.legal_documents where id = d.agreement_document_id;
  return jsonb_build_object(
    'dispute_number', d.dispute_number,
    'accepted', public.is_admin() or public.has_agreement(p_dispute, auth.uid()),
    'doc', jsonb_build_object('id', l.id, 'version', l.version, 'title', l.title, 'body', l.body, 'is_placeholder', l.is_placeholder));
end $$;

create or replace function public.my_pending_agreements() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'dispute_number', d.dispute_number) order by d.created_at desc), '[]'::jsonb)
  from public.disputes d
  where auth.uid() is not null and not public.is_admin()
    and public.is_dispute_member(d.id) and not public.has_agreement(d.id, auth.uid());
$$;

drop policy disputes_select on public.disputes;
create policy disputes_select on public.disputes for select to authenticated using (public.can_read_dispute(id));
drop policy documents_select on public.documents;
create policy documents_select on public.documents for select to authenticated using (public.can_read_dispute(dispute_id));
drop policy sessions_select on public.sessions;
create policy sessions_select on public.sessions for select to authenticated using (public.can_read_dispute(dispute_id));
drop policy settlements_select on public.settlements;
create policy settlements_select on public.settlements for select to authenticated using (public.can_read_dispute(dispute_id));
drop policy signatures_select on public.settlement_signatures;
create policy signatures_select on public.settlement_signatures for select to authenticated using (public.can_read_dispute(dispute_id));
drop policy audit_select on public.audit_logs;
create policy audit_select on public.audit_logs for select to authenticated
  using (public.is_admin() or (dispute_id is not null and public.can_read_dispute(dispute_id)));

drop policy documents_obj_read on storage.objects;
create policy documents_obj_read on storage.objects for select to authenticated
  using (bucket_id = 'documents' and public.can_read_dispute(((storage.foldername(name))[1])::uuid));
drop policy documents_obj_insert on storage.objects;
create policy documents_obj_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'documents' and public.can_read_dispute(((storage.foldername(name))[1])::uuid));

-- ----------------------------------------------------- 5. EXECUTE grants
-- Helpers used inside RLS policies must stay executable by `authenticated`; everything that
-- changes state is closed to `anon` (and PUBLIC). Public on purpose: invitation_preview, verify_record.
revoke execute on function
  public.create_dispute(text, text, text, numeric, text, text), public.accept_invitation(text),
  public.propose_mediator(uuid, uuid), public.party_respond_mediator(uuid, boolean),
  public.mediator_respond(uuid, boolean), public.schedule_session(uuid, timestamptz, int),
  public.save_settlement(uuid, text), public.submit_settlement(uuid), public.sign_settlement(uuid, text, text),
  public.publish_legal_document(text, text, text, boolean), public.accept_legal(uuid, uuid, text, text),
  public.issue_dispute_record(uuid), public.verify_audit_chain(), public.admin_metrics(),
  public.check_audit_anchor(bigint, text), public.dispute_gate_info(uuid), public.my_pending_agreements(),
  public.has_platform_consent(), public.can_read_dispute(uuid), public.has_agreement(uuid, uuid),
  public.is_admin(), public.is_dispute_member(uuid), public.can_see_profile(uuid)
  from public, anon;
grant execute on function
  public.create_dispute(text, text, text, numeric, text, text), public.accept_invitation(text),
  public.propose_mediator(uuid, uuid), public.party_respond_mediator(uuid, boolean),
  public.mediator_respond(uuid, boolean), public.schedule_session(uuid, timestamptz, int),
  public.save_settlement(uuid, text), public.submit_settlement(uuid), public.sign_settlement(uuid, text, text),
  public.publish_legal_document(text, text, text, boolean), public.accept_legal(uuid, uuid, text, text),
  public.issue_dispute_record(uuid), public.verify_audit_chain(), public.admin_metrics(),
  public.check_audit_anchor(bigint, text), public.dispute_gate_info(uuid), public.my_pending_agreements(),
  public.has_platform_consent(), public.can_read_dispute(uuid), public.has_agreement(uuid, uuid),
  public.is_admin(), public.is_dispute_member(uuid), public.can_see_profile(uuid)
  to authenticated;
