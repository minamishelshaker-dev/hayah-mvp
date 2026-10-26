-- Trust boundary, data exposure, quotas, rate limits. Own accounts. Needs helpers.sql and lifecycle_tests.sql (t.make_active).
\set ON_ERROR_STOP 1
\pset tuples_only on
\pset format unaligned

\set xadm  c0000000-0000-0000-0000-000000000001
\set xmed  c0000000-0000-0000-0000-000000000002
\set xmedu c0000000-0000-0000-0000-000000000003
\set xcla  c0000000-0000-0000-0000-000000000004
\set xres  c0000000-0000-0000-0000-000000000005
\set xstr  c0000000-0000-0000-0000-000000000006
\set xspam c0000000-0000-0000-0000-000000000007

select t.as_super();
insert into auth.users (id, email, raw_user_meta_data) values
 (:'xadm'::uuid,  'xadmin@t.com', '{"full_name":"Admin X"}'),
 (:'xmed'::uuid,  'xmed@t.com',   '{"full_name":"Mediator Verified"}'),
 (:'xmedu'::uuid, 'xmedu@t.com',  '{"full_name":"Mediator Unverified"}'),
 (:'xcla'::uuid,  'xcla@t.com',   '{"full_name":"Claimant X"}'),
 (:'xres'::uuid,  'xres@t.com',   '{"full_name":"Respondent X"}'),
 (:'xstr'::uuid,  'xstr@t.com',   '{"full_name":"Stranger X"}'),
 (:'xspam'::uuid, 'xspam@t.com',  '{"full_name":"Spammer X"}');
update public.profiles set role = 'admin' where id = :'xadm'::uuid;
update public.profiles set role = 'mediator', kyc_status = 'verified', phone = '01000000000' where id = :'xmed'::uuid;
update public.profiles set role = 'mediator' where id = :'xmedu'::uuid;   -- promoted but NOT verified

-- ============================================ T1. API users can no longer write evidence directly
select t.as_user(:'xcla'::uuid);
select t.fails($$select public.accept_legal(gen_random_uuid(), gen_random_uuid(), '1.2.3.4', 'x')$$, 'T1 users cannot call accept_legal directly', 'permission denied');
select t.fails($$select public.sign_settlement(gen_random_uuid(), '8.8.8.8', 'Fake-Browser')$$, 'T2 users cannot call sign_settlement directly (no forged IP, no skipped password step)', 'permission denied');
select t.fails($$insert into public.documents (dispute_id,uploaded_by,file_name,file_path,file_size,mime_type,sha256_hash) values (gen_random_uuid(), gen_random_uuid(), 'x','y',1,'a/b','h')$$, 'T3 users cannot insert document rows directly', 'permission denied');
select t.fails($$select public.act_as(gen_random_uuid(), 'aal2')$$, 'T4 users cannot impersonate through act_as', 'permission denied');
select t.fails($$select public.register_document_srv(gen_random_uuid(), 'aal2', gen_random_uuid(), 'p', 'n', 'application/pdf', 1, repeat('a', 64), 'other')$$, 'T5 users cannot call the server-only registration', 'permission denied');
select t.as_anon();
select t.fails($$select public.rate_limit_hit('k', 1, 60)$$, 'T6 anonymous cannot touch the rate limiter', 'permission denied');

-- ============================================ T2. the server-side path enforces the real rules
select t.make_active(:'xcla'::uuid, :'xres'::uuid, :'xmed'::uuid, 'xres@t.com') as dx \gset
select t.as_user(:'xcla'::uuid);
select t.put_object(:'dx' || '/real');
select t.register_document(:'dx'::uuid, 'عقد.pdf', :'dx' || '/real', 'application/pdf', 2048, repeat('e', 64), 'contract') as docid \gset
select t.ok((select count(*) from public.documents where id = :'docid'::uuid) = 1, 'T7 a document with a real stored file registers');
select t.as_super();
select t.ok((select actor_id from public.audit_logs where event_type = 'documents.INSERT' and entity_id = :'docid'::uuid) = :'xcla'::uuid, 'T8 the audit log names the real actor, not an empty one');
select t.as_user(:'xcla'::uuid);
select t.fails(format('select t.register_document(%L, ''وهمي.pdf'', %L, ''application/pdf'', 123456, %L)', :'dx', :'dx' || '/never-uploaded', repeat('a', 64)), 'T9 a document without a stored file is refused', 'غير موجود في التخزين');
select t.put_object(:'dx' || '/page.html');
select t.fails(format('select t.register_document(%L, ''p.html'', %L, ''text/html'', 10, %L)', :'dx', :'dx' || '/page.html', repeat('a', 64)), 'T10 a file type outside the allow-list is refused', 'غير مسموح');
select t.fails(format('select t.register_document(%L, ''r.pdf'', %L, ''application/pdf'', 10, ''not-a-hash'')', :'dx', :'dx' || '/real'), 'T11 a malformed hash is refused', 'بصمة');
select t.fails(format('select t.register_document(%L, ''r.pdf'', %L, ''application/pdf'', 10, %L)', :'dx', gen_random_uuid()::text || '/real', repeat('a', 64)), 'T12 a path belonging to another dispute is refused', 'لا يخص');
select t.fails(format('select t.register_document(%L, ''r.pdf'', %L, ''application/pdf'', 99999999, %L)', :'dx', :'dx' || '/real', repeat('a', 64)), 'T13 an oversized file is refused', 'حجم');
select t.as_user(:'xstr'::uuid);
select t.fails(format('select t.register_document(%L, ''r.pdf'', %L, ''application/pdf'', 10, %L)', :'dx', :'dx' || '/real', repeat('a', 64)), 'T14 an outsider cannot register into the file', 'غير مصرح');
select t.as_super();
select t.ok(array_position((select allowed_mime_types from storage.buckets where id = 'documents'), 'application/pdf') is not null and array_position((select allowed_mime_types from storage.buckets where id = 'documents'), 'text/html') is null, 'T15 the storage bucket itself carries the allow-list');

-- ============================================ T3. no raw rows for members
select t.make_active(:'xcla'::uuid, :'xres'::uuid, :'xmed'::uuid, 'xres@t.com') as dy \gset
select t.as_user(:'xmed'::uuid);
select public.save_settlement(:'dy'::uuid, 'اتفاق تسوية: يلتزم الطرف الثاني بسداد مبلغ مئة ألف جنيه خلال ثلاثين يوما من تاريخ هذا الاتفاق.');
select public.submit_settlement(:'dy'::uuid);
select t.as_user(:'xcla'::uuid);
select t.sign_settlement(:'dy'::uuid, '10.0.0.1', 'UA-claimant');
select t.as_user(:'xres'::uuid);
select t.sign_settlement(:'dy'::uuid, '10.0.0.2', 'UA-respondent');
select t.ok((select count(*) from public.audit_logs) = 0, 'T16 a party reads no raw audit rows');
select t.ok((select count(*) from public.consents where user_id <> :'xres'::uuid) = 0, 'T17 a party cannot read the other participants'' consent rows (IP, browser)');
select t.ok((select count(*) from public.settlement_signatures where user_id <> :'xres'::uuid) = 0, 'T18 nor their signature rows');
select t.ok((select count(*) from public.profiles where id <> :'xres'::uuid) = 0, 'T19 nor their profile rows (e-mail, phone, bar number)');
select t.ok(jsonb_array_length(public.dispute_timeline(:'dy'::uuid)) > 5, 'T20 the whitelisted timeline works');
select t.ok(position('ip_address' in public.dispute_timeline(:'dy'::uuid)::text) = 0
        and position('user_agent' in public.dispute_timeline(:'dy'::uuid)::text) = 0
        and position('token' in public.dispute_timeline(:'dy'::uuid)::text) = 0
        and position('10.0.0' in public.dispute_timeline(:'dy'::uuid)::text) = 0, 'T21 the timeline carries no IP, browser or token');
select t.ok(jsonb_array_length(public.dispute_consents(:'dy'::uuid)) = 3 and position('ip' in public.dispute_consents(:'dy'::uuid)::text) = 0, 'T22 consent status shows who accepted, without IP');
select t.ok(jsonb_array_length(public.dispute_signatures(:'dy'::uuid)) = 2 and position('10.0.0' in public.dispute_signatures(:'dy'::uuid)::text) = 0, 'T23 signatures show who signed and when, without IP');
select t.ok((public.profile_names(array[:'xcla'::uuid, :'xmed'::uuid, :'xstr'::uuid])->>(:'xcla')) = 'Claimant X'
        and (public.profile_names(array[:'xcla'::uuid, :'xmed'::uuid, :'xstr'::uuid])->>(:'xmed')) = 'Mediator Verified'
        and not (public.profile_names(array[:'xstr'::uuid]) ? (:'xstr')), 'T24 names resolve for people on my files only');
select t.as_super();
select t.ok((select count(*) from public.consents where ip_address is not null) > 0
        and (select count(*) from public.settlement_signatures where ip_address = '10.0.0.1') = 1, 'T25 the evidence (IP, browser) is still stored for the platform and the admin');

-- ============================================ T4. mediator directory
select t.as_user(:'xstr'::uuid);
select t.ok((select count(*) from public.profiles where role = 'mediator') = 0, 'T26 a stranger cannot read mediators'' rows');
select t.ok(position('Mediator Verified' in public.mediator_directory()::text) > 0
        and position('Mediator Unverified' in public.mediator_directory()::text) = 0, 'T27 the directory lists verified mediators only');
select t.ok(position('email' in public.mediator_directory()::text) = 0 and position('phone' in public.mediator_directory()::text) = 0
        and position('xmed@t.com' in public.mediator_directory()::text) = 0 and position('01000000000' in public.mediator_directory()::text) = 0, 'T28 and exposes no e-mail or phone');
select t.make_active(:'xcla'::uuid, :'xres'::uuid, :'xmed'::uuid, 'xres@t.com') as dz \gset
select t.as_user(:'xcla'::uuid);
select public.create_dispute('نزاع لاختبار وسيط غير موثّق', 'وصف طويل للنزاع يتجاوز الخمسين حرفا حتى يكون صالحا للاختبار في قاعدة البيانات', 'commercial', 100000, 'xres@t.com', '')::text as rq \gset
select (:'rq'::jsonb)->>'id' as dq \gset
select (:'rq'::jsonb)->>'token' as kq \gset
select t.accept_legal((public.dispute_gate_info(:'dq'::uuid)->'doc'->>'id')::uuid, :'dq'::uuid, '1.1.1.1', 'ua');
select t.as_user(:'xres'::uuid);
select public.accept_invitation(:'kq');
select t.accept_legal((public.dispute_gate_info(:'dq'::uuid)->'doc'->>'id')::uuid, :'dq'::uuid, '1.1.1.1', 'ua');
select t.as_user(:'xcla'::uuid);
select t.fails(format('select public.propose_mediator(%L, %L)', :'dq', :'xmedu'), 'T29 an unverified mediator cannot be proposed', 'غير موجود');

-- ============================================ T5. fixes
-- metrics: only real settlements count as "settled"
select t.as_user(:'xadm'::uuid);
select (public.admin_metrics()->>'value_settled')::numeric as s0 \gset
select t.as_user(:'xcla'::uuid);
select public.close_dispute(:'dz'::uuid, 'no_settlement', 'لا اتفاق');
select t.as_user(:'xadm'::uuid);
select t.ok((public.admin_metrics()->>'value_settled')::numeric = :s0, 'T30 a file closed WITHOUT settlement does not count as settled value');
select t.as_user(:'xmed'::uuid);
select public.close_dispute(:'dy'::uuid, 'settled');
select t.as_user(:'xadm'::uuid);
select (public.admin_metrics()->>'value_settled')::numeric as s1 \gset
select t.as_super();
select t.ok(:s1 = :s0 and :s1 = (select coalesce(sum(dispute_value_egp), 0) from public.disputes where status = 'signed' or outcome = 'settled') and :s1 > 0,
  'T31 signed-then-closed files are counted once, and the total equals the real settled value');
-- brackets
select t.make_active(:'xcla'::uuid, :'xres'::uuid, :'xmed'::uuid, 'xres@t.com') as db \gset
select t.as_user(:'xmed'::uuid);
select public.save_settlement(:'db'::uuid, 'اتفاق تسوية: ١- [يكتب الوسيط التزامات الطرف الأول] ٢- يلتزم الطرف الثاني بسداد مبلغ مئة ألف جنيه.');
select t.fails(format('select public.submit_settlement(%L)', :'db'), 'T32 a settlement still holding [..] placeholders cannot be opened for signature', 'أقواس');
select public.save_settlement(:'db'::uuid, 'اتفاق تسوية: ١- يلتزم الطرف الأول بتسليم البضاعة ٢- يلتزم الطرف الثاني بسداد مبلغ مئة ألف جنيه.');
select public.submit_settlement(:'db'::uuid);
select t.ok((select status from public.settlements where dispute_id = :'db'::uuid) = 'pending_signatures', 'T33 the completed text opens for signature');
-- invitation quota
select t.as_user(:'xspam'::uuid);
select count(public.create_dispute('نزاع رقم ' || g, 'وصف طويل للنزاع يتجاوز الخمسين حرفا حتى يكون صالحا للاختبار في قاعدة البيانات', 'commercial', 100000, 'victim' || g || '@t.com', '')) as made from generate_series(1, 10) g \gset
select t.ok(:made = 10, 'T34 ten invitations in a day are allowed');
select t.fails($$select public.create_dispute('نزاع حادي عشر', 'وصف طويل للنزاع يتجاوز الخمسين حرفا حتى يكون صالحا للاختبار في قاعدة البيانات', 'commercial', 100000, 'victim11@t.com', '')$$, 'T35 the eleventh is refused (no mass-mailing through the platform)', 'الحد اليومي');

-- ============================================ T6. rate limiter
select t.as_service();
select t.ok(not public.rate_limit_hit('probe', 2, 60), 'T36 first hit passes');
select t.ok(not public.rate_limit_hit('probe', 2, 60), 'T37 second hit passes');
select t.ok(public.rate_limit_hit('probe', 2, 60), 'T38 the third hit is over the limit');
select t.ok(not public.rate_limit_hit('other-key', 2, 60), 'T39 another key is unaffected');
