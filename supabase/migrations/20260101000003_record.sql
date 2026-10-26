-- =====================================================================
-- Hayah ADR — certified case record (محضر موثّق). Run ONCE, AFTER trial.sql.
--   * issue_dispute_record(): builds an immutable snapshot of the whole file
--     inside the database (so the client cannot forge its content) and stores it.
--   * verify_record(): lets anyone confirm that a record hash / JSON file
--     was really issued by the platform (public, reveals only number and date).
-- =====================================================================

create or replace function public.mask_ip(p text, p_full boolean) returns text
language sql immutable as $$
  select case
    when p is null then null
    when p_full then p
    when p like '%.%' then regexp_replace(p, '\.[0-9]+$', '.x')
    when p like '%:%' then split_part(p, ':', 1) || ':' || split_part(p, ':', 2) || ':x'
    else 'x' end;
$$;

create table public.record_exports (
  id uuid primary key default gen_random_uuid(),
  dispute_id uuid not null references public.disputes(id) on delete cascade,
  exported_by uuid not null references public.profiles(id),
  record jsonb not null,
  record_hash text unique not null,
  created_at timestamptz not null default now()
);
create index record_exports_dispute on public.record_exports (dispute_id);

alter table public.record_exports enable row level security;
-- A record issued by an admin contains full IP addresses, so members only see what they issued themselves.
create policy record_exports_select on public.record_exports for select to authenticated
  using (exported_by = auth.uid() or public.is_admin());
revoke all on public.record_exports from anon;
revoke insert, update, delete, truncate on public.record_exports from authenticated;

-- Slim audit entry: the hash only, not the whole snapshot.
create or replace function public.audit_record_export() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
begin
  insert into public.audit_logs (event_type, actor_id, dispute_id, entity_type, entity_id, new_state)
  values ('record_exports.INSERT', auth.uid(), new.dispute_id, 'record_exports', new.id,
          jsonb_build_object('record_hash', new.record_hash));
  return null;
end $$;
create trigger audit_record_exports after insert on public.record_exports
  for each row execute function public.audit_record_export();

-- Internal builder. Not callable from the API (see REVOKE below).
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
      'type', d.dispute_type, 'value_egp', d.dispute_value_egp, 'status', d.status, 'created_at', d.created_at),
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
          'status', a.new_state->>'status', 'prev_status', a.previous_state->>'status',
          'file_name', a.new_state->>'file_name', 'sha256_hash', a.new_state->>'sha256_hash',
          'session_number', a.new_state->'session_number', 'version', a.new_state->'version',
          'party_role', a.new_state->>'party_role', 'dispute_number', a.new_state->>'dispute_number',
          'invited_email', a.new_state->>'invited_email')),
        'row_hash', a.row_hash) order by a.seq)
      from public.audit_logs a left join public.profiles ap on ap.id = a.actor_id
      where a.dispute_id = p_dispute), '[]'::jsonb),
    'chain_check', v_chain);
end $$;
revoke execute on function public.build_dispute_record(uuid, boolean) from public, anon, authenticated;

create or replace function public.issue_dispute_record(p_dispute uuid) returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare v_uid uuid := auth.uid(); v_me public.profiles; v_env jsonb; v_id uuid;
begin
  if v_uid is null then raise exception 'يجب تسجيل الدخول'; end if;
  if not public.is_dispute_member(p_dispute) then raise exception 'غير مصرح'; end if;
  select * into v_me from public.profiles where id = v_uid;
  if v_me.role <> 'admin' and not public.has_agreement(p_dispute, v_uid) then
    raise exception 'اقبل اتفاقية الوساطة أولًا';
  end if;
  v_env := jsonb_build_object(
    'schema', 'hayah-record/1',
    'issued_at', now(),
    'issued_by', jsonb_build_object('name', v_me.full_name, 'role', v_me.role),
    'data', public.build_dispute_record(p_dispute, v_me.role = 'admin'));
  insert into public.record_exports (dispute_id, exported_by, record, record_hash)
  values (p_dispute, v_uid, v_env, encode(digest(convert_to(v_env::text, 'UTF8'), 'sha256'), 'hex'))
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.verify_record(p_hash text, p_record jsonb) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select jsonb_build_object('found', true, 'issued_at', e.created_at,
            'dispute_number', e.record->'data'->'dispute'->>'number', 'record_hash', e.record_hash)
     from public.record_exports e
     where (p_hash is not null and e.record_hash = lower(trim(p_hash)))
        or (p_record is not null and e.record = p_record)
     limit 1),
    jsonb_build_object('found', false));
$$;
grant execute on function public.verify_record(text, jsonb) to anon, authenticated;
