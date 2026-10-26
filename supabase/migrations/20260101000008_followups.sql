-- =====================================================================
-- Hayah ADR — follow-ups from the reviews. Run AFTER 007.
--   * reopen_settlement(): the mediator can fix a text nobody has signed yet
--   * my_actions(): "what is waiting for ME" across all my files (dashboard)
--   * record signatures: an Ed25519 signature over the canonical record, attached by the server
--     (so a record can be verified OFFLINE with the public key, not only against this database)
-- =====================================================================

-- ------------------------------------------------ reopen a settlement nobody signed yet
create or replace function public.reopen_settlement(p_dispute uuid, p_reason text default null) returns void
language plpgsql security definer set search_path = public as $$
declare d public.disputes; s public.settlements;
begin
  perform public.require_mfa();
  select * into d from public.disputes where id = p_dispute for update;
  if not found or d.mediator_id is distinct from auth.uid() then raise exception 'غير مصرح'; end if;
  select * into s from public.settlements where dispute_id = p_dispute for update;
  if not found or s.status <> 'pending_signatures' then raise exception 'لا يوجد اتفاق مفتوح للتوقيع'; end if;
  if exists (select 1 from public.settlement_signatures where settlement_id = s.id) then
    raise exception 'وقّع أحد الطرفين على النص الحالي فلا يُعاد فتحه. يوقّع الطرف الآخر عليه أو تُنهى الوساطة';
  end if;
  update public.settlements set status = 'draft' where id = s.id;
end $$;

-- ------------------------------------------------ what is waiting for me
create or replace function public.my_actions() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(q.x order by q.x->>'dispute_number', q.x->>'code'), '[]'::jsonb) from (
    select jsonb_build_object('dispute_id', d.id, 'dispute_number', d.dispute_number, 'code', 'accept_agreement') x
      from public.disputes d
      where auth.uid() is not null and not public.is_admin() and d.status not in ('closed', 'cancelled')
        and public.is_dispute_member(d.id) and not public.has_agreement(d.id, auth.uid())
    union all
    select jsonb_build_object('dispute_id', d.id, 'dispute_number', d.dispute_number, 'code', 'approve_mediator')
      from public.mediator_assignments a join public.disputes d on d.id = a.dispute_id
      where a.status = 'proposed' and a.proposed_by <> auth.uid() and auth.uid() in (d.claimant_id, d.respondent_id)
        and public.has_agreement(d.id, auth.uid())
    union all
    select jsonb_build_object('dispute_id', d.id, 'dispute_number', d.dispute_number, 'code', 'accept_assignment')
      from public.mediator_assignments a join public.disputes d on d.id = a.dispute_id
      where a.status = 'approved' and a.mediator_id = auth.uid() and d.status = 'mediator_selection'
    union all
    select jsonb_build_object('dispute_id', d.id, 'dispute_number', d.dispute_number, 'code', 'choose_mediator')
      from public.disputes d
      where d.status in ('accepted', 'mediator_selection') and auth.uid() in (d.claimant_id, d.respondent_id)
        and public.has_agreement(d.id, auth.uid())
        and not exists (select 1 from public.mediator_assignments a where a.dispute_id = d.id and a.status in ('proposed', 'approved'))
    union all
    select jsonb_build_object('dispute_id', d.id, 'dispute_number', d.dispute_number, 'code', 'renew_invitation')
      from public.disputes d join public.invitations i on i.dispute_id = d.id
      where d.status = 'invited' and d.claimant_id = auth.uid() and i.status = 'pending' and i.expires_at < now()
    union all
    select jsonb_build_object('dispute_id', d.id, 'dispute_number', d.dispute_number, 'code', 'schedule_session')
      from public.disputes d
      where d.status = 'active' and d.mediator_id = auth.uid() and public.is_dispute_member(d.id)
        and not exists (select 1 from public.sessions s where s.dispute_id = d.id and s.status = 'scheduled')
    union all
    select jsonb_build_object('dispute_id', d.id, 'dispute_number', d.dispute_number, 'code', 'sign_settlement')
      from public.settlements s join public.disputes d on d.id = s.dispute_id
      where s.status = 'pending_signatures' and auth.uid() in (d.claimant_id, d.respondent_id)
        and public.has_agreement(d.id, auth.uid())
        and not exists (select 1 from public.settlement_signatures g where g.settlement_id = s.id and g.user_id = auth.uid())
  ) q;
$$;

-- ------------------------------------------------ record signatures (Ed25519, made by the server)
alter table public.record_exports
  add column signature text,
  add column signing_key_id text,
  add column signed_at timestamptz;

-- Attached once, by the server only. The signature covers the canonical JSON of the stored record.
create or replace function public.attach_record_signature(p_export uuid, p_signature text, p_key_id text) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.record_exports set signature = p_signature, signing_key_id = p_key_id, signed_at = now()
   where id = p_export and signature is null;
  if not found then raise exception 'المحضر غير موجود أو موقَّع من قبل'; end if;
end $$;

create or replace function public.audit_record_signature() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
begin
  insert into public.audit_logs (event_type, actor_id, dispute_id, entity_type, entity_id, new_state)
  values ('record_exports.SIGNED', auth.uid(), new.dispute_id, 'record_exports', new.id,
          jsonb_build_object('record_hash', new.record_hash, 'signing_key_id', new.signing_key_id));
  return null;
end $$;
create trigger audit_record_exports_signed after update of signature on public.record_exports
  for each row when (old.signature is null and new.signature is not null)
  execute function public.audit_record_signature();

create or replace function public.verify_record(p_hash text, p_record jsonb) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select jsonb_build_object('found', true, 'issued_at', e.created_at,
            'dispute_number', e.record->'data'->'dispute'->>'number', 'record_hash', e.record_hash,
            'signed', e.signature is not null, 'signing_key_id', e.signing_key_id)
     from public.record_exports e
     where (p_hash is not null and e.record_hash = lower(trim(p_hash)))
        or (p_record is not null and e.record = p_record)
     limit 1),
    jsonb_build_object('found', false));
$$;

-- ------------------------------------------------ grants
revoke execute on function public.reopen_settlement(uuid, text), public.my_actions() from public, anon;
grant execute on function public.reopen_settlement(uuid, text), public.my_actions() to authenticated;
revoke execute on function public.attach_record_signature(uuid, text, text) from public, anon, authenticated;
grant execute on function public.attach_record_signature(uuid, text, text) to service_role;
