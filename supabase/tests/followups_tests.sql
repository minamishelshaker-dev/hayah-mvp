-- Follow-ups: reopen settlement, my_actions, record signature attachment. Needs lifecycle_tests (t.make_active).
\set ON_ERROR_STOP 1
\pset tuples_only on
\pset format unaligned

\set fadm c0000000-0000-0000-0000-000000000001
\set fmed c0000000-0000-0000-0000-000000000002
\set fcla c0000000-0000-0000-0000-000000000004
\set fres c0000000-0000-0000-0000-000000000005
\set fstr c0000000-0000-0000-0000-000000000006

-- ======================================================== F1. reopen a settlement nobody signed
select t.make_active(:'fcla'::uuid, :'fres'::uuid, :'fmed'::uuid, 'xres@t.com') as df \gset
select t.as_user(:'fmed'::uuid);
select public.save_settlement(:'df'::uuid, 'اتفاق تسوية: ١- يلتزم الطرف الأول بتسليم البضاعة ٢- يلتزم الطرف الثاني بسداد مبلغ مئة ألف جنيه.');
select public.submit_settlement(:'df'::uuid);
select t.as_user(:'fcla'::uuid);
select t.fails(format('select public.reopen_settlement(%L)', :'df'), 'F1 a party cannot reopen the settlement', 'غير مصرح');
select t.as_user(:'fmed'::uuid);
select public.reopen_settlement(:'df'::uuid, 'تصحيح بند');
select t.ok((select status from public.settlements where dispute_id = :'df'::uuid) = 'draft', 'F2 the mediator reopens an unsigned settlement');
select public.save_settlement(:'df'::uuid, 'اتفاق تسوية (معدّل): ١- يلتزم الطرف الأول بتسليم البضاعة خلال أسبوع ٢- يلتزم الطرف الثاني بسداد مبلغ مئة ألف جنيه.');
select public.submit_settlement(:'df'::uuid);
select t.as_user(:'fcla'::uuid);
select t.sign_settlement(:'df'::uuid, '1.1.1.1', 'ua');
select t.as_user(:'fmed'::uuid);
select t.fails(format('select public.reopen_settlement(%L)', :'df'), 'F3 once someone has signed, the text cannot be reopened', 'وقّع أحد الطرفين');

-- ======================================================== F2. what is waiting for me
select t.as_user(:'fres'::uuid);
select t.ok(exists (select 1 from jsonb_array_elements(public.my_actions()) e where e->>'dispute_id' = :'df' and e->>'code' = 'sign_settlement'), 'F4 the respondent is told to sign');
select t.as_user(:'fcla'::uuid);
select t.ok(not exists (select 1 from jsonb_array_elements(public.my_actions()) e where e->>'dispute_id' = :'df' and e->>'code' = 'sign_settlement'), 'F5 the claimant who already signed is not');
select t.as_user(:'fstr'::uuid);
select t.ok(jsonb_array_length(public.my_actions()) = 0, 'F6 an outsider has nothing waiting');
select t.as_user(:'fcla'::uuid);
select public.create_dispute('نزاع للتنبيه', 'وصف طويل للنزاع يتجاوز الخمسين حرفا حتى يكون صالحا للاختبار في قاعدة البيانات', 'commercial', 100000, 'xres@t.com', '')::text as rr2 \gset
select t.ok(exists (select 1 from jsonb_array_elements(public.my_actions()) e where e->>'dispute_id' = (:'rr2'::jsonb)->>'id' and e->>'code' = 'accept_agreement'), 'F7 a new file asks its creator to accept the agreement first');

-- ======================================================== F3. record signatures
select t.as_user(:'fcla'::uuid);
select public.issue_dispute_record(:'df'::uuid) as rid \gset
select t.fails(format('select public.attach_record_signature(%L, ''sig'', ''k1'')', :'rid'), 'F8 users cannot attach signatures', 'permission denied');
select t.as_service();
select public.attach_record_signature(:'rid'::uuid, 'c2lnbmF0dXJl', 'key-1');
select t.fails(format('select public.attach_record_signature(%L, ''other'', ''key-2'')', :'rid'), 'F9 a signature can be attached only once', 'موقَّع من قبل');
select t.as_super();
select t.ok((select signature = 'c2lnbmF0dXJl' and signing_key_id = 'key-1' and signed_at is not null from public.record_exports where id = :'rid'::uuid), 'F10 the signature is stored with its key id');
select t.ok((select count(*) from public.audit_logs where event_type = 'record_exports.SIGNED' and entity_id = :'rid'::uuid) = 1, 'F11 attaching a signature is audited');
select record_hash as rh from public.record_exports where id = :'rid'::uuid \gset
select t.as_anon();
select t.ok((public.verify_record(:'rh', null)->>'signed')::boolean and (public.verify_record(:'rh', null)->>'signing_key_id') = 'key-1', 'F12 public verification reports that the record is signed, and with which key');
