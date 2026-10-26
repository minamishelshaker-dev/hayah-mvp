-- =====================================================================
-- Hayah ADR — two-step verification (MFA) for admins and mediators.
-- Run ONCE, AFTER lifecycle.sql.
--   * Enforced in the DATABASE: a session that has not passed the second step
--     (JWT claim aal = 'aal2') has none of an admin's or mediator's privileges,
--     even through direct API calls. Parties are not affected.
--   * Switch: app_settings.require_mfa ('true' by default). Changing it is audited.
--   * Enrolment is never blocked: aal1 sessions can still read their own profile,
--     so a new admin can reach the enrolment page and cannot lock himself out.
-- =====================================================================

create table public.app_settings (key text primary key, value text not null);
insert into public.app_settings values ('require_mfa', 'true');
alter table public.app_settings enable row level security;   -- no policies: not readable by API users
revoke all on public.app_settings from anon, authenticated;
create trigger audit_app_settings after insert or update or delete on public.app_settings
  for each row execute function public.audit_changes();

create or replace function public.mfa_required() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select value from public.app_settings where key = 'require_mfa'), 'true') = 'true';
$$;

-- True for parties, and for admins/mediators only on a second-step-verified session.
create or replace function public.mfa_satisfied() returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when auth.uid() is null then false
    when not public.mfa_required() then true
    when not exists (select 1 from public.profiles where id = auth.uid() and role in ('admin', 'mediator')) then true
    else coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
  end;
$$;

create or replace function public.require_mfa() returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.mfa_satisfied() then raise exception 'يلزم التحقق بخطوتين (MFA) لهذا الحساب'; end if;
end $$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin') and public.mfa_satisfied();
$$;

create or replace function public.is_dispute_member(p_dispute uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and public.mfa_satisfied() and (
    public.is_admin()
    or exists (select 1 from public.disputes d where d.id = p_dispute
               and auth.uid() in (d.created_by, d.claimant_id, d.respondent_id, d.mediator_id))
    or exists (select 1 from public.mediator_assignments a where a.dispute_id = p_dispute
               and a.mediator_id = auth.uid() and a.status in ('approved', 'accepted'))
  );
$$;

-- What the app needs to know: must this user pass the second step, and has this session?
create or replace function public.mfa_status() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'required', public.mfa_required() and exists (select 1 from public.profiles where id = auth.uid() and role in ('admin', 'mediator')),
    'ok', public.mfa_satisfied());
$$;

create or replace function public.security_status() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'غير مصرح'; end if;
  return jsonb_build_object('mfa_required', public.mfa_required());
end $$;

-- Sensitive admin actions that happen outside the database (e.g. resetting someone's authenticator).
create or replace function public.record_admin_event(p_event text, p_target uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'غير مصرح'; end if;
  insert into public.audit_logs (event_type, actor_id, entity_type, entity_id, new_state)
  values ('admin.' || left(regexp_replace(p_event, '[^a-z_]', '', 'g'), 40), auth.uid(), 'profiles', p_target,
          jsonb_build_object('target', p_target));
end $$;

-- Every privileged mediator action now demands a verified second step (re-declared with one extra line).
create or replace function public.schedule_session(p_dispute uuid, p_at timestamptz, p_minutes int) returns uuid
language plpgsql security definer set search_path = public as $$
declare d public.disputes; v_id uuid; v_no int;
begin
  perform public.require_mfa();
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

create or replace function public.save_settlement(p_dispute uuid, p_content text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare d public.disputes; s public.settlements; v_hash text;
begin
  perform public.require_mfa();
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
  perform public.require_mfa();
  select * into d from public.disputes where id = p_dispute for update;
  if not found or d.mediator_id is distinct from auth.uid() then raise exception 'غير مصرح'; end if;
  if not (public.has_agreement(p_dispute, d.claimant_id) and public.has_agreement(p_dispute, d.respondent_id)
          and public.has_agreement(p_dispute, d.mediator_id)) then
    raise exception 'لا يُفتح الاتفاق للتوقيع قبل قبول الجميع لاتفاقية الوساطة';
  end if;
  update public.settlements set status = 'pending_signatures' where dispute_id = p_dispute and status = 'draft';
  if not found then raise exception 'لا توجد مسودة اتفاق لإرسالها للتوقيع'; end if;
end $$;

create or replace function public.mediator_respond(p_assignment uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); a public.mediator_assignments;
begin
  perform public.require_mfa();
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

create or replace function public.mediator_withdraw(p_dispute uuid, p_reason text default null) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); d public.disputes;
begin
  perform public.require_mfa();
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

create or replace function public.close_dispute(p_dispute uuid, p_outcome text, p_reason text default null) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); d public.disputes;
begin
  perform public.require_mfa();
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

revoke execute on function public.mfa_required(), public.mfa_satisfied(), public.require_mfa(),
  public.mfa_status(), public.security_status(), public.record_admin_event(text, uuid) from public, anon;
grant execute on function public.mfa_status(), public.security_status(), public.record_admin_event(text, uuid) to authenticated;
-- the redefined functions keep their earlier grants (CREATE OR REPLACE preserves privileges)
