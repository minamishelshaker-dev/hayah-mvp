-- Migration 10: digital signing INSIDE the platform for arbitration (agreement + award), admin read logging, hardening.
--
-- What "signed" means here (same model as the mediation settlement): a simple electronic signature = the signer's identity
-- re-checked by password on the server + the SHA-256 of the exact text signed + time + second-factor level + IP/browser seen by
-- the server. On top of that, when the last signature lands, the database freezes a canonical record of the instrument and the
-- server attaches an Ed25519 signature of the PLATFORM over it (verifiable offline with scripts/verify-record.mjs).
-- It is NOT a qualified signature licensed by ITIDA (Law 15/2004). Whether a court accepts it for an arbitration agreement or an
-- award must be confirmed by a lawyer; the paper/scan route from migration 09 stays available for exactly that reason.

-- ------------------------------------------------------------ A. defence in depth for function privileges
-- Functions created from now on are NOT executable by the API roles unless a migration grants them explicitly.
-- Two statements on purpose: PostgreSQL gives EXECUTE to PUBLIC on every new function (only the global form below removes that),
-- and Supabase additionally grants anon/authenticated through schema-level defaults (the second statement removes those).
-- Both apply to functions created by the role running this migration. Every later migration must GRANT what it wants callable.
alter default privileges revoke execute on functions from public;
alter default privileges in schema public revoke execute on functions from anon, authenticated;

-- ------------------------------------------------------------ B. the arbitration agreement drafted and signed on the platform
create table public.arb_agreements (
  id uuid primary key default gen_random_uuid(),
  arbitration_id uuid not null unique references public.arbitrations(id) on delete cascade,
  body text not null,
  body_hash text not null,
  version int not null default 1,
  status text not null default 'draft' check (status in ('draft', 'open', 'signed')),
  created_by uuid not null references public.profiles(id),
  opened_at timestamptz,
  signed_at timestamptz,
  signed_record jsonb,
  platform_signature text,
  signing_key_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger arb_agreements_touch before update on public.arb_agreements for each row execute function public.touch_updated_at();

create table public.arb_agreement_signatures (
  id uuid primary key default gen_random_uuid(),
  agreement_id uuid not null references public.arb_agreements(id) on delete cascade,
  arbitration_id uuid not null references public.arbitrations(id) on delete cascade,
  user_id uuid not null references public.profiles(id),
  body_hash text not null,
  aal text,
  ip_address text,
  user_agent text,
  signed_at timestamptz not null default now(),
  unique (agreement_id, user_id)
);

-- the scan route now also records the hash of the confirmed file and the assurance level
alter table public.arb_agreement_confirmations add column doc_hash text, add column aal text;

-- ------------------------------------------------------------ C. the award signed on the platform
alter table public.arb_awards
  add column signing_mode text check (signing_mode in ('paper', 'platform')),
  add column signed_at timestamptz,
  add column signer_ip text,
  add column signer_ua text,
  add column signer_aal text,
  add column signed_record jsonb,
  add column platform_signature text,
  add column signing_key_id text;

-- ------------------------------------------------------------ D. audit: texts and frozen records never enter the log
create or replace function public.audit_arb_slim() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare v_old jsonb; v_new jsonb; v_row jsonb;
begin
  if tg_op in ('UPDATE', 'DELETE') then v_old := to_jsonb(old) - 'draft_text' - 'body' - 'signed_record'; end if;
  if tg_op in ('INSERT', 'UPDATE') then v_new := to_jsonb(new) - 'draft_text' - 'body' - 'signed_record'; end if;
  v_row := coalesce(v_new, v_old);
  insert into public.audit_logs (event_type, actor_id, dispute_id, entity_type, entity_id, previous_state, new_state)
  values (tg_table_name || '.' || tg_op, auth.uid(), (v_row->>'arbitration_id')::uuid, tg_table_name, (v_row->>'id')::uuid, v_old, v_new);
  return null;
end $$;

create trigger audit_arb_agreements after insert or update or delete on public.arb_agreements for each row execute function public.audit_arb_slim();
create trigger audit_arb_agreement_signatures after insert or update or delete on public.arb_agreement_signatures for each row execute function public.audit_changes();

-- A signed instrument cannot be changed afterwards, whoever holds the key (the signature is attached later and may change).
create or replace function public.arb_agreement_frozen() returns trigger language plpgsql as $$
begin
  if old.status = 'signed' and (new.body is distinct from old.body or new.body_hash is distinct from old.body_hash
     or (old.signed_record is not null and new.signed_record is distinct from old.signed_record)) then
    raise exception 'الاتفاق الموقَّع لا يُعدَّل';
  end if;
  return new;
end $$;
create trigger arb_agreements_frozen before update on public.arb_agreements for each row execute function public.arb_agreement_frozen();

create or replace function public.arb_award_frozen() returns trigger language plpgsql as $$
begin
  if old.status = 'issued' and (new.draft_text is distinct from old.draft_text or new.draft_hash is distinct from old.draft_hash
     or new.award_date is distinct from old.award_date or new.signing_mode is distinct from old.signing_mode
     or (old.signed_record is not null and new.signed_record is distinct from old.signed_record)) then
    raise exception 'الحكم الصادر لا يُعدَّل';
  end if;
  return new;
end $$;
create trigger arb_awards_frozen before update on public.arb_awards for each row execute function public.arb_award_frozen();

-- ------------------------------------------------------------ E. RLS
alter table public.arb_agreements enable row level security;
alter table public.arb_agreement_signatures enable row level security;
create policy arb_agreements_select on public.arb_agreements for select to authenticated using (public.arb_can_read(arbitration_id));
create policy arb_agreement_signatures_select on public.arb_agreement_signatures for select to authenticated using (user_id = auth.uid() or public.is_admin());
revoke all on public.arb_agreements, public.arb_agreement_signatures from anon;
revoke insert, update, delete, truncate on public.arb_agreements, public.arb_agreement_signatures from authenticated;

-- ------------------------------------------------------------ F. frozen records (built inside the database, never by the app)
create or replace function public.arb_agreement_record(p_arb uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'format', 'hayah.arbitration-agreement.v1',
    'arbitration_number', a.arb_number,
    'dispute_value_egp', a.dispute_value_egp,
    'agreement_text', g.body,
    'agreement_text_sha256', g.body_hash,
    'signature_method', 'platform-simple-electronic-signature',
    'signers', (select coalesce(jsonb_agg(jsonb_build_object(
                  'user_id', s.user_id, 'name', p.full_name,
                  'role', case when s.user_id = a.claimant_id then 'claimant' else 'respondent' end,
                  'signed_at', s.signed_at, 'assurance_level', s.aal) order by s.signed_at), '[]'::jsonb)
                from public.arb_agreement_signatures s join public.profiles p on p.id = s.user_id
                where s.agreement_id = g.id))
  from public.arbitrations a join public.arb_agreements g on g.arbitration_id = a.id
  where a.id = p_arb;
$$;

create or replace function public.arb_award_record(p_arb uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'format', 'hayah.arbitration-award.v1',
    'arbitration_number', a.arb_number,
    'claimant', (select full_name from public.profiles where id = a.claimant_id),
    'respondent', (select full_name from public.profiles where id = a.respondent_id),
    'arbitrator', jsonb_build_object('user_id', a.arbitrator_id,
                    'name', (select full_name from public.profiles where id = a.arbitrator_id), 'assurance_level', w.signer_aal),
    'dispute_value_egp', a.dispute_value_egp,
    'award_date', w.award_date,
    'signed_at', w.signed_at,
    'award_text', w.draft_text,
    'award_text_sha256', w.draft_hash,
    'agreement_form', case when exists (select 1 from public.arb_agreements g where g.arbitration_id = a.id and g.status = 'signed') then 'platform'
                           when exists (select 1 from public.arb_agreement_confirmations c where c.arbitration_id = a.id) then 'scan' end,
    'agreement_sha256', coalesce((select g.body_hash from public.arb_agreements g where g.arbitration_id = a.id and g.status = 'signed'),
                                 (select c.doc_hash from public.arb_agreement_confirmations c where c.arbitration_id = a.id limit 1)),
    'signature_method', 'platform-simple-electronic-signature')
  from public.arbitrations a join public.arb_awards w on w.arbitration_id = a.id
  where a.id = p_arb;
$$;

-- ------------------------------------------------------------ G. agreement: draft -> open -> signed
create or replace function public.save_arb_agreement(p_arb uuid, p_text text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare v_uid uuid := auth.uid(); a public.arbitrations; g public.arb_agreements; v_hash text;
begin
  select * into a from public.arbitrations where id = p_arb for update;
  if not found or (v_uid is distinct from a.claimant_id and v_uid is distinct from a.respondent_id) then raise exception 'غير مصرح'; end if;
  if a.status <> 'agreement' then raise exception 'ليس الملف في مرحلة اتفاق التحكيم'; end if;
  if not public.arb_has_rules(p_arb, v_uid) then raise exception 'يجب قبول قواعد التحكيم أولًا'; end if;
  if exists (select 1 from public.arb_agreement_confirmations where arbitration_id = p_arb) then
    raise exception 'أُكّد اتفاق تحكيم موقَّع مرفوع كملف، فلا يُصاغ اتفاق آخر على المنصة';
  end if;
  if length(trim(coalesce(p_text, ''))) < 200 then raise exception 'نص الاتفاق قصير جدًا'; end if;
  v_hash := encode(digest(convert_to(p_text, 'UTF8'), 'sha256'), 'hex');
  select * into g from public.arb_agreements where arbitration_id = p_arb for update;
  if not found then
    insert into public.arb_agreements (arbitration_id, body, body_hash, created_by) values (p_arb, p_text, v_hash, v_uid);
  else
    if g.status <> 'draft' then raise exception 'فُتح الاتفاق للتوقيع: أعد فتحه للتعديل أولًا'; end if;
    update public.arb_agreements set body = p_text, body_hash = v_hash, version = version + 1 where id = g.id;
  end if;
end $$;

create or replace function public.open_arb_agreement(p_arb uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); a public.arbitrations; g public.arb_agreements;
begin
  select * into a from public.arbitrations where id = p_arb for update;
  if not found or (v_uid is distinct from a.claimant_id and v_uid is distinct from a.respondent_id) then raise exception 'غير مصرح'; end if;
  if a.status <> 'agreement' then raise exception 'ليس الملف في مرحلة اتفاق التحكيم'; end if;
  if not public.arb_has_rules(p_arb, v_uid) then raise exception 'يجب قبول قواعد التحكيم أولًا'; end if;
  select * into g from public.arb_agreements where arbitration_id = p_arb for update;
  if not found or g.status <> 'draft' then raise exception 'لا توجد مسودة اتفاق'; end if;
  if g.body ~ '\[[^\]]*\]' then raise exception 'نص الاتفاق يحتوي أقواسًا [..] لم تُستبدل'; end if;
  update public.arb_agreements set status = 'open', opened_at = now() where id = g.id;
end $$;

create or replace function public.reopen_arb_agreement(p_arb uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); a public.arbitrations; g public.arb_agreements;
begin
  select * into a from public.arbitrations where id = p_arb for update;
  if not found or (v_uid is distinct from a.claimant_id and v_uid is distinct from a.respondent_id) then raise exception 'غير مصرح'; end if;
  if a.status <> 'agreement' then raise exception 'ليس الملف في مرحلة اتفاق التحكيم'; end if;
  select * into g from public.arb_agreements where arbitration_id = p_arb for update;
  if not found or g.status <> 'open' then raise exception 'لا يوجد اتفاق مفتوح للتوقيع'; end if;
  if exists (select 1 from public.arb_agreement_signatures where agreement_id = g.id) then
    raise exception 'وقّع أحد الطرفين، فلا يُعاد فتح النص للتعديل';
  end if;
  update public.arb_agreements set status = 'draft', opened_at = null where id = g.id;
end $$;

create or replace function public.sign_arb_agreement(p_arb uuid, p_expected_hash text, p_ip text, p_ua text) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); a public.arbitrations; g public.arb_agreements; n int;
begin
  select * into a from public.arbitrations where id = p_arb for update;
  if not found or (v_uid is distinct from a.claimant_id and v_uid is distinct from a.respondent_id) then raise exception 'غير مصرح'; end if;
  if a.status <> 'agreement' then raise exception 'ليس الملف في مرحلة اتفاق التحكيم'; end if;
  if not public.arb_has_rules(p_arb, v_uid) then raise exception 'يجب قبول قواعد التحكيم أولًا'; end if;
  select * into g from public.arb_agreements where arbitration_id = p_arb for update;
  if not found or g.status <> 'open' then raise exception 'الاتفاق ليس مفتوحًا للتوقيع'; end if;
  -- the text may have been reopened and edited after this signer's page was rendered: sign only what was shown
  if p_expected_hash is distinct from g.body_hash then raise exception 'تغيّر نص الاتفاق منذ عرضه عليك. حدّث الصفحة واقرأه من جديد قبل التوقيع'; end if;
  begin
    insert into public.arb_agreement_signatures (agreement_id, arbitration_id, user_id, body_hash, aal, ip_address, user_agent)
    values (g.id, p_arb, v_uid, g.body_hash, coalesce(auth.jwt() ->> 'aal', 'aal1'), left(p_ip, 100), left(p_ua, 300));
  exception when unique_violation then raise exception 'وقّعت من قبل';
  end;
  select count(distinct user_id) into n from public.arb_agreement_signatures where agreement_id = g.id and body_hash = g.body_hash;
  if n = 2 then
    update public.arb_agreements set status = 'signed', signed_at = now(), signed_record = public.arb_agreement_record(p_arb) where id = g.id;
    update public.arbitrations set status = 'selection' where id = p_arb;
  end if;
end $$;

create or replace function public.sign_arb_agreement_srv(p_actor uuid, p_aal text, p_arb uuid, p_expected_hash text, p_ip text, p_ua text)
returns void language plpgsql security definer set search_path = public as $$
begin perform public.act_as(p_actor, p_aal); perform public.sign_arb_agreement(p_arb, p_expected_hash, p_ip, p_ua); end $$;

-- The scan route: same rules as before, plus (1) a file already confirmed by one party is the only one the other may confirm
-- (two different files used to leave the case stuck at "agreement" with both confirmations in), (2) it is closed once the
-- platform-signed route has been opened, (3) the file's hash and the assurance level are recorded.
create or replace function public.confirm_arb_agreement(p_arb uuid, p_doc uuid, p_ip text, p_ua text) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); a public.arbitrations; n int; k int; v_first uuid;
begin
  select * into a from public.arbitrations where id = p_arb for update;
  if not found or (v_uid is distinct from a.claimant_id and v_uid is distinct from a.respondent_id) then raise exception 'غير مصرح'; end if;
  if a.status <> 'agreement' then raise exception 'ليس الملف في مرحلة اتفاق التحكيم'; end if;
  if not public.arb_has_rules(p_arb, v_uid) then raise exception 'يجب قبول قواعد التحكيم أولًا'; end if;
  if exists (select 1 from public.arb_agreements where arbitration_id = p_arb and status in ('open', 'signed')) then
    raise exception 'يجري توقيع اتفاق التحكيم على المنصة، فلا يُؤكَّد ملف مرفوع';
  end if;
  if not exists (select 1 from public.arb_documents where id = p_doc and arbitration_id = p_arb and doc_type = 'arbitration_agreement') then
    raise exception 'اختر ملف اتفاق التحكيم المرفوع';
  end if;
  select document_id into v_first from public.arb_agreement_confirmations where arbitration_id = p_arb limit 1;
  if v_first is not null and v_first <> p_doc then
    raise exception 'أكّد الطرف الآخر ملفًا آخر. أكّد الملف نفسه، أو أنهِ الطلب وافتح غيره';
  end if;
  begin
    insert into public.arb_agreement_confirmations (arbitration_id, user_id, document_id, doc_hash, aal, ip_address, user_agent)
    values (p_arb, v_uid, p_doc, (select sha256_hash from public.arb_documents where id = p_doc), coalesce(auth.jwt() ->> 'aal', 'aal1'),
            left(p_ip, 100), left(p_ua, 300));
  exception when unique_violation then raise exception 'أكّدت من قبل';
  end;
  select count(distinct user_id), count(distinct document_id) into n, k from public.arb_agreement_confirmations where arbitration_id = p_arb;
  if n = 2 and k = 1 then update public.arbitrations set status = 'selection' where id = p_arb; end if;
end $$;

-- ------------------------------------------------------------ H. award: paper route (as before) or platform signature
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
  update public.arb_awards set status = 'issued', signing_mode = 'paper', signed_document_id = p_signed_doc, award_date = p_award_date, issued_at = now() where id = w.id;
  update public.arbitrations set status = 'closed', outcome = 'award_issued', closed_at = now(), closed_by = v_uid where id = p_arb;
end $$;

create or replace function public.sign_award(p_arb uuid, p_expected_hash text, p_award_date date, p_ip text, p_ua text) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); a public.arbitrations; w public.arb_awards;
begin
  perform public.require_mfa();
  select * into a from public.arbitrations where id = p_arb for update;
  if not found or a.arbitrator_id is distinct from v_uid then raise exception 'غير مصرح'; end if;
  if a.status <> 'deliberation' then raise exception 'ليس الملف في مرحلة المداولة'; end if;
  select * into w from public.arb_awards where arbitration_id = p_arb for update;
  if not found or w.status <> 'draft' then raise exception 'لا توجد مسودة حكم'; end if;
  -- sign only the saved text the arbitrator was shown (unsaved edits in the browser are not signed)
  if p_expected_hash is distinct from w.draft_hash then raise exception 'تغيّر نص الحكم المحفوظ عمّا عُرض عليك. احفظ المسودة ثم حدّث الصفحة وراجع البصمة قبل التوقيع'; end if;
  if w.draft_text ~ '\[[^\]]*\]' then raise exception 'مسودة الحكم تحتوي أقواسًا [..] لم تُستبدل'; end if;
  if p_award_date is null or p_award_date > (now() at time zone 'Africa/Cairo')::date then raise exception 'تاريخ الحكم غير صالح'; end if;
  update public.arb_awards
     set status = 'issued', signing_mode = 'platform', award_date = p_award_date, issued_at = now(), signed_at = now(),
         signer_ip = left(p_ip, 100), signer_ua = left(p_ua, 300), signer_aal = coalesce(auth.jwt() ->> 'aal', 'aal1')
   where id = w.id;
  update public.arb_awards set signed_record = public.arb_award_record(p_arb) where id = w.id;
  update public.arbitrations set status = 'closed', outcome = 'award_issued', closed_at = now(), closed_by = v_uid where id = p_arb;
end $$;

create or replace function public.sign_award_srv(p_actor uuid, p_aal text, p_arb uuid, p_expected_hash text, p_award_date date, p_ip text, p_ua text)
returns void language plpgsql security definer set search_path = public as $$
begin perform public.act_as(p_actor, p_aal); perform public.sign_award(p_arb, p_expected_hash, p_award_date, p_ip, p_ua); end $$;

-- Attached once, by the server only, over the canonical JSON of the frozen record.
create or replace function public.attach_arb_signature(p_kind text, p_arb uuid, p_signature text, p_key_id text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_kind = 'agreement' then
    update public.arb_agreements set platform_signature = p_signature, signing_key_id = p_key_id
     where arbitration_id = p_arb and status = 'signed' and platform_signature is null;
  elsif p_kind = 'award' then
    update public.arb_awards set platform_signature = p_signature, signing_key_id = p_key_id
     where arbitration_id = p_arb and status = 'issued' and signing_mode = 'platform' and platform_signature is null;
  else
    raise exception 'نوع غير معروف';
  end if;
  if not found then raise exception 'غير موجود أو موقَّع من قبل'; end if;
end $$;

-- timeline whitelist: show the signing mode (nothing else new)
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
        'number', a.new_state->'number', 'arb_number', a.new_state->>'arb_number', 'signing_mode', a.new_state->>'signing_mode')),
      'previous_state', jsonb_strip_nulls(jsonb_build_object('status', a.previous_state->>'status'))) order by a.seq)
    from public.audit_logs a left join public.profiles ap on ap.id = a.actor_id
    where a.dispute_id = p_arb), '[]'::jsonb);
end $$;

-- ------------------------------------------------------------ I. the admin can read every file: make each look visible
-- One audit row per admin per case per hour. The parties see it in their own timeline ("مدير المنصة"), so it is a deterrent too.
create or replace function public.log_admin_view(p_kind text, p_case uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then return; end if;
  if p_kind not in ('dispute', 'arbitration') or p_case is null then return; end if;
  if exists (select 1 from public.audit_logs where event_type = 'admin.view_' || p_kind and actor_id = auth.uid()
               and dispute_id = p_case and created_at > now() - interval '1 hour') then return; end if;
  insert into public.audit_logs (event_type, actor_id, dispute_id, entity_type, entity_id, new_state)
  values ('admin.view_' || p_kind, auth.uid(), p_case, p_kind, p_case, jsonb_build_object('case', p_case));
end $$;


-- who has signed (names and times only; the raw signature rows with IP/browser stay private to their owner and the admin)
create or replace function public.arb_agreement_signers(p_arb uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('user_id', s.user_id, 'signed_at', s.signed_at) order by s.signed_at), '[]'::jsonb)
  from public.arb_agreement_signatures s where s.arbitration_id = p_arb and public.arb_can_read(p_arb);
$$;

-- ------------------------------------------------------------ J. grants (explicit: the default now grants nothing)
revoke execute on function
  public.save_arb_agreement(uuid, text), public.open_arb_agreement(uuid), public.reopen_arb_agreement(uuid),
  public.sign_arb_agreement(uuid, text, text, text), public.sign_award(uuid, text, date, text, text),
  public.sign_arb_agreement_srv(uuid, text, uuid, text, text, text), public.sign_award_srv(uuid, text, uuid, text, date, text, text),
  public.attach_arb_signature(text, uuid, text, text), public.arb_agreement_record(uuid), public.arb_award_record(uuid),
  public.log_admin_view(text, uuid), public.arb_agreement_signers(uuid)
  from public, anon, authenticated;
grant execute on function
  public.save_arb_agreement(uuid, text), public.open_arb_agreement(uuid), public.reopen_arb_agreement(uuid),
  public.log_admin_view(text, uuid), public.arb_agreement_signers(uuid)
  to authenticated;
grant execute on function
  public.sign_arb_agreement_srv(uuid, text, uuid, text, text, text), public.sign_award_srv(uuid, text, uuid, text, date, text, text),
  public.attach_arb_signature(text, uuid, text, text)
  to service_role;
-- sign_arb_agreement / sign_award / arb_*_record stay callable only by the owner (via the _srv wrappers and other definer functions).
-- issue_award and confirm_arb_agreement were re-declared above: CREATE OR REPLACE keeps their earlier grants.
