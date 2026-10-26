-- Assertion-based tests. Any failure aborts with a non-zero exit (psql -v ON_ERROR_STOP=1).
\set ON_ERROR_STOP 1
\pset tuples_only on
\pset format unaligned

\set adm  a0000000-0000-0000-0000-000000000001
\set med  a0000000-0000-0000-0000-000000000002
\set med2 a0000000-0000-0000-0000-000000000003
\set cla  a0000000-0000-0000-0000-000000000004
\set res  a0000000-0000-0000-0000-000000000005
\set str  a0000000-0000-0000-0000-000000000006

-- ============================================================ A. accounts
select t.as_super();
insert into auth.users (id, email, raw_user_meta_data) values
 (:'adm'::uuid,  'admin@t.com', '{"full_name":"Admin","requested_role":"admin"}'),
 (:'med'::uuid,  'med@t.com',   '{"full_name":"Mediator One","requested_role":"mediator"}'),
 (:'med2'::uuid, 'med2@t.com',  '{"full_name":"Mediator Two","requested_role":"mediator"}'),
 (:'cla'::uuid,  'cla@t.com',   '{"full_name":"Claimant Co"}'),
 (:'res'::uuid,  'res@t.com',   '{"full_name":"Respondent Co"}'),
 (:'str'::uuid,  'str@t.com',   '{"full_name":"Stranger"}');
select t.ok((select count(*) from public.profiles where role <> 'party') = 0, 'A1 signup metadata can never grant a privileged role');
update public.profiles set role = 'admin' where id = :'adm'::uuid;
update public.profiles set role = 'mediator', kyc_status = 'verified' where id in (:'med'::uuid, :'med2'::uuid);
select t.ok((select count(*) from public.mediator_profiles) = 2, 'A2 promoting to mediator creates the mediator profile');

select t.as_user(:'cla'::uuid);
update public.profiles set role = 'admin', kyc_status = 'verified' where id = :'cla'::uuid;
select t.ok((select role from public.profiles where id = :'cla'::uuid) = 'party'
        and (select kyc_status from public.profiles where id = :'cla'::uuid) = 'pending',
        'A3 a user cannot promote or verify himself');
select t.fails($$insert into public.disputes (title,description,dispute_type,dispute_value_egp,created_by,claimant_id,agreement_document_id)
  select 'x','y','civil',100000,id,id,(select id from public.legal_documents limit 1) from public.profiles where email='cla@t.com'$$,
  'A4 direct insert into disputes is denied', 'permission denied');
select t.as_anon();
select t.fails($$select public.create_dispute('a','b','commercial',100000,'x@y.com','')$$, 'A5 anonymous cannot call create_dispute', 'permission denied');
select t.ok(public.invitation_preview('missing-token') is null, 'A6 the public invitation preview works without login');

-- ===================================================== B. platform consent
select t.as_user(:'cla'::uuid);
select t.ok(not public.has_platform_consent(), 'B1 no platform consent at the start');
select t.accept_platform();
select t.ok(public.has_platform_consent(), 'B2 accepting current terms and privacy is recorded');
select t.fails($$select public.publish_legal_document('terms','عنوان','نص النسخة الجديدة طويل بما يكفي هنا')$$, 'B3 a non-admin cannot publish legal text', 'غير مصرح');
select t.as_user(:'adm'::uuid);
select public.publish_legal_document('terms', 'شروط الاستخدام', 'نص الشروط المعتمد يتضمن التزامات الأطراف وحدود المسؤولية.');
select t.as_user(:'cla'::uuid);
select t.ok(not public.has_platform_consent(), 'B4 a new terms version requires acceptance again');
select t.fails(format('select t.accept_legal(%L, null, ''ip'', ''ua'')',
  (select id from public.legal_documents where kind = 'terms' and version = 1)), 'B5 an outdated platform document cannot be accepted', 'لم تعد سارية');
select t.accept_platform();
select t.ok(public.has_platform_consent(), 'B6 accepting the new version restores access');

-- ============================================ C. read gate + version pinning
select public.create_dispute('نزاع توريد بضائع', 'وصف طويل للنزاع يتجاوز الخمسين حرفا حتى يكون صالحا للاختبار في قاعدة البيانات', 'commercial', 120000, 'RES@t.com ', '0100')::text as r \gset
select (:'r'::jsonb)->>'id' as did \gset
select (:'r'::jsonb)->>'token' as tok \gset
select (public.dispute_gate_info(:'did'::uuid))->'doc'->>'id' as doc1 \gset
select t.ok((public.dispute_gate_info(:'did'::uuid)->>'accepted')::boolean = false, 'C1 the gate reports "not accepted"');
select t.ok((select count(*) from public.disputes) = 0, 'C2 RLS hides the dispute itself until the agreement is accepted');
select t.ok(jsonb_array_length(public.my_pending_agreements()) = 1, 'C3 the pending-agreements list shows the file');
select t.fails(format('select t.register_document(%L, ''a.pdf'', %L, ''application/pdf'', 1, %L)', :'did', :'did' || '/a', repeat('a', 64)), 'C4 no document registration before accepting the agreement', 'قبول اتفاقية');

select t.as_user(:'str'::uuid);
select t.ok(public.dispute_gate_info(:'did'::uuid) is null, 'C5 an outsider gets nothing from the gate');
select t.fails(format('select t.accept_legal(%L,%L,''ip'',''ua'')', :'doc1', :'did'), 'C6 an outsider cannot accept for a dispute', 'غير مصرح');
select t.as_user(:'adm'::uuid);
select t.fails(format('select t.accept_legal(%L,%L,''ip'',''ua'')', :'doc1', :'did'), 'C7 an admin cannot accept on a party''s behalf', 'غير مصرح');

select t.as_user(:'cla'::uuid);
select t.fails(format('select t.accept_legal(%L, null, ''ip'', ''ua'')', :'doc1'), 'C8 the agreement needs a dispute id', 'خاصة بنزاع');
select t.accept_legal(:'doc1'::uuid, :'did'::uuid, '9.9.9.9', 'ua');
select t.ok((select count(*) from public.disputes) = 1, 'C9 after accepting, the claimant reads the dispute');

select t.as_user(:'adm'::uuid);
select public.publish_legal_document('mediation_agreement', 'اتفاقية الوساطة', 'نص اتفاقية الوساطة المعتمد، النسخة الثانية.');
select id as doc2 from public.legal_documents where kind = 'mediation_agreement' and is_current \gset
select t.as_user(:'res'::uuid);
select public.accept_invitation(:'tok');
select t.fails(format('select t.accept_legal(%L,%L,''ip'',''ua'')', :'doc2', :'did'),
  'C10 a version other than the dispute''s pinned one is refused', 'لا تطابق');
select t.accept_legal(:'doc1'::uuid, :'did'::uuid, '2.2.2.2', 'ua');
select t.as_user(:'cla'::uuid);
select (public.create_dispute('نزاع ثان', 'وصف طويل للنزاع يتجاوز الخمسين حرفا حتى يكون صالحا للاختبار في قاعدة البيانات', 'commercial', 90000, 'res@t.com', ''))->>'id' as did2 \gset
select t.ok((public.dispute_gate_info(:'did2'::uuid)->'doc'->>'id') = :'doc2', 'C11 a new dispute is pinned to the new version');
select t.as_user(:'str'::uuid);
select t.ok(not public.has_agreement(:'did'::uuid, :'cla'::uuid), 'C12 outsiders cannot probe consent status');

-- ================================================== D. mediator selection
select t.as_user(:'cla'::uuid);
select public.propose_mediator(:'did'::uuid, :'med'::uuid);
select t.fails(format('select public.party_respond_mediator(%L,true)', (select id from public.mediator_assignments limit 1)),
  'D1 the proposer cannot approve his own proposal', 'الطرف الآخر');
select t.as_user(:'res'::uuid);
select public.party_respond_mediator((select id from public.mediator_assignments limit 1), true);
select t.as_user(:'med'::uuid);
select t.ok((select count(*) from public.disputes) = 0, 'D2 the mediator cannot read the file before accepting the agreement');
select t.ok((public.dispute_gate_info(:'did'::uuid)->>'accepted')::boolean = false, 'D3 the mediator sees the gate');
select t.fails(format('select public.mediator_respond(%L,true)', (select id from public.mediator_assignments limit 1)),
  'D4 the mediator cannot take the case before accepting the agreement', 'اقرأ اتفاقية');
select t.accept_legal(:'doc1'::uuid, :'did'::uuid, '3.3.3.3', 'ua');
select public.mediator_respond((select id from public.mediator_assignments limit 1), true);
select t.ok((select status from public.disputes where id = :'did'::uuid) = 'active', 'D5 the dispute is active after the mediator accepts');

-- ============================================ E. sessions, documents, settlement
select t.as_user(:'cla'::uuid);
select t.fails(format('select public.schedule_session(%L, now() + interval ''1 day'', 60)', :'did'), 'E1 a party cannot schedule sessions', 'الوسيط وحده');
select t.as_user(:'med'::uuid);
select public.schedule_session(:'did'::uuid, now() + interval '1 day', 60);
select t.ok((select count(*) from public.sessions) = 1, 'E2 the mediator schedules a session');

select t.as_user(:'cla'::uuid);
select t.put_object(:'did' || '/f1');
select t.register_document(:'did'::uuid, 'contract.pdf', :'did' || '/f1', 'application/pdf', 1000, repeat('a', 64), 'contract');
select t.ok((select count(*) from public.documents) = 1, 'E3 a party who accepted can upload');
select t.fails($$update public.documents set sha256_hash = 'forged'$$, 'E4 documents cannot be edited', 'permission denied');
select t.fails($$delete from public.documents$$, 'E5 documents cannot be deleted', 'permission denied');
select t.as_user(:'str'::uuid);
select t.fails(format('select t.register_document(%L, ''x.pdf'', %L, ''application/pdf'', 1, %L)', :'did', :'did' || '/f2', repeat('b', 64)), 'E6 an outsider cannot register a document', 'غير مصرح');

select t.as_user(:'cla'::uuid);
select t.fails(format('select public.save_settlement(%L, repeat(''x'', 80))', :'did'), 'E7 a party cannot draft the settlement', 'الوسيط وحده');
select t.as_user(:'med'::uuid);
select public.save_settlement(:'did'::uuid, 'اتفاق تسوية: يلتزم الطرف الثاني بسداد مبلغ مئة ألف جنيه خلال ثلاثين يوما من تاريخ هذا الاتفاق.');
select public.save_settlement(:'did'::uuid, 'اتفاق تسوية (نسخة معدلة): يلتزم الطرف الثاني بسداد مبلغ مئة ألف جنيه خلال ثلاثين يوما من تاريخ هذا الاتفاق.');
select t.ok((select version from public.settlements) = 2, 'E8 saving again creates version 2');
select t.as_user(:'cla'::uuid);
select t.fails(format('select t.sign_settlement(%L, ''1.1.1.1'', ''ua'')', :'did'), 'E9 no signing before the settlement is opened', 'غير مفتوح');
select t.as_user(:'med'::uuid);
select public.submit_settlement(:'did'::uuid);
select t.fails(format('select public.save_settlement(%L, repeat(''y'', 80))', :'did'), 'E10 the text is locked once opened for signature', 'مُغلق');
select t.fails(format('select t.sign_settlement(%L, ''1.1.1.1'', ''ua'')', :'did'), 'E11 the mediator cannot sign', 'للأطراف فقط');
select t.as_user(:'cla'::uuid);
select t.sign_settlement(:'did'::uuid, '1.1.1.1', 'ua');
select t.fails(format('select t.sign_settlement(%L, ''1.1.1.1'', ''ua'')', :'did'), 'E12 signing twice is refused', 'وقّعت');
select t.as_user(:'res'::uuid);
select t.sign_settlement(:'did'::uuid, '2.2.2.2', 'ua');
select t.ok((select status from public.disputes where id = :'did'::uuid) = 'signed'
        and (select status from public.settlements) = 'signed', 'E13 both signatures complete the settlement');
select t.ok(jsonb_array_length(public.dispute_signatures(:'did'::uuid)) = 2
        and (select count(distinct e->>'content_hash') from jsonb_array_elements(public.dispute_signatures(:'did'::uuid)) e) = 1
        and (public.dispute_signatures(:'did'::uuid)->0->>'content_hash') = (select content_hash from public.settlements),
        'E14 both signatures bind to the same locked text hash');

-- ================================================================ F. audit
select t.as_user(:'cla'::uuid);
select t.fails($$insert into public.audit_logs (event_type) values ('FAKE')$$, 'F1 users cannot write the audit log', 'permission denied');
select t.fails($$update public.audit_logs set event_type = 'x'$$, 'F2 users cannot edit the audit log', 'permission denied');
select t.as_super();
select t.fails($$update public.audit_logs set event_type = 'x' where seq = 3$$, 'F3 not even a superuser can edit it normally', 'append-only');
select t.fails($$delete from public.audit_logs$$, 'F4 nor delete it', 'append-only');
select t.ok((select count(*) from public.audit_logs where hash_version <> 2) = 0, 'F5 every row uses hash version 2');
select t.as_user(:'adm'::uuid);
select t.ok((public.verify_audit_chain()->>'ok')::boolean, 'F6 the full chain verifies');
select t.as_user(:'str'::uuid);
select t.fails($$select public.verify_audit_chain()$$, 'F7 only admins can run the full verification', 'غير مصرح');
select t.ok((select count(*) from public.audit_logs) = 0, 'F8 an outsider sees no audit rows');

-- =============================================================== G. records
select t.as_user(:'cla'::uuid);
select public.issue_dispute_record(:'did'::uuid) as rid \gset
select t.ok((select (record->'data'->'chain_check'->>'ok')::boolean from public.record_exports where id = :'rid'::uuid), 'G1 the record embeds a passing chain check');
select t.ok((select bool_and(g->>'ip' like '%.x') from public.record_exports e,
  jsonb_array_elements(e.record->'data'->'settlement'->'signatures') g where e.id = :'rid'::uuid), 'G2 other parties'' IPs are masked in a party''s record');
select t.fails($$select public.build_dispute_record(gen_random_uuid(), true)$$, 'G3 the internal builder is not callable', 'permission denied');
select t.as_user(:'str'::uuid);
select t.fails(format('select public.issue_dispute_record(%L)', :'did'), 'G4 an outsider cannot issue a record', 'غير مصرح');
select t.as_user(:'adm'::uuid);
select public.issue_dispute_record(:'did'::uuid) as aid \gset
select t.ok((select bool_and(g->>'ip' !~ '\.x$') from public.record_exports e,
  jsonb_array_elements(e.record->'data'->'settlement'->'signatures') g where e.id = :'aid'::uuid), 'G5 an admin record keeps full IPs');
select t.as_user(:'cla'::uuid);
select t.ok((select count(*) from public.record_exports) = 1, 'G6 a party cannot read the admin''s record');
select t.fails($$update public.record_exports set record_hash = 'x'$$, 'G7 records are immutable', 'permission denied');
select t.as_super();
select record_hash as h, record::text as rec from public.record_exports where id = :'rid'::uuid \gset
select t.as_anon();
select t.ok((public.verify_record(:'h', null)->>'found')::boolean, 'G8 public verification by hash');
select t.ok((public.verify_record(null, :'rec'::jsonb)->>'found')::boolean, 'G9 public verification by JSON');
select t.ok(not (public.verify_record(null, jsonb_set(:'rec'::jsonb, '{data,dispute,title}', '"مزوّر"'))->>'found')::boolean, 'G10 an edited record fails verification');
select t.ok(not (public.verify_record(repeat('0', 64), null)->>'found')::boolean, 'G11 an unknown hash fails verification');

-- ============================================================ H. metrics, anchor
select t.as_user(:'adm'::uuid);
select t.ok((public.admin_metrics()->'funnel'->>'signed')::int = 1 and (public.admin_metrics()->'funnel'->>'created')::int = 2, 'H1 metrics reflect the funnel');
select t.as_user(:'cla'::uuid);
select t.fails($$select public.admin_metrics()$$, 'H2 metrics are admin-only', 'غير مصرح');
select t.fails($$select public.audit_head()$$, 'H3 users cannot read the audit head', 'permission denied');
select t.as_service();
select public.audit_head()::text as head \gset
select (:'head'::jsonb)->>'seq' as aseq, (:'head'::jsonb)->>'row_hash' as ahash \gset
select t.as_user(:'adm'::uuid);
select t.ok((public.check_audit_anchor(:'aseq'::bigint, :'ahash')->>'ok')::boolean, 'H4 a stored anchor matches');
select t.ok((public.check_audit_anchor(:'aseq'::bigint, repeat('0', 64))->>'reason') = 'mismatch', 'H5 a wrong anchor is reported');

-- ============================================================ I. tampering
select t.as_super();
select row_hash as th, seq as tseq from public.audit_logs where event_type = 'documents.INSERT' order by seq limit 1 \gset
alter table public.audit_logs disable trigger audit_no_change;
update public.audit_logs set actor_id = :'str'::uuid where seq = :'tseq'::bigint;
alter table public.audit_logs enable trigger audit_no_change;
select t.as_user(:'adm'::uuid);
select t.ok(not (public.verify_audit_chain()->>'ok')::boolean, 'I1 changing only the actor is detected (the old hash formula missed this)');
select t.ok((public.check_audit_anchor(:'tseq'::bigint, :'th')->>'reason') = 'row_altered', 'I2 the altered row is pinpointed');

-- A database admin who rewrites the whole chain defeats the chain itself...
select t.as_super();
alter table public.audit_logs disable trigger audit_no_change;
do $$
declare r public.audit_logs; r2 public.audit_logs; prev text := null;
begin
  for r in select * from public.audit_logs order by seq loop
    update public.audit_logs set prev_hash = prev where seq = r.seq;
    select * into r2 from public.audit_logs where seq = r.seq;
    update public.audit_logs set row_hash = public.audit_row_hash(r2) where seq = r.seq;
    select row_hash into prev from public.audit_logs where seq = r.seq;
  end loop;
end $$;
alter table public.audit_logs enable trigger audit_no_change;
select t.as_user(:'adm'::uuid);
select t.ok((public.verify_audit_chain()->>'ok')::boolean, 'I3 a full rewrite by a DB admin is invisible to the chain alone');
-- ...but not the anchor that was emailed out before the rewrite.
select t.ok((public.check_audit_anchor(:'aseq'::bigint, :'ahash')->>'reason') = 'mismatch', 'I4 the externally stored anchor exposes the rewrite');
