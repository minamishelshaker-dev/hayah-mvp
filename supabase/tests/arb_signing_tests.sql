-- Migration 10: arbitration agreement + award signed on the platform, the scan-route fix, admin read logging, function privileges.
-- Needs helpers.sql, lifecycle_tests.sql (t.make_active) and arbitration_tests.sql (t.make_arb).
\set ON_ERROR_STOP 1
\pset tuples_only on
\pset format unaligned

\set sadm f0000000-0000-0000-0000-000000000001
\set smed f0000000-0000-0000-0000-000000000002
\set sarb f0000000-0000-0000-0000-000000000003
\set scla f0000000-0000-0000-0000-000000000004
\set sres f0000000-0000-0000-0000-000000000005
\set sstr f0000000-0000-0000-0000-000000000006

select t.as_super();
insert into auth.users (id, email, raw_user_meta_data) values
 (:'sadm'::uuid, 'sadmin@t.com', '{"full_name":"Admin S"}'),
 (:'smed'::uuid, 'smed@t.com',   '{"full_name":"Mediator S"}'),
 (:'sarb'::uuid, 'sarb@t.com',   '{"full_name":"Arbitrator S"}'),
 (:'scla'::uuid, 'scla@t.com',   '{"full_name":"Claimant S"}'),
 (:'sres'::uuid, 'sres@t.com',   '{"full_name":"Respondent S"}'),
 (:'sstr'::uuid, 'sstr@t.com',   '{"full_name":"Stranger S"}');
update public.profiles set role = 'admin' where id = :'sadm'::uuid;
update public.profiles set role = 'mediator', kyc_status = 'verified' where id = :'smed'::uuid;
update public.profiles set role = 'arbitrator', kyc_status = 'verified', phone = '01222222222' where id = :'sarb'::uuid;

-- a file that has just entered the "agreement" stage (rules accepted, escalation accepted, nothing signed)
create or replace function t.make_arb_agreement(c uuid, r uuid, med uuid, r_email text) returns uuid language plpgsql as $$
declare v_src uuid; v_arb uuid;
begin
  v_src := t.make_active(c, r, med, r_email);
  perform t.as_user(c);
  v_arb := public.propose_escalation(v_src, 'ملف تحكيم للتوقيع الرقمي', repeat('ملخص الطلب ', 6), 150000, false);
  perform t.accept_rules(v_arb);
  perform t.as_user(r); perform t.accept_rules(v_arb); perform public.respond_escalation(v_arb, true);
  return v_arb;
end $$;

-- ====================================================== S. the agreement drafted and signed on the platform
select t.make_arb_agreement(:'scla'::uuid, :'sres'::uuid, :'smed'::uuid, 'sres@t.com') as arb \gset
select t.as_user(:'scla'::uuid);
select t.ok((select status from public.arbitrations where id = :'arb'::uuid) = 'agreement', 'S0 the file is at the agreement stage');

select t.as_user(:'sstr'::uuid);
select t.fails(format('select public.save_arb_agreement(%L, %L)', :'arb', repeat('نص ', 120)), 'S1 an outsider cannot draft the agreement', 'غير مصرح');

select t.as_user(:'scla'::uuid);
select t.fails(format('select public.save_arb_agreement(%L, ''قصير'')', :'arb'), 'S2 a too-short text is refused', 'قصير');
select public.save_arb_agreement(:'arb'::uuid, 'اتفاق تحكيم. موضوع النزاع: [وصف النزاع]. ' || repeat('نص الاتفاق علامة-سرية-123 ', 12));
select t.ok((select status = 'draft' and version = 1 from public.arb_agreements where arbitration_id = :'arb'::uuid), 'S3 the draft is saved as version 1');
select t.fails(format('select public.open_arb_agreement(%L)', :'arb'), 'S4 a text with an unfilled [..] cannot be opened for signature', 'أقواسًا');

select t.as_user(:'sres'::uuid);
select public.save_arb_agreement(:'arb'::uuid, 'اتفاق تحكيم. موضوع النزاع: عقد توريد رقم 5. ' || repeat('نص الاتفاق علامة-سرية-123 ', 12));
select t.ok((select version = 2 and status = 'draft' from public.arb_agreements where arbitration_id = :'arb'::uuid), 'S5 either party may edit the draft (version 2)');
select public.open_arb_agreement(:'arb'::uuid);
select t.ok((select status = 'open' and opened_at is not null from public.arb_agreements where arbitration_id = :'arb'::uuid), 'S6 the text is opened for signature');
select t.fails(format('select public.save_arb_agreement(%L, %L)', :'arb', 'تعديل ' || repeat('نص ', 80)), 'S7 an opened text cannot be edited', 'فُتح');

-- no direct route around the server
select t.fails(format('select public.sign_arb_agreement(%L, ''x'', ''1.1.1.1'', ''ua'')', :'arb'), 'S8 the signing function is closed to users', 'permission denied');
select t.fails(format('select public.sign_arb_agreement_srv(%L, ''aal2'', %L, ''x'', ''1.1.1.1'', ''ua'')', :'sres', :'arb'), 'S9 so is the server-only wrapper', 'permission denied');
select t.fails($$update public.arb_agreements set status = 'signed'$$, 'S10 users cannot write agreements directly', 'permission denied');

select t.as_user(:'sstr'::uuid);
select t.fails(format('select t.sign_arb_agreement(%L, ''x'', ''9.9.9.9'', ''ua'')', :'arb'), 'S11 an outsider cannot sign', 'غير مصرح');

select t.as_user(:'scla'::uuid);
select body_hash as ah from public.arb_agreements where arbitration_id = :'arb'::uuid \gset
select t.fails(format('select t.sign_arb_agreement(%L, %L, ''1.1.1.1'', ''ua'')', :'arb', repeat('0', 64)), 'S11a a signature is refused if the text is not the one that was shown (stale page)', 'تغيّر نص الاتفاق');
select t.sign_arb_agreement(:'arb'::uuid, :'ah', '1.1.1.1', 'ua');
select t.ok((select status = 'agreement' from public.arbitrations where id = :'arb'::uuid)
        and (select status = 'open' from public.arb_agreements where arbitration_id = :'arb'::uuid), 'S12 one signature does not close the stage');
select t.fails(format('select t.sign_arb_agreement(%L, %L, ''1.1.1.1'', ''ua'')', :'arb', :'ah'), 'S13 a party signs once', 'وقّعت من قبل');
select t.fails(format('select public.reopen_arb_agreement(%L)', :'arb'), 'S14 after a signature the text cannot be reopened', 'وقّع أحد');
select t.ok((select count(*) from public.arb_agreement_signatures) = 1, 'S15 a party reads only their own raw signature row');

select t.as_user(:'sres'::uuid);
select t.sign_arb_agreement(:'arb'::uuid, :'ah', '2.2.2.2', 'ua');
select t.as_super();
select t.ok((select status = 'selection' from public.arbitrations where id = :'arb'::uuid), 'S16 the second signature moves the file to arbitrator selection');
select t.ok((select status = 'signed' and signed_at is not null and signed_record is not null from public.arb_agreements where arbitration_id = :'arb'::uuid), 'S17 the agreement is signed and its record is frozen');
select t.ok((select jsonb_array_length(signed_record->'signers') = 2 and signed_record->>'agreement_text_sha256' = body_hash and signed_record->>'format' = 'hayah.arbitration-agreement.v1'
               and position('1.1.1.1' in signed_record::text) = 0 from public.arb_agreements where arbitration_id = :'arb'::uuid), 'S18 the record names both signers, carries the text hash and no IP address');
select t.fails($$update public.arb_agreements set body = 'x' where status = 'signed'$$, 'S19 a signed agreement cannot be changed, even by the owner', 'لا يُعدَّل');
select t.fails($$update public.arb_agreements set signed_record = '{}'::jsonb where status = 'signed'$$, 'S20 nor its frozen record', 'لا يُعدَّل');

select t.as_user(:'sstr'::uuid);
select t.fails(format('select public.attach_arb_signature(''agreement'', %L, ''c2ln'', ''k1'')', :'arb'), 'S21 users cannot attach the platform signature (only the server can)', 'permission denied');
select t.attach_arb_signature('agreement', :'arb'::uuid, 'c2ln', 'k1');
select t.as_user(:'scla'::uuid);
select t.ok((select platform_signature = 'c2ln' and signing_key_id = 'k1' from public.arb_agreements where arbitration_id = :'arb'::uuid), 'S22 the server attaches the platform signature (visible to the parties)');
select t.fails(format('select t.attach_arb_signature(''agreement'', %L, ''other'', ''k1'')', :'arb'), 'S23 attached once only', 'موقَّع من قبل');
select t.ok(jsonb_array_length(public.arb_agreement_signers(:'arb'::uuid)) = 2, 'S24 a party sees who signed and when (names and times only)');
select t.as_user(:'sstr'::uuid);
select t.ok(public.arb_agreement_signers(:'arb'::uuid) = '[]'::jsonb and (select count(*) from public.arb_agreements) = 0, 'S25 an outsider sees neither the text nor the signers');

-- ====================================================== T. the two routes exclude each other; the scan route can no longer dead-end
select t.make_arb_agreement(:'scla'::uuid, :'sres'::uuid, :'smed'::uuid, 'sres@t.com') as arb2 \gset
select t.as_user(:'scla'::uuid);
select t.put_object(:'arb2' || '/a1');
select t.register_arb_document(:'arb2'::uuid, 'اتفاق-1.pdf', :'arb2' || '/a1', 'application/pdf', 1000, repeat('1', 64), 'arbitration_agreement') as doc1 \gset
select t.as_user(:'sres'::uuid);
select t.put_object(:'arb2' || '/a2');
select t.register_arb_document(:'arb2'::uuid, 'اتفاق-2.pdf', :'arb2' || '/a2', 'application/pdf', 1000, repeat('2', 64), 'arbitration_agreement') as doc2 \gset
select t.as_user(:'scla'::uuid);
select t.confirm_arb_agreement(:'arb2'::uuid, :'doc1'::uuid, '1.1.1.1', 'ua');
select t.as_user(:'sres'::uuid);
select t.fails(format('select t.confirm_arb_agreement(%L, %L, ''2.2.2.2'', ''ua'')', :'arb2', :'doc2'), 'T1 the other party cannot confirm a different file (this used to leave the file stuck)', 'ملفًا آخر');
select t.confirm_arb_agreement(:'arb2'::uuid, :'doc1'::uuid, '2.2.2.2', 'ua');
select t.as_super();
select t.ok((select status = 'selection' from public.arbitrations where id = :'arb2'::uuid), 'T2 confirming the same file completes the stage');
select t.ok((select bool_and(doc_hash = repeat('1', 64) and aal is not null) from public.arb_agreement_confirmations where arbitration_id = :'arb2'::uuid), 'T3 the confirmation records the file hash and the assurance level');

select t.make_arb_agreement(:'scla'::uuid, :'sres'::uuid, :'smed'::uuid, 'sres@t.com') as arb3 \gset
select t.as_user(:'scla'::uuid);
select t.put_object(:'arb3' || '/a1');
select t.register_arb_document(:'arb3'::uuid, 'اتفاق.pdf', :'arb3' || '/a1', 'application/pdf', 1000, repeat('3', 64), 'arbitration_agreement') as doc3 \gset
select t.confirm_arb_agreement(:'arb3'::uuid, :'doc3'::uuid, '1.1.1.1', 'ua');
select t.fails(format('select public.save_arb_agreement(%L, %L)', :'arb3', repeat('نص ', 120)), 'T4 once a scan is confirmed, no platform text can be drafted', 'أُكّد اتفاق');

select t.make_arb_agreement(:'scla'::uuid, :'sres'::uuid, :'smed'::uuid, 'sres@t.com') as arb4 \gset
select t.as_user(:'scla'::uuid);
select t.put_object(:'arb4' || '/a1');
select t.register_arb_document(:'arb4'::uuid, 'اتفاق.pdf', :'arb4' || '/a1', 'application/pdf', 1000, repeat('4', 64), 'arbitration_agreement') as doc4 \gset
select public.save_arb_agreement(:'arb4'::uuid, 'اتفاق تحكيم بلا أقواس. ' || repeat('نص الاتفاق ', 40));
select public.open_arb_agreement(:'arb4'::uuid);
select t.fails(format('select t.confirm_arb_agreement(%L, %L, ''1.1.1.1'', ''ua'')', :'arb4', :'doc4'), 'T5 once the platform text is open, a scan cannot be confirmed', 'يجري توقيع');

-- ====================================================== W. the award signed on the platform
select t.make_arb(:'scla'::uuid, :'sres'::uuid, :'smed'::uuid, :'sarb'::uuid, 'sres@t.com') as arbw \gset
select t.as_user(:'sarb'::uuid);
select public.close_proceedings(:'arbw'::uuid);
select public.save_award_draft(:'arbw'::uuid, 'حكم التحكيم. [اسم الطرف] علامة-سرية-123 ' || repeat('أسباب الحكم والمنطوق. ', 12));
select draft_hash as wh1 from public.arb_awards where arbitration_id = :'arbw'::uuid \gset
select t.fails(format('select t.sign_award(%L, %L, (now() at time zone ''Africa/Cairo'')::date, ''3.3.3.3'', ''ua'')', :'arbw', :'wh1'), 'W1 a draft with an unfilled [..] cannot be signed', 'أقواسًا');
select public.save_award_draft(:'arbw'::uuid, 'حكم التحكيم. حكمت الهيئة لصالح المدّعي علامة-سرية-123 ' || repeat('أسباب الحكم والمنطوق. ', 12));
select draft_hash as wh from public.arb_awards where arbitration_id = :'arbw'::uuid \gset
select t.fails(format('select t.sign_award(%L, %L, (now() at time zone ''Africa/Cairo'')::date, ''3.3.3.3'', ''ua'')', :'arbw', :'wh1'), 'W0 signing an older saved text (stale hash) is refused', 'تغيّر نص الحكم');

select t.as_user(:'scla'::uuid);
select t.fails(format('select t.sign_award(%L, %L, (now() at time zone ''Africa/Cairo'')::date, ''1.1.1.1'', ''ua'')', :'arbw', :'wh'), 'W2 a party cannot sign the award', 'غير مصرح');
select t.as_user(:'sarb'::uuid, 'aal1');
select t.fails(format('select t.sign_award(%L, %L, (now() at time zone ''Africa/Cairo'')::date, ''3.3.3.3'', ''ua'')', :'arbw', :'wh'), 'W3 the arbitrator needs the second factor in this session', 'بخطوتين');
select t.as_user(:'sarb'::uuid);
select t.fails(format('select t.sign_award(%L, %L, (now() at time zone ''Africa/Cairo'')::date + 3, ''3.3.3.3'', ''ua'')', :'arbw', :'wh'), 'W4 a future award date is refused', 'تاريخ الحكم');
select t.fails(format('select public.sign_award(%L, ''x'', current_date, ''3.3.3.3'', ''ua'')', :'arbw'), 'W5 the signing function itself is closed to users', 'permission denied');
select t.sign_award(:'arbw'::uuid, :'wh', (now() at time zone 'Africa/Cairo')::date, '3.3.3.3', 'ua');

select t.as_super();
select t.ok((select status = 'closed' and outcome = 'award_issued' from public.arbitrations where id = :'arbw'::uuid), 'W6 signing the award closes the file with the award outcome');
select t.ok((select status = 'issued' and signing_mode = 'platform' and signed_at is not null and signer_aal = 'aal2' and signed_record is not null from public.arb_awards where arbitration_id = :'arbw'::uuid), 'W7 the award is issued in platform mode with its frozen record');
select t.ok((select signed_record->>'award_text_sha256' = draft_hash and signed_record->>'award_text' = draft_text
               and signed_record->'arbitrator'->>'name' = 'Arbitrator S' and signed_record->>'format' = 'hayah.arbitration-award.v1'
               and position('3.3.3.3' in signed_record::text) = 0 from public.arb_awards where arbitration_id = :'arbw'::uuid), 'W8 the record carries the exact text and its hash, the arbitrator, and no IP address');
select t.fails($$update public.arb_awards set draft_text = 'تغيير' where status = 'issued'$$, 'W9 an issued award text cannot be changed, even by the owner', 'لا يُعدَّل');
select t.fails($$update public.arb_awards set award_date = award_date - 1 where status = 'issued'$$, 'W10 nor its date', 'لا يُعدَّل');
select t.fails($$update public.arb_awards set signing_mode = 'paper' where status = 'issued'$$, 'W11 nor its signing mode', 'لا يُعدَّل');
select t.attach_arb_signature('award', :'arbw'::uuid, 'c2ln', 'k1');
select t.fails(format('select t.attach_arb_signature(''award'', %L, ''other'', ''k1'')', :'arbw'), 'W12 the platform signature is attached once', 'موقَّع من قبل');
select t.as_user(:'sres'::uuid);
select t.ok((select platform_signature = 'c2ln' and signed_record is not null from public.arb_awards where arbitration_id = :'arbw'::uuid), 'W13 a party reads the issued award, its record and the platform signature');
select t.as_user(:'sstr'::uuid);
select t.ok((select count(*) from public.arb_awards) = 0, 'W14 an outsider reads nothing');

-- the paper route still works and is marked as such
select t.make_arb(:'scla'::uuid, :'sres'::uuid, :'smed'::uuid, :'sarb'::uuid, 'sres@t.com') as arbp \gset
select t.as_user(:'sarb'::uuid);
select public.close_proceedings(:'arbp'::uuid);
select public.save_award_draft(:'arbp'::uuid, 'حكم التحكيم الورقي. ' || repeat('أسباب الحكم والمنطوق. ', 12));
select t.put_object(:'arbp' || '/award.pdf');
select t.register_arb_document(:'arbp'::uuid, 'الحكم الموقع.pdf', :'arbp' || '/award.pdf', 'application/pdf', 2048, repeat('9', 64), 'award_signed') as awd \gset
select public.issue_award(:'arbp'::uuid, :'awd'::uuid, (now() at time zone 'Africa/Cairo')::date);
select t.as_super();
select t.ok((select status = 'issued' and signing_mode = 'paper' and signed_record is null from public.arb_awards where arbitration_id = :'arbp'::uuid), 'W15 the paper route issues the award and is marked as paper');

-- ====================================================== L. texts never leak into the audit log
select t.as_super();
select t.ok((select count(*) from public.audit_logs where position('علامة-سرية-123' in coalesce(new_state::text, '') || coalesce(previous_state::text, '')) > 0) = 0, 'L1 neither the agreement text nor the award text (nor the frozen records) enters the audit log');
select t.ok((select count(*) from public.audit_logs where event_type like 'arb_agreement%' or event_type = 'arb_awards.UPDATE') > 0, 'L2 the signing steps themselves are in the audit log');

-- ====================================================== V. the admin's looks are visible
select t.as_user(:'sadm'::uuid);
select public.log_admin_view('arbitration', :'arbw'::uuid);
select public.log_admin_view('arbitration', :'arbw'::uuid);
select t.as_super();
select t.ok((select count(*) from public.audit_logs where event_type = 'admin.view_arbitration' and dispute_id = :'arbw'::uuid) = 1, 'V1 an admin look is logged once per hour per file');
select t.as_user(:'scla'::uuid);
select public.log_admin_view('arbitration', :'arbw'::uuid);
select t.ok(position('admin.view_arbitration' in public.arb_timeline(:'arbw'::uuid)::text) > 0, 'V2 the parties see the admin look in their own timeline');
select t.as_super();
select t.ok((select count(*) from public.audit_logs where event_type = 'admin.view_arbitration' and actor_id = :'scla'::uuid) = 0, 'V3 a non-admin call writes nothing');
select t.ok((public.verify_audit_chain()->>'ok')::boolean, 'V4 the audit chain still verifies');

-- ====================================================== P. function privileges (a new service-only function cannot be forgotten)
select t.as_super();
select t.ok((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname like '%\_srv') >= 8, 'P0 the check below is not vacuous (many server-only functions exist)');
select t.ok(not exists (
  select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and (p.proname like '%\_srv' or p.proname in ('act_as', 'attach_record_signature', 'attach_arb_signature', 'sign_arb_agreement', 'sign_award',
                                                   'arb_agreement_record', 'arb_award_record', 'accept_arb_rules', 'confirm_arb_agreement'))
    and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))
), 'P1 no server-only function is executable by anon or authenticated');
create function public.zz_default_privilege_probe() returns int language sql as $$ select 1 $$;
select t.ok(not has_function_privilege('authenticated', 'public.zz_default_privilege_probe()', 'execute')
        and not has_function_privilege('anon', 'public.zz_default_privilege_probe()', 'execute'), 'P2 a function created without an explicit grant is not callable from the API');
drop function public.zz_default_privilege_probe();
