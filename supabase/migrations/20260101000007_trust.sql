-- =====================================================================
-- Hayah ADR — trust boundary, data exposure, quotas. Run ONCE, AFTER mfa.sql.
--
--  A. Evidence is written ONLY by the server. Document registration, settlement
--     signing and consent acceptance are no longer callable by API users: the
--     server passes the verified actor and the IP / browser it observed itself, so
--     a client can no longer forge a document row, skip the password step or
--     choose the IP stored next to its signature.
--  B. Members no longer read raw audit / consent / signature / profile rows
--     (IP, browser, e-mail, phone, tokens). They get whitelisted views via RPC.
--  C. Fixes: settled-value metrics, bracket placeholders in the settlement text,
--     daily invitation quota, mediator directory limited to VERIFIED mediators.
--  D. Server-side rate limiting and a file-type allow-list for uploads.
-- =====================================================================

-- ------------------------------------------------ A. server-only evidence writes
create or replace function public.act_as(p_actor uuid, p_aal text default 'aal1') returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.profiles where id = p_actor) then raise exception 'مستخدم غير معروف'; end if;
  -- Transaction-local: audit triggers and helper functions now see the real actor and session level.
  perform set_config('request.jwt.claim.sub', p_actor::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', p_actor, 'aal', coalesce(p_aal, 'aal1'))::text, true);
end $$;

create or replace function public.allowed_mime_types() returns text[] language sql immutable as $$
  select array['application/pdf', 'image/png', 'image/jpeg', 'image/webp', 'text/plain',
    'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'];
$$;
update storage.buckets set allowed_mime_types = public.allowed_mime_types() where id = 'documents';

create or replace function public.accept_legal_srv(p_actor uuid, p_aal text, p_document uuid, p_dispute uuid, p_ip text, p_ua text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.act_as(p_actor, p_aal);
  perform public.accept_legal(p_document, p_dispute, p_ip, p_ua);
end $$;

create or replace function public.sign_settlement_srv(p_actor uuid, p_aal text, p_dispute uuid, p_ip text, p_ua text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.act_as(p_actor, p_aal);
  perform public.sign_settlement(p_dispute, p_ip, p_ua);
end $$;

create or replace function public.register_document_srv(
  p_actor uuid, p_aal text, p_dispute uuid, p_path text, p_file_name text,
  p_mime text, p_size bigint, p_hash text, p_type text
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_type text := case when p_type in ('contract', 'evidence', 'correspondence', 'other') then p_type else 'other' end;
begin
  perform public.act_as(p_actor, p_aal);
  if not public.is_dispute_member(p_dispute) then raise exception 'غير مصرح'; end if;
  if not public.is_admin() and not public.has_agreement(p_dispute, p_actor) then raise exception 'يجب قبول اتفاقية الوساطة أولًا'; end if;
  if not public.dispute_is_open(p_dispute) then raise exception 'الملف مغلق: لا يمكن إضافة مستندات'; end if;
  if p_path not like p_dispute::text || '/%' then raise exception 'مسار الملف لا يخص هذا النزاع'; end if;
  if p_hash !~ '^[0-9a-f]{64}$' then raise exception 'بصمة الملف غير صالحة'; end if;
  if not (p_mime = any (public.allowed_mime_types())) then raise exception 'نوع الملف غير مسموح'; end if;
  if p_size is null or p_size <= 0 or p_size > 10485760 then raise exception 'حجم الملف غير صالح'; end if;
  if not exists (select 1 from storage.objects where bucket_id = 'documents' and name = p_path) then
    raise exception 'الملف غير موجود في التخزين';
  end if;
  insert into public.documents (dispute_id, uploaded_by, file_name, file_path, file_size, mime_type, sha256_hash, document_type)
  values (p_dispute, p_actor, left(p_file_name, 255), p_path, p_size, p_mime, p_hash, v_type) returning id into v_id;
  return v_id;
end $$;

drop policy documents_insert on public.documents;
revoke insert on public.documents from authenticated;

-- ------------------------------------------------ B. no raw rows for members
drop policy consents_select on public.consents;
create policy consents_select on public.consents for select to authenticated using (user_id = auth.uid() or public.is_admin());
drop policy signatures_select on public.settlement_signatures;
create policy signatures_select on public.settlement_signatures for select to authenticated using (user_id = auth.uid() or public.is_admin());
drop policy audit_select on public.audit_logs;
create policy audit_select on public.audit_logs for select to authenticated using (public.is_admin());
drop policy profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated using (id = auth.uid() or public.is_admin());
drop policy mediator_profiles_select on public.mediator_profiles;
create policy mediator_profiles_select on public.mediator_profiles for select to authenticated using (id = auth.uid() or public.is_admin());

create or replace function public.dispute_timeline(p_dispute uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.can_read_dispute(p_dispute) then return '[]'::jsonb; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'seq', a.seq, 'event_type', a.event_type, 'created_at', a.created_at, 'row_hash', a.row_hash,
      'actor_name', case when a.actor_id is null then 'النظام' when ap.role = 'admin' then 'مدير المنصة' else ap.full_name end,
      'new_state', jsonb_strip_nulls(jsonb_build_object(
        'status', a.new_state->>'status', 'outcome', a.new_state->>'outcome', 'file_name', a.new_state->>'file_name',
        'sha256_hash', a.new_state->>'sha256_hash', 'session_number', a.new_state->'session_number',
        'version', a.new_state->'version', 'party_role', a.new_state->>'party_role', 'dispute_number', a.new_state->>'dispute_number')),
      'previous_state', jsonb_strip_nulls(jsonb_build_object('status', a.previous_state->>'status'))) order by a.seq)
    from public.audit_logs a left join public.profiles ap on ap.id = a.actor_id
    where a.dispute_id = p_dispute), '[]'::jsonb);
end $$;

create or replace function public.dispute_consents(p_dispute uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('user_id', c.user_id, 'accepted_at', c.accepted_at)), '[]'::jsonb)
  from public.consents c join public.disputes d on d.id = c.dispute_id and d.agreement_document_id = c.document_id
  where c.dispute_id = p_dispute and public.is_dispute_member(p_dispute);
$$;

create or replace function public.dispute_signatures(p_dispute uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'user_id', g.user_id, 'party_role', g.party_role,
           'signed_at', g.signed_at, 'content_hash', g.content_hash) order by g.signed_at), '[]'::jsonb)
  from public.settlement_signatures g where g.dispute_id = p_dispute and public.can_read_dispute(p_dispute);
$$;

-- Names only (never e-mail / phone / bar number), and only for people connected to files I can read.
create or replace function public.profile_names(p_ids uuid[]) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(p.id, p.full_name), '{}'::jsonb)
  from public.profiles p
  where auth.uid() is not null and p.id = any (p_ids) and (
    p.id = auth.uid() or public.is_admin()
    or exists (select 1 from public.disputes d where public.can_read_dispute(d.id)
               and p.id in (d.claimant_id, d.respondent_id, d.mediator_id, d.created_by))
    or exists (select 1 from public.mediator_assignments a where public.can_read_dispute(a.dispute_id) and a.mediator_id = p.id));
$$;

create or replace function public.mediator_directory() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'name', p.full_name, 'bio', m.bio,
           'specializations', m.specializations, 'years_experience', m.years_experience) order by p.full_name), '[]'::jsonb)
  from public.profiles p join public.mediator_profiles m on m.id = p.id
  where auth.uid() is not null and p.role = 'mediator' and p.kyc_status = 'verified';
$$;

-- ------------------------------------------------ C. fixes
create or replace function public.check_invite_quota(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_user is null then return; end if;
  if (select count(*) from public.invitations i join public.disputes d on d.id = i.dispute_id
      where d.claimant_id = p_user and i.created_at > now() - interval '24 hours') >= 10 then
    raise exception 'تجاوزت الحد اليومي للدعوات (10 خلال 24 ساعة). حاول لاحقًا أو تواصل مع الإدارة';
  end if;
end $$;

-- Only mediators the admin has both promoted AND verified can be proposed, and only they are listed.
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
  if not exists (select 1 from public.profiles where id = p_mediator and role = 'mediator' and kyc_status = 'verified') then
    raise exception 'الوسيط غير موجود';
  end if;
  if exists (select 1 from public.mediator_assignments where dispute_id = p_dispute and status in ('proposed', 'approved')) then
    raise exception 'يوجد اقتراح وسيط قيد الانتظار';
  end if;
  insert into public.mediator_assignments (dispute_id, mediator_id, proposed_by) values (p_dispute, p_mediator, v_uid);
  update public.disputes set status = 'mediator_selection' where id = p_dispute;
end $$;

create or replace function public.create_dispute(
  p_title text, p_description text, p_type text, p_value numeric, p_email text, p_phone text
) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_email text; d public.disputes; v_token text; v_agreement uuid;
begin
  perform public.check_invite_quota(auth.uid());
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

create or replace function public.resend_invitation(p_dispute uuid, p_email text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); d public.disputes; v_email text; v_token text; v_own text;
begin
  perform public.check_invite_quota(auth.uid());
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

create or replace function public.submit_settlement(p_dispute uuid) returns void
language plpgsql security definer set search_path = public as $$
declare d public.disputes;
begin
  perform public.require_mfa();
  select * into d from public.disputes where id = p_dispute for update;
  if not found or d.mediator_id is distinct from auth.uid() then raise exception 'غير مصرح'; end if;
  if not (public.has_agreement(p_dispute, d.claimant_id) and public.has_agreement(p_dispute, d.respondent_id)
          and public.has_agreement(p_dispute, d.mediator_id)) then
    raise exception 'لا يُفتح الاتفاق للتوقيع قبل قبول الجميع لاتفاقية الوساطة';
  end if;
  if exists (select 1 from public.settlements where dispute_id = p_dispute and status = 'draft' and content ~ '\[[^\]]*\]') then
    raise exception 'نص الاتفاق يحتوي أقواسًا [..] لم تُستبدل. أكمل البنود ثم افتح الاتفاق للتوقيع';
  end if;
  update public.settlements set status = 'pending_signatures' where dispute_id = p_dispute and status = 'draft';
  if not found then raise exception 'لا توجد مسودة اتفاق لإرسالها للتوقيع'; end if;
end $$;

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
    'value_settled', (select coalesce(sum(dispute_value_egp), 0) from public.disputes where (status = 'signed' or outcome = 'settled')),
    'sessions_total', (select count(*) from public.sessions),
    'sessions_per_settled', (select round(avg(c), 1) from (
        select count(*) c from public.sessions s join public.disputes d on d.id = s.dispute_id
        where (d.status = 'signed' or d.outcome = 'settled') group by s.dispute_id) x),
    'documents_total', (select count(*) from public.documents),
    'invitations_sent', (select count(*) from public.invitations),
    'invitations_accepted', (select count(*) from public.invitations where status = 'accepted'),
    'placeholder_docs', (select count(*) from public.legal_documents where is_current and is_placeholder),
    'verified_mediators', (select count(*) from public.profiles where role = 'mediator' and kyc_status = 'verified'),
    'users_total', (select count(*) from public.profiles)
  );
end $$;

-- ------------------------------------------------ D. rate limiting (server-side, shared across serverless instances)
create table public.rate_limits (
  key text not null, bucket bigint not null, hits int not null default 1, expires_at timestamptz not null,
  primary key (key, bucket)
);
alter table public.rate_limits enable row level security;   -- no policies
revoke all on public.rate_limits from anon, authenticated;

-- Returns TRUE when the caller is OVER the limit.
create or replace function public.rate_limit_hit(p_key text, p_limit int, p_window_seconds int) returns boolean
language plpgsql security definer set search_path = public as $$
declare v_bucket bigint := floor(extract(epoch from now()) / p_window_seconds); v_hits int;
begin
  insert into public.rate_limits (key, bucket, expires_at)
  values (p_key, v_bucket, to_timestamp((v_bucket + 1) * p_window_seconds))
  on conflict (key, bucket) do update set hits = public.rate_limits.hits + 1
  returning hits into v_hits;
  if random() < 0.02 then delete from public.rate_limits where expires_at < now() - interval '1 hour'; end if;
  return v_hits > p_limit;
end $$;

-- ------------------------------------------------ grants
revoke execute on function public.accept_legal(uuid, uuid, text, text), public.sign_settlement(uuid, text, text) from public, anon, authenticated;
revoke execute on function public.act_as(uuid, text), public.accept_legal_srv(uuid, text, uuid, uuid, text, text),
  public.sign_settlement_srv(uuid, text, uuid, text, text),
  public.register_document_srv(uuid, text, uuid, text, text, text, bigint, text, text),
  public.rate_limit_hit(text, int, int), public.check_invite_quota(uuid), public.allowed_mime_types()
  from public, anon, authenticated;
grant execute on function public.act_as(uuid, text), public.accept_legal_srv(uuid, text, uuid, uuid, text, text),
  public.sign_settlement_srv(uuid, text, uuid, text, text),
  public.register_document_srv(uuid, text, uuid, text, text, text, bigint, text, text),
  public.rate_limit_hit(text, int, int) to service_role;
revoke execute on function public.dispute_timeline(uuid), public.dispute_consents(uuid), public.dispute_signatures(uuid),
  public.profile_names(uuid[]), public.mediator_directory() from public, anon;
grant execute on function public.dispute_timeline(uuid), public.dispute_consents(uuid), public.dispute_signatures(uuid),
  public.profile_names(uuid[]), public.mediator_directory() to authenticated;
