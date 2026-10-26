-- =====================================================================
-- Hayah ADR — failure paths. Run ONCE, AFTER hardening.sql.
--   * decline an invitation, withdraw a dispute, renew/redirect an invitation
--   * a mediator can step down and be replaced
--   * a mediation can end WITHOUT a settlement, and every dispute ends with a recorded outcome
--   * closed / cancelled disputes are read-only
--   * metrics now separate settled / no settlement / withdrawn / declined / still open
-- =====================================================================

alter table public.disputes
  add column closed_at timestamptz,
  add column closed_by uuid references public.profiles(id),
  add column outcome text check (outcome in ('settled', 'no_settlement', 'withdrawn', 'declined')),
  add column outcome_reason text;

alter table public.invitations drop constraint invitations_status_check;
alter table public.invitations add constraint invitations_status_check
  check (status in ('pending', 'accepted', 'expired', 'declined', 'cancelled'));
alter table public.mediator_assignments drop constraint mediator_assignments_status_check;
alter table public.mediator_assignments add constraint mediator_assignments_status_check
  check (status in ('proposed', 'approved', 'accepted', 'rejected', 'ended'));
alter table public.mediator_assignments add column ended_reason text;

create or replace function public.dispute_is_open(p_dispute uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.disputes where id = p_dispute and status not in ('closed', 'cancelled'));
$$;

-- Respondent says no, from the invitation link.
create or replace function public.decline_invitation(p_token text, p_reason text default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_email text; inv public.invitations;
begin
  if v_uid is null then raise exception 'يجب تسجيل الدخول'; end if;
  select * into inv from public.invitations where token = p_token for update;
  if not found then raise exception 'رابط الدعوة غير صالح'; end if;
  select email into v_email from public.profiles where id = v_uid;
  if lower(v_email) <> inv.invited_email then raise exception 'هذه الدعوة موجّهة إلى بريد إلكتروني آخر'; end if;
  if inv.status <> 'pending' then raise exception 'لم تعد الدعوة قائمة'; end if;
  update public.invitations set status = 'declined' where id = inv.id;
  update public.disputes set status = 'cancelled', outcome = 'declined', closed_at = now(), closed_by = v_uid,
         outcome_reason = left(nullif(trim(p_reason), ''), 500)
   where id = inv.dispute_id and status = 'invited';
  return inv.dispute_id;
end $$;

-- Either party leaves before a mediator has taken the case.
create or replace function public.withdraw_dispute(p_dispute uuid, p_reason text default null) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); d public.disputes;
begin
  select * into d from public.disputes where id = p_dispute for update;
  if not found or (v_uid is distinct from d.claimant_id and v_uid is distinct from d.respondent_id) then
    raise exception 'غير مصرح';
  end if;
  if d.status not in ('invited', 'accepted', 'mediator_selection') then
    raise exception 'لا يمكن سحب النزاع في هذه المرحلة. أنهِ الوساطة بدلًا من ذلك';
  end if;
  update public.invitations set status = 'cancelled' where dispute_id = p_dispute and status = 'pending';
  update public.mediator_assignments set status = 'rejected', responded_at = now()
   where dispute_id = p_dispute and status in ('proposed', 'approved');
  update public.disputes set status = 'cancelled', closed_at = now(), closed_by = v_uid,
         outcome = case when v_uid = d.claimant_id then 'withdrawn' else 'declined' end,
         outcome_reason = left(nullif(trim(p_reason), ''), 500)
   where id = p_dispute;
end $$;

-- Invitation expired, or the e-mail address was wrong: issue a fresh link (optionally to another address).
create or replace function public.resend_invitation(p_dispute uuid, p_email text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); d public.disputes; v_email text; v_token text; v_own text;
begin
  select * into d from public.disputes where id = p_dispute for update;
  if not found or d.claimant_id is distinct from v_uid then raise exception 'غير مصرح'; end if;
  if d.status <> 'invited' then raise exception 'لا تُجدَّد الدعوة بعد قبولها أو إنهاء النزاع'; end if;
  select email into v_own from public.profiles where id = v_uid;
  v_email := coalesce(lower(trim(nullif(p_email, ''))),
    (select invited_email from public.invitations where dispute_id = p_dispute order by created_at desc limit 1));
  if v_email = lower(v_own) then raise exception 'لا يمكنك دعوة نفسك كطرف ثانٍ في النزاع'; end if;
  update public.invitations set status = 'expired' where dispute_id = p_dispute and status = 'pending';
  v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  insert into public.invitations (dispute_id, invited_email, token, expires_at)
  values (p_dispute, v_email, v_token, now() + interval '7 days');
  return jsonb_build_object('token', v_token, 'email', v_email);
end $$;

-- The mediator steps down; the parties choose a new one. The old mediator loses all access.
create or replace function public.mediator_withdraw(p_dispute uuid, p_reason text default null) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); d public.disputes;
begin
  select * into d from public.disputes where id = p_dispute for update;
  if not found or d.mediator_id is distinct from v_uid then raise exception 'غير مصرح'; end if;
  if d.status not in ('active', 'settlement_draft') then raise exception 'لا يمكن الانسحاب في هذه المرحلة'; end if;
  if exists (select 1 from public.settlements where dispute_id = p_dispute and status <> 'draft') then
    raise exception 'فُتح الاتفاق للتوقيع: لا يمكن الانسحاب قبل اكتمال التوقيع أو إنهاء الوساطة';
  end if;
  update public.mediator_assignments set status = 'ended', responded_at = now(),
         ended_reason = left(nullif(trim(p_reason), ''), 500)
   where dispute_id = p_dispute and mediator_id = v_uid and status = 'accepted';
  update public.sessions set status = 'cancelled'
   where dispute_id = p_dispute and status = 'scheduled' and scheduled_at > now();
  update public.disputes set mediator_id = null, status = 'mediator_selection' where id = p_dispute;
end $$;

-- Ends the file with a recorded outcome. Mediation is voluntary: any party (or the mediator) may end it.
create or replace function public.close_dispute(p_dispute uuid, p_outcome text, p_reason text default null) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); d public.disputes;
begin
  select * into d from public.disputes where id = p_dispute for update;
  if not found or not (public.is_admin() or v_uid = d.claimant_id or v_uid = d.respondent_id or v_uid = d.mediator_id) then
    raise exception 'غير مصرح';
  end if;
  if p_outcome = 'settled' then
    if d.status <> 'signed' then raise exception 'لا يُغلق الملف كتسوية قبل اكتمال التوقيع'; end if;
  elsif p_outcome = 'no_settlement' then
    if d.status not in ('active', 'settlement_draft') then raise exception 'لا يمكن إنهاء الوساطة بلا تسوية في هذه المرحلة'; end if;
  else
    raise exception 'نتيجة غير صالحة';
  end if;
  update public.sessions set status = 'cancelled'
   where dispute_id = p_dispute and status = 'scheduled' and scheduled_at > now();
  update public.disputes set status = 'closed', outcome = p_outcome, closed_at = now(), closed_by = v_uid,
         outcome_reason = left(nullif(trim(p_reason), ''), 500)
   where id = p_dispute;
end $$;

-- Same as before, with NULL-safe membership (respondent_id is NULL while the invitation is pending).
create or replace function public.propose_mediator(p_dispute uuid, p_mediator uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); d public.disputes;
begin
  select * into d from public.disputes where id = p_dispute for update;
  if not found or (v_uid is distinct from d.claimant_id and v_uid is distinct from d.respondent_id) then
    raise exception 'غير مصرح';
  end if;
  if not public.has_agreement(p_dispute, v_uid) then raise exception 'يجب قبول اتفاقية الوساطة أولًا'; end if;
  if d.status not in ('accepted', 'mediator_selection') then raise exception 'لا يمكن اختيار وسيط في هذه المرحلة'; end if;
  if not exists (select 1 from public.profiles where id = p_mediator and role = 'mediator') then
    raise exception 'الوسيط غير موجود';
  end if;
  if exists (select 1 from public.mediator_assignments where dispute_id = p_dispute and status in ('proposed', 'approved')) then
    raise exception 'يوجد اقتراح وسيط قيد الانتظار';
  end if;
  insert into public.mediator_assignments (dispute_id, mediator_id, proposed_by) values (p_dispute, p_mediator, v_uid);
  update public.disputes set status = 'mediator_selection' where id = p_dispute;
end $$;

-- Gate info now also tells the page who the caller is and whether the file already ended.
create or replace function public.dispute_gate_info(p_dispute uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d public.disputes; l public.legal_documents; v_uid uuid := auth.uid();
begin
  if v_uid is null or not public.is_dispute_member(p_dispute) then return null; end if;
  select * into d from public.disputes where id = p_dispute;
  select * into l from public.legal_documents where id = d.agreement_document_id;
  return jsonb_build_object(
    'dispute_number', d.dispute_number,
    'accepted', public.is_admin() or public.has_agreement(p_dispute, v_uid),
    'status', d.status, 'outcome', d.outcome,
    'role', case when public.is_admin() then 'admin' when v_uid = d.claimant_id then 'claimant'
                 when v_uid = d.respondent_id then 'respondent' when v_uid = d.mediator_id then 'mediator'
                 else 'mediator_candidate' end,
    'assignment_id', (select a.id from public.mediator_assignments a
                      where a.dispute_id = p_dispute and a.mediator_id = v_uid and a.status = 'approved' limit 1),
    'doc', jsonb_build_object('id', l.id, 'version', l.version, 'title', l.title, 'body', l.body, 'is_placeholder', l.is_placeholder));
end $$;

create or replace function public.my_pending_agreements() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'dispute_number', d.dispute_number) order by d.created_at desc), '[]'::jsonb)
  from public.disputes d
  where auth.uid() is not null and not public.is_admin() and d.status not in ('closed', 'cancelled')
    and public.is_dispute_member(d.id) and not public.has_agreement(d.id, auth.uid());
$$;

-- Nothing can be uploaded into a closed or cancelled file.
drop policy documents_insert on public.documents;
create policy documents_insert on public.documents for insert to authenticated
  with check (uploaded_by = auth.uid() and public.is_dispute_member(dispute_id) and public.dispute_is_open(dispute_id)
              and (public.is_admin() or public.has_agreement(dispute_id, auth.uid())));
drop policy documents_obj_insert on storage.objects;
create policy documents_obj_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'documents'
              and public.can_read_dispute(((storage.foldername(name))[1])::uuid)
              and public.dispute_is_open(((storage.foldername(name))[1])::uuid));

-- Record snapshot now carries the outcome.
create or replace function public.build_dispute_record(p_dispute uuid, p_full_ip boolean) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare d public.disputes; v_chain jsonb;
begin
  select * into d from public.disputes where id = p_dispute;

  -- Re-computes the hash of every audit row of this dispute and checks its link to the previous row.
  with chk as (
    select a.seq,
      (a.row_hash = public.audit_row_hash(a)
       and a.prev_hash is not distinct from (select p.row_hash from public.audit_logs p where p.seq = a.seq - 1)) as ok
    from public.audit_logs a where a.dispute_id = p_dispute)
  select jsonb_build_object('checked', count(*), 'ok', coalesce(bool_and(ok), true),
                            'first_bad_seq', min(seq) filter (where not ok))
  into v_chain from chk;

  return jsonb_build_object(
    'dispute', jsonb_build_object('number', d.dispute_number, 'title', d.title, 'description', d.description,
      'type', d.dispute_type, 'value_egp', d.dispute_value_egp, 'status', d.status, 'created_at', d.created_at,
      'outcome', d.outcome, 'outcome_reason', d.outcome_reason, 'closed_at', d.closed_at),
    'parties', jsonb_build_object(
      'claimant', (select full_name from public.profiles where id = d.claimant_id),
      'respondent', (select full_name from public.profiles where id = d.respondent_id),
      'mediator', (select full_name from public.profiles where id = d.mediator_id)),
    'consents', coalesce((
      select jsonb_agg(jsonb_build_object('name', p.full_name, 'document', l.title, 'kind', l.kind, 'version', l.version,
        'document_hash', c.body_hash, 'accepted_at', c.accepted_at, 'ip', public.mask_ip(c.ip_address, p_full_ip))
        order by c.accepted_at)
      from public.consents c
      join public.legal_documents l on l.id = c.document_id
      join public.profiles p on p.id = c.user_id
      where c.dispute_id = p_dispute
         or (c.dispute_id is null and c.user_id in (d.claimant_id, d.respondent_id, d.mediator_id))), '[]'::jsonb),
    'documents', coalesce((
      select jsonb_agg(jsonb_build_object('file_name', x.file_name, 'type', x.document_type, 'size', x.file_size,
        'sha256', x.sha256_hash, 'uploaded_by', p.full_name, 'uploaded_at', x.created_at) order by x.created_at)
      from public.documents x join public.profiles p on p.id = x.uploaded_by
      where x.dispute_id = p_dispute), '[]'::jsonb),
    'sessions', coalesce((
      select jsonb_agg(jsonb_build_object('number', s.session_number, 'scheduled_at', s.scheduled_at,
        'duration_minutes', s.duration_minutes, 'status', s.status) order by s.session_number)
      from public.sessions s where s.dispute_id = p_dispute), '[]'::jsonb),
    'settlement', (
      select jsonb_build_object('status', s.status, 'version', s.version, 'content', s.content, 'content_hash', s.content_hash,
        'signatures', coalesce((
          select jsonb_agg(jsonb_build_object('name', p.full_name, 'party_role', g.party_role, 'signed_at', g.signed_at,
            'content_hash', g.content_hash, 'ip', public.mask_ip(g.ip_address, p_full_ip)) order by g.signed_at)
          from public.settlement_signatures g join public.profiles p on p.id = g.user_id
          where g.settlement_id = s.id), '[]'::jsonb))
      from public.settlements s where s.dispute_id = p_dispute),
    -- Only whitelisted, non-sensitive fields of each event (never invitation tokens).
    'timeline', coalesce((
      select jsonb_agg(jsonb_build_object('seq', a.seq, 'event_type', a.event_type, 'at', a.created_at,
        'actor', case when a.actor_id is null then 'النظام' when ap.role = 'admin' then 'مدير المنصة' else ap.full_name end,
        'state', jsonb_strip_nulls(jsonb_build_object(
          'status', a.new_state->>'status', 'prev_status', a.previous_state->>'status', 'outcome', a.new_state->>'outcome',
          'file_name', a.new_state->>'file_name', 'sha256_hash', a.new_state->>'sha256_hash',
          'session_number', a.new_state->'session_number', 'version', a.new_state->'version',
          'party_role', a.new_state->>'party_role', 'dispute_number', a.new_state->>'dispute_number',
          'invited_email', a.new_state->>'invited_email')),
        'row_hash', a.row_hash) order by a.seq)
      from public.audit_logs a left join public.profiles ap on ap.id = a.actor_id
      where a.dispute_id = p_dispute), '[]'::jsonb),
    'chain_check', v_chain);
end $$;

-- Metrics: outcomes.
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
    select d.id, d.status, d.outcome, d.created_at as t_created,
      max(s.at) filter (where s.st = 'accepted') as t_accepted,
      max(s.at) filter (where s.st = 'active') as t_active,
      max(s.at) filter (where s.st = 'settlement_draft') as t_draft,
      max(s.at) filter (where s.st = 'signed') as t_signed
    from public.disputes d left join stage s on s.dispute_id = d.id
    group by d.id, d.status, d.outcome, d.created_at
  )
  select jsonb_build_object(
    'funnel', jsonb_build_object(
      'created', count(*), 'accepted', count(t_accepted), 'active', count(t_active),
      'draft', count(t_draft), 'signed', count(t_signed)),
    'outcomes', jsonb_build_object(
      'settled', count(*) filter (where status in ('signed') or outcome = 'settled'),
      'no_settlement', count(*) filter (where outcome = 'no_settlement'),
      'withdrawn', count(*) filter (where outcome = 'withdrawn'),
      'declined', count(*) filter (where outcome = 'declined'),
      'open', count(*) filter (where outcome is null and status <> 'signed')),
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

revoke execute on function
  public.dispute_is_open(uuid), public.decline_invitation(text, text), public.withdraw_dispute(uuid, text),
  public.resend_invitation(uuid, text), public.mediator_withdraw(uuid, text), public.close_dispute(uuid, text, text)
  from public, anon;
grant execute on function
  public.dispute_is_open(uuid), public.decline_invitation(text, text), public.withdraw_dispute(uuid, text),
  public.resend_invitation(uuid, text), public.mediator_withdraw(uuid, text), public.close_dispute(uuid, text, text)
  to authenticated;
revoke execute on function public.build_dispute_record(uuid, boolean) from public, anon, authenticated;
