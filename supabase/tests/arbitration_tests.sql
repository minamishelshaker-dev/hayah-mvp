-- Arbitration, phase A. Own accounts. Needs helpers.sql and lifecycle_tests.sql (t.make_active).
\set ON_ERROR_STOP 1
\pset tuples_only on
\pset format unaligned

\set dadm  d0000000-0000-0000-0000-000000000001
\set dmed  d0000000-0000-0000-0000-000000000002
\set dmed2 d0000000-0000-0000-0000-000000000003
\set darb  d0000000-0000-0000-0000-000000000004
\set darbu d0000000-0000-0000-0000-000000000005
\set darb2 d0000000-0000-0000-0000-000000000006
\set dcla  d0000000-0000-0000-0000-000000000007
\set dres  d0000000-0000-0000-0000-000000000008
\set dstr  d0000000-0000-0000-0000-000000000009

select t.as_super();
insert into auth.users (id, email, raw_user_meta_data) values
 (:'dadm'::uuid,  'dadmin@t.com',  '{"full_name":"Admin D"}'),
 (:'dmed'::uuid,  'dmed@t.com',    '{"full_name":"Mediator D"}'),
 (:'dmed2'::uuid, 'dmed2@t.com',   '{"full_name":"Mediator D2"}'),
 (:'darb'::uuid,  'darb@t.com',    '{"full_name":"Arbitrator One","requested_role":"arbitrator"}'),
 (:'darbu'::uuid, 'darbu@t.com',   '{"full_name":"Arbitrator Unverified"}'),
 (:'darb2'::uuid, 'darb2@t.com',   '{"full_name":"Arbitrator Two"}'),
 (:'dcla'::uuid,  'dcla@t.com',    '{"full_name":"Claimant D"}'),
 (:'dres'::uuid,  'dres@t.com',    '{"full_name":"Respondent D"}'),
 (:'dstr'::uuid,  'dstr@t.com',    '{"full_name":"Stranger D"}');
select t.ok((select role from public.profiles where id = :'darb'::uuid) = 'party'
        and (select requested_role from public.profiles where id = :'darb'::uuid) = 'arbitrator', 'R1 asking for the arbitrator role grants nothing by itself');
update public.profiles set role = 'admin' where id = :'dadm'::uuid;
update public.profiles set role = 'mediator', kyc_status = 'verified' where id in (:'dmed'::uuid, :'dmed2'::uuid);
update public.profiles set role = 'arbitrator', kyc_status = 'verified', phone = '01111111111' where id in (:'darb'::uuid, :'darb2'::uuid);
update public.profiles set role = 'arbitrator' where id = :'darbu'::uuid;
select t.ok((select count(*) from public.mediator_profiles where id in (:'darb'::uuid, :'darb2'::uuid, :'darbu'::uuid)) = 3, 'R2 promoting to arbitrator creates the neutral profile');

select t.as_user(:'dstr'::uuid);
select t.ok(position('Arbitrator One' in public.arbitrator_directory()::text) > 0 and position('Arbitrator Unverified' in public.arbitrator_directory()::text) = 0, 'R3 the directory lists verified arbitrators only');
select t.ok(position('darb@t.com' in public.arbitrator_directory()::text) = 0 and position('01111111111' in public.arbitrator_directory()::text) = 0, 'R4 and exposes no e-mail or phone');

-- ====================================================== helper: a whole arbitration, up to a chosen stage
select t.as_super();
create or replace function t.make_arb(c uuid, r uuid, med uuid, arb_user uuid, r_email text, p_stop text default 'full') returns uuid language plpgsql as $$
declare v_src uuid; v_arb uuid; v_doc uuid;
begin
  v_src := t.make_active(c, r, med, r_email);
  perform t.as_user(c);
  v_arb := public.propose_escalation(v_src, 'ملف تحكيم تجريبي', repeat('ملخص الطلب ', 6), 150000, false);
  perform t.accept_rules(v_arb);
  perform t.as_user(r); perform t.accept_rules(v_arb); perform public.respond_escalation(v_arb, true);
  perform t.as_user(c); perform t.put_object(v_arb::text || '/agr');
  v_doc := t.register_arb_document(v_arb, 'اتفاق.pdf', v_arb::text || '/agr', 'application/pdf', 1000, repeat('a', 64), 'arbitration_agreement');
  perform t.confirm_arb_agreement(v_arb, v_doc, '1.1.1.1', 'ua');
  perform t.as_user(r); perform t.confirm_arb_agreement(v_arb, v_doc, '2.2.2.2', 'ua');
  if p_stop = 'selection' then return v_arb; end if;
  perform t.as_user(c); perform public.propose_arbitrator(v_arb, arb_user);
  perform t.as_user(r); perform public.party_respond_arbitrator((select id from public.arb_assignments where arbitration_id = v_arb and status = 'proposed'), true);
  perform t.as_user(arb_user); perform t.accept_rules(v_arb);
  perform public.arbitrator_respond((select id from public.arb_assignments where arbitration_id = v_arb and status = 'approved'), true, repeat('أقرّ باستقلالي وحيادي التام تجاه الطرفين. ', 2));
  return v_arb;
end $$;

-- ====================================================== A. escalation: a NEW, clean, consensual file
select t.make_active(:'dcla'::uuid, :'dres'::uuid, :'dmed'::uuid, 'dres@t.com') as src \gset
select t.as_user(:'dstr'::uuid);
select t.fails(format('select public.propose_escalation(%L, ''عنوان طلب التحكيم'', %L, 150000)', :'src', repeat('ملخص الطلب ', 6)), 'A1 an outsider cannot escalate a file', 'غير مصرح');
select t.as_user(:'dmed'::uuid);
select t.fails(format('select public.propose_escalation(%L, ''عنوان طلب التحكيم'', %L, 150000)', :'src', repeat('ملخص الطلب ', 6)), 'A2 the mediator cannot escalate on the parties'' behalf', 'غير مصرح');
select t.as_user(:'dcla'::uuid);
select t.fails(format('select public.propose_escalation(%L, ''قصير'', ''ملخص قصير'', 150000)', :'src'), 'A3 the claim must be typed afresh (title and summary)', 'اكتب عنوانًا');
select public.propose_escalation(:'src'::uuid, 'مطالبة بثمن بضاعة موردة', repeat('ملخص الطلب كما يكتبه المدّعي من جديد. ', 3), 150000, true) as arb \gset
select t.fails(format('select public.propose_escalation(%L, ''عنوان ثانٍ للطلب'', %L, 100000)', :'src', repeat('ملخص آخر للطلب ', 4)), 'A4 one open arbitration per mediation file', 'يوجد ملف تحكيم');
select t.as_super();
select t.ok((select status = 'proposed' and claimant_id = :'dcla'::uuid and respondent_id = :'dres'::uuid and arb_number like 'HAYAH-ARB-%' and prior_clause from public.arbitrations where id = :'arb'::uuid), 'A5 the arbitration is created as a separate file with its own number');
select t.ok((select count(*) from public.arb_documents where arbitration_id = :'arb'::uuid) = 0
        and (select count(*) from public.arb_steps where arbitration_id = :'arb'::uuid) = 0
        and (select count(*) from public.arb_submissions where arbitration_id = :'arb'::uuid) = 0, 'A6 clean record: nothing from the mediation is carried over');
select t.as_user(:'dmed'::uuid);
select t.ok((select count(*) from public.arbitrations) = 0 and public.arb_gate_info(:'arb'::uuid) is null, 'A7 the mediator has no access to the arbitration file');

-- ====================================================== B. the rules gate (read + act)
select t.as_user(:'dcla'::uuid);
select t.ok((select count(*) from public.arbitrations) = 0, 'B1 before accepting the arbitration rules the file is hidden even from the claimant');
select t.ok(not (public.arb_gate_info(:'arb'::uuid)->>'accepted')::boolean and (public.arb_gate_info(:'arb'::uuid)->>'role') = 'claimant', 'B2 the gate tells him what to do');
select t.ok(exists (select 1 from jsonb_array_elements(public.my_actions()) e where e->>'case_id' = :'arb' and e->>'code' = 'accept_arb_rules' and e->>'case_kind' = 'arbitration'), 'B3 and the dashboard lists it');
select t.fails(format('select public.accept_arb_rules(gen_random_uuid(), %L, ''1.2.3.4'', ''x'')', :'arb'), 'B4 users cannot write their own consent (server-only)', 'permission denied');
select t.accept_rules(:'arb'::uuid);
select t.ok((select count(*) from public.arbitrations) = 1, 'B5 after accepting, the claimant reads his file');
select t.as_user(:'dres'::uuid);
select t.fails(format('select public.respond_escalation(%L, true)', :'arb'), 'B6 the respondent cannot agree before reading the rules', 'اقرأ قواعد');
select t.accept_rules(:'arb'::uuid);
select t.as_user(:'dcla'::uuid);
select t.fails(format('select public.respond_escalation(%L, true)', :'arb'), 'B7 only the respondent answers an escalation request', 'غير مصرح');
select t.as_user(:'dres'::uuid);
select public.respond_escalation(:'arb'::uuid, true);
select t.ok((select status from public.arbitrations where id = :'arb'::uuid) = 'agreement', 'B8 the respondent agrees to escalate');

-- ====================================================== C. the arbitration agreement: signed OUTSIDE, scan confirmed by both
select t.as_user(:'dcla'::uuid);
select t.put_object(:'arb' || '/agreement.pdf');
select t.put_object(:'arb' || '/other.pdf');
select t.fails(format('select t.register_arb_document(%L, ''x.pdf'', %L, ''application/pdf'', 10, %L, ''award_signed'')', :'arb', :'arb' || '/other.pdf', repeat('b', 64)), 'C1 a claimant cannot upload a signed award', 'الحكم الموقَّع');
select t.register_arb_document(:'arb'::uuid, 'اتفاق التحكيم الموقّع.pdf', :'arb' || '/agreement.pdf', 'application/pdf', 4096, repeat('c', 64), 'arbitration_agreement') as agr \gset
select t.register_arb_document(:'arb'::uuid, 'ملف آخر.pdf', :'arb' || '/other.pdf', 'application/pdf', 100, repeat('d', 64), 'other') as oth \gset
select t.fails(format('select t.confirm_arb_agreement(%L, %L, ''1.1.1.1'', ''ua'')', :'arb', :'oth'), 'C2 only a file uploaded as the arbitration agreement can be confirmed', 'اختر ملف');
select t.confirm_arb_agreement(:'arb'::uuid, :'agr'::uuid, '1.1.1.1', 'ua');
select t.ok((select status from public.arbitrations where id = :'arb'::uuid) = 'agreement', 'C3 one confirmation does not move the file on');
select t.fails(format('select t.confirm_arb_agreement(%L, %L, ''1.1.1.1'', ''ua'')', :'arb', :'agr'), 'C4 a party confirms once', 'أكّدت من قبل');
select t.as_user(:'dstr'::uuid);
select t.fails(format('select t.confirm_arb_agreement(%L, %L, ''1.1.1.1'', ''ua'')', :'arb', :'agr'), 'C5 an outsider cannot confirm', 'غير مصرح');
select t.as_user(:'dres'::uuid);
select t.ok((select count(*) from public.arb_agreement_confirmations where user_id <> :'dres'::uuid) = 0, 'C6 a party cannot read the other''s confirmation row (IP, browser)');
select t.ok(jsonb_array_length(public.arb_confirmations(:'arb'::uuid)) = 1 and position('ip' in public.arb_confirmations(:'arb'::uuid)::text) = 0, 'C7 the whitelisted view shows who confirmed, without IP');
select t.confirm_arb_agreement(:'arb'::uuid, :'agr'::uuid, '2.2.2.2', 'ua');
select t.ok((select status from public.arbitrations where id = :'arb'::uuid) = 'selection', 'C8 both parties confirm the same file: the file moves to arbitrator selection');
select t.as_user(:'dcla'::uuid);
select t.fails(format('select t.register_arb_document(%L, ''y.pdf'', %L, ''application/pdf'', 10, %L, ''arbitration_agreement'')', :'arb', :'arb' || '/other.pdf', repeat('e', 64)), 'C9 a confirmed agreement is never replaced', 'مرحلة الاتفاق');

-- ====================================================== D. choosing the arbitrator
select t.as_user(:'dres'::uuid);
select t.fails(format('select public.propose_arbitrator(%L, %L)', :'arb', :'darbu'), 'D1 an unverified arbitrator cannot be proposed', 'غير معتمد');
select t.fails(format('select public.propose_arbitrator(%L, %L)', :'arb', :'dmed'), 'D2 a mediator-role account is not an arbitrator', 'غير معتمد');
select t.fails(format('select public.propose_arbitrator(%L, %L)', :'arb', :'dcla'), 'D3 a party cannot be the arbitrator', 'غير معتمد');
select public.propose_arbitrator(:'arb'::uuid, :'darb'::uuid);
select t.fails(format('select public.propose_arbitrator(%L, %L)', :'arb', :'darb2'), 'D4 one proposal at a time', 'قيد الانتظار');
select t.fails(format('select public.party_respond_arbitrator(%L, true)', (select id from public.arb_assignments where arbitration_id = :'arb'::uuid and status = 'proposed')), 'D5 the proposer cannot approve his own proposal', 'الطرف الآخر');
select t.as_user(:'darb'::uuid);
select t.ok(public.arb_gate_info(:'arb'::uuid) is null, 'D6 a proposed arbitrator sees nothing until BOTH parties approve him');
select t.as_user(:'dcla'::uuid);
select public.party_respond_arbitrator((select id from public.arb_assignments where arbitration_id = :'arb'::uuid and status = 'proposed'), true);
select t.as_super();
select id as asg from public.arb_assignments where arbitration_id = :'arb'::uuid and status = 'approved' \gset
select t.as_user(:'darb'::uuid);
select t.ok((select count(*) from public.arbitrations) = 0 and (public.arb_gate_info(:'arb'::uuid)->>'role') = 'arbitrator_candidate', 'D7 after approval he sees only the gate (rules), not the file');
select t.fails(format('select public.arbitrator_respond(%L, true, repeat(''أقر بالاستقلال والحياد. '', 4))', :'asg'), 'D8 he cannot take the case before accepting the arbitration rules', 'اقرأ قواعد');
select t.accept_rules(:'arb'::uuid);
select t.as_user(:'darb'::uuid, 'aal1');
select t.fails(format('select public.arbitrator_respond(%L, true, repeat(''أقر بالاستقلال والحياد. '', 4))', :'asg'), 'D9 an arbitrator without the second step (MFA) cannot act', 'خطوتين');
select t.as_user(:'darb'::uuid);
select t.fails(format('select public.arbitrator_respond(%L, true, ''مستقل'')', :'asg'), 'D10 a written declaration of independence is required', 'إقرار الاستقلال');
select public.arbitrator_respond(:'asg'::uuid, true, 'أقرّ بأنني لم أعمل مع أي من الطرفين ولا تربطني بهما أو بالنزاع علاقة تمس استقلالي أو حيادي.');
select t.ok((select status = 'active' and arbitrator_id = :'darb'::uuid from public.arbitrations where id = :'arb'::uuid), 'D11 the arbitrator accepts: proceedings begin');
select t.as_user(:'dres'::uuid);
select t.ok(jsonb_array_length(public.arb_disclosures(:'arb'::uuid)) = 1 and position('استقلالي' in public.arb_disclosures(:'arb'::uuid)::text) > 0, 'D12 the parties can read his declaration');

-- ====================================================== E. procedure
select t.as_user(:'dcla'::uuid);
select t.fails(format('select public.set_arb_step(%L, ''statement_of_claim'', ''claimant'', now() + interval ''2 days'')', :'arb'), 'E1 a party cannot set the timetable', 'المحكّم وحده');
select t.as_user(:'darb'::uuid);
select t.ok(exists (select 1 from jsonb_array_elements(public.my_actions()) e where e->>'case_id' = :'arb' and e->>'code' = 'set_timetable'), 'E2 the arbitrator is told to set the timetable');
select t.fails(format('select public.set_arb_step(%L, ''statement_of_claim'', ''claimant'', now() - interval ''1 day'')', :'arb'), 'E3 a deadline in the past is refused', 'المستقبل');
select public.set_arb_step(:'arb'::uuid, 'statement_of_claim', 'claimant', now() + interval '2 days', 'مذكرة الدعوى') as s1 \gset
select public.set_arb_step(:'arb'::uuid, 'statement_of_defence', 'respondent', now() + interval '4 days') as s2 \gset
select public.set_arb_step(:'arb'::uuid, 'reply', 'claimant', now() + interval '6 days') as s3 \gset
select t.as_user(:'dres'::uuid);
select t.fails(format('select public.submit_arb_statement(%L, repeat(''نص المذكرة '', 5))', :'s1'), 'E4 only the party named in the step may submit', 'ليست من حقك');
select t.as_user(:'dcla'::uuid);
select t.fails(format('select public.submit_arb_statement(%L, ''قصير'')', :'s1'), 'E5 a statement needs real content', 'قصير');
select public.submit_arb_statement(:'s1'::uuid, 'مذكرة-سرية-123: يطالب المدّعي بثمن البضاعة الموردة وفق العقد المرفق.');
select t.fails(format('select public.submit_arb_statement(%L, repeat(''نص المذكرة '', 5))', :'s1'), 'E6 one statement per step', 'من قبل');
select t.ok((select late from public.arb_submissions where step_id = :'s1'::uuid) = false, 'E7 on time: not flagged');
select t.as_user(:'dres'::uuid);
select t.put_object(:'arb' || '/exhibit-r1.pdf');
select t.register_arb_document(:'arb'::uuid, 'مستند المدّعى عليه.pdf', :'arb' || '/exhibit-r1.pdf', 'application/pdf', 2048, repeat('f', 64), 'exhibit') as rdoc \gset
select t.as_super();
update public.arb_steps set due_at = now() - interval '1 day' where id = :'s2'::uuid;
select t.as_user(:'dres'::uuid);
select public.submit_arb_statement(:'s2'::uuid, 'ردّ المدّعى عليه على الدعوى مع مستند مرفق.', array[:'rdoc'::uuid]);
select t.ok((select late and document_ids = array[:'rdoc'::uuid] from public.arb_submissions where step_id = :'s2'::uuid), 'E8 a late statement is accepted but flagged, with its attachment');
select t.as_user(:'dcla'::uuid);
select t.fails(format('select public.submit_arb_statement(%L, repeat(''نص المذكرة '', 5), array[%L]::uuid[])', :'s3', :'rdoc'), 'E9 one cannot attach the other party''s file', 'مرفقات غير صالحة');
select t.ok((select count(*) from public.arb_submissions) = 2, 'E10 submissions are visible to the parties');
select t.as_user(:'dstr'::uuid);
select t.ok((select count(*) from public.arb_submissions) = 0 and (select count(*) from public.arb_steps) = 0, 'E11 and to nobody else');
select t.as_user(:'darb'::uuid);
select t.fails(format('select public.extend_arb_step(%L, now() + interval ''9 days'')', :'s1'), 'E12 a step already answered cannot be extended', 'قُدِّمت');
select public.extend_arb_step(:'s3'::uuid, now() + interval '9 days');
select t.as_user(:'dcla'::uuid);
select t.fails(format('select public.schedule_arb_hearing(%L, now() + interval ''1 day'', 120)', :'arb'), 'E13 a party cannot schedule a hearing', 'المحكّم وحده');
select t.as_user(:'darb'::uuid);
select public.schedule_arb_hearing(:'arb'::uuid, now() + interval '1 day', 120) as h1 \gset
select t.as_user(:'dres'::uuid);
select t.ok((select count(*) from public.arb_hearings where status = 'scheduled') = 1, 'E14 the parties see the hearing');
select t.ok(not exists (select 1 from jsonb_array_elements(public.my_actions()) e where e->>'case_id' = :'arb' and e->>'code' = 'submit_statement'), 'E15 the respondent, who has answered his step, is not told to submit again');
select t.as_user(:'dcla'::uuid);
select t.ok(exists (select 1 from jsonb_array_elements(public.my_actions()) e where e->>'case_id' = :'arb' and e->>'code' = 'submit_statement'), 'E16 the claimant is told that a reply is due');

-- ====================================================== F. deliberation and the award
select t.as_user(:'darb'::uuid);
select t.fails(format('select public.save_award_draft(%L, repeat(''x'', 200))', :'arb'), 'F1 no draft before the proceedings are closed', 'بعد إقفال');
select t.as_user(:'dcla'::uuid);
select t.fails(format('select public.close_proceedings(%L)', :'arb'), 'F2 a party cannot close the proceedings', 'غير مصرح');
select t.as_user(:'darb'::uuid);
select public.close_proceedings(:'arb'::uuid);
select t.ok((select status from public.arbitrations where id = :'arb'::uuid) = 'deliberation' and (select status from public.arb_hearings where id = :'h1'::uuid) = 'cancelled', 'F3 closing the proceedings cancels hearings still ahead');
select t.as_user(:'dcla'::uuid);
select t.fails(format('select public.submit_arb_statement(%L, repeat(''نص المذكرة '', 5))', :'s3'), 'F4 no more statements after the proceedings are closed', 'انتهت مرحلة');
select t.as_user(:'darb'::uuid);
select t.fails(format('select public.save_award_draft(%L, ''قصير'')', :'arb'), 'F5 a draft needs real content', 'قصير');
select public.save_award_draft(:'arb'::uuid, 'نص-الحكم-السري-456: حكمت الهيئة [يكتب المحكّم المنطوق هنا] وألزمت المدّعى عليه بالمبلغ المطالب به، وذلك للأسباب الواردة في هذا الحكم المسبَّب.');
select t.as_user(:'dcla'::uuid);
select t.ok((select count(*) from public.arb_awards) = 0, 'F6 the parties cannot read the draft award');
select t.as_user(:'dadm'::uuid);
select t.ok((select count(*) from public.arb_awards) = 0, 'F7 nor can the admin');
select t.as_user(:'darb'::uuid);
select t.ok((select count(*) from public.arb_awards where status = 'draft') = 1, 'F8 the arbitrator can');
select t.as_super();
select t.ok((select count(*) from public.audit_logs where new_state::text like '%نص-الحكم-السري-456%' or previous_state::text like '%نص-الحكم-السري-456%'
                                                       or new_state::text like '%مذكرة-سرية-123%') = 0, 'F9 neither the draft award nor any statement text ever reaches the audit log');
select t.ok((select count(*) from public.audit_logs where event_type = 'arb_awards.INSERT' and new_state ? 'draft_hash') = 1, 'F10 but the hash of the draft does');
select t.as_user(:'darb'::uuid);
select t.put_object(:'arb' || '/award-signed.pdf');
select t.fails(format('select public.issue_award(%L, gen_random_uuid(), current_date)', :'arb'), 'F11 a draft still holding [..] placeholders cannot be issued', 'أقواس');
select public.save_award_draft(:'arb'::uuid, 'نص-الحكم-السري-456: حكمت الهيئة بإلزام المدّعى عليه بأداء مبلغ مئة وخمسين ألف جنيه للمدّعي، وذلك للأسباب الواردة في هذا الحكم المسبَّب.');
select t.ok((select version from public.arb_awards where arbitration_id = :'arb'::uuid) = 2, 'F12 the corrected draft is version 2');
select t.fails(format('select public.issue_award(%L, gen_random_uuid(), current_date)', :'arb'), 'F13 an award cannot be issued without the signed scan', 'ارفع مسح');
select t.as_user(:'dcla'::uuid);
select t.fails(format('select t.register_arb_document(%L, ''a.pdf'', %L, ''application/pdf'', 10, %L, ''award_signed'')', :'arb', :'arb' || '/award-signed.pdf', repeat('1', 64)), 'F14 only the arbitrator uploads the signed award', 'الحكم الموقَّع');
select t.as_user(:'darb'::uuid);
select t.register_arb_document(:'arb'::uuid, 'الحكم الموقّع.pdf', :'arb' || '/award-signed.pdf', 'application/pdf', 90000, repeat('2', 64), 'award_signed') as adoc \gset
select t.fails(format('select public.issue_award(%L, %L, current_date + 3)', :'arb', :'adoc'), 'F15 an award cannot be dated in the future', 'تاريخ الحكم');
select public.issue_award(:'arb'::uuid, :'adoc'::uuid, current_date);
select t.ok((select status = 'closed' and outcome = 'award_issued' and closed_by = :'darb'::uuid from public.arbitrations where id = :'arb'::uuid), 'F16 issuing the award closes the file with outcome "award issued"');
select t.as_user(:'dcla'::uuid);
select t.ok((select count(*) from public.arb_awards where status = 'issued') = 1, 'F17 now the parties can read the issued award record');
select t.as_user(:'dadm'::uuid);
select t.ok((select count(*) from public.arb_awards where status = 'issued') = 1, 'F18 and the admin');
select t.as_user(:'darb'::uuid);
select t.fails(format('select public.set_arb_step(%L, ''other'', ''claimant'', now() + interval ''2 days'')', :'arb'), 'F19 a closed file is read-only', 'المرحلة');
select t.fails(format('select public.terminate_arbitration(%L)', :'arb'), 'F20 and cannot be terminated again', 'المرحلة');
select t.as_user(:'dres'::uuid);
select t.put_object(:'arb' || '/late.pdf');
select t.fails(format('select t.register_arb_document(%L, ''l.pdf'', %L, ''application/pdf'', 10, %L, ''other'')', :'arb', :'arb' || '/late.pdf', repeat('3', 64)), 'F21 no documents after closure', 'منتهٍ');
select t.ok(jsonb_array_length(public.arb_timeline(:'arb'::uuid)) > 15
        and position('1.1.1.1' in public.arb_timeline(:'arb'::uuid)::text) = 0
        and position('نص-الحكم' in public.arb_timeline(:'arb'::uuid)::text) = 0
        and position('draft_text' in public.arb_timeline(:'arb'::uuid)::text) = 0, 'F22 the parties'' timeline is whitelisted: no IP, no award text');

-- ====================================================== G. other ways a file can go
select t.make_active(:'dcla'::uuid, :'dres'::uuid, :'dmed'::uuid, 'dres@t.com') as src3 \gset
select t.as_user(:'dcla'::uuid);
select public.propose_escalation(:'src3'::uuid, 'طلب تحكيم سيُرفض', repeat('ملخص الطلب ', 6), 90000) as arb3 \gset
select t.accept_rules(:'arb3'::uuid);
select t.as_user(:'dres'::uuid);
select t.accept_rules(:'arb3'::uuid);
select public.respond_escalation(:'arb3'::uuid, false, 'لا أرغب في التحكيم');
select t.as_super();
select t.ok((select status = 'cancelled' and outcome = 'declined' and outcome_reason = 'لا أرغب في التحكيم' from public.arbitrations where id = :'arb3'::uuid), 'G1 the respondent declines: the file is cancelled with the outcome and reason');
select t.as_user(:'dres'::uuid);
select public.propose_escalation(:'src3'::uuid, 'طلب تحكيم جديد من الطرف الآخر', repeat('ملخص الطلب ', 6), 90000) is not null as reproposed \gset
select t.ok(:'reproposed'::boolean, 'G2 after a declined request a new one can be proposed (here by the other party)');

select t.make_arb(:'dcla'::uuid, :'dres'::uuid, :'dmed2'::uuid, null, 'dres@t.com', 'selection') as arb5 \gset
select t.as_user(:'dcla'::uuid);
select t.as_super();
update public.profiles set role = 'arbitrator', kyc_status = 'verified' where id = :'dmed2'::uuid;
select t.as_user(:'dcla'::uuid);
select t.fails(format('select public.propose_arbitrator(%L, %L)', :'arb5', :'dmed2'), 'G3 whoever mediated the source dispute can never be proposed as arbitrator (no override)', 'وسيطًا في الوساطة السابقة');
select public.withdraw_arbitration(:'arb5'::uuid, 'اتفقنا ودّيًا');
select t.as_super();
select t.ok((select status = 'cancelled' and outcome = 'withdrawn' from public.arbitrations where id = :'arb5'::uuid), 'G4 the claimant withdraws before an arbitrator is seated');

select t.make_arb(:'dcla'::uuid, :'dres'::uuid, :'dmed'::uuid, :'darb'::uuid, 'dres@t.com') as arb6 \gset
select t.as_user(:'dcla'::uuid);
select t.fails(format('select public.withdraw_arbitration(%L)', :'arb6'), 'G5 once an arbitrator is seated the parties cannot simply withdraw', 'بعد تعيين');
select t.as_user(:'darb'::uuid);
select public.close_proceedings(:'arb6'::uuid);
select public.save_award_draft(:'arb6'::uuid, repeat('مسودة حكم المحكّم الأول ستُحذف عند انسحابه ولا تنتقل إلى من يخلفه. ', 3));
select public.arbitrator_withdraw(:'arb6'::uuid, 'ظرف طارئ');
select t.as_super();
select t.ok((select status = 'selection' and arbitrator_id is null from public.arbitrations where id = :'arb6'::uuid)
        and (select status from public.arb_assignments where arbitration_id = :'arb6'::uuid and arbitrator_id = :'darb'::uuid) = 'ended'
        and (select count(*) from public.arb_awards where arbitration_id = :'arb6'::uuid) = 0, 'G6 an arbitrator can step down: the file returns to selection and his draft is not handed on');
select t.as_user(:'darb'::uuid);
select t.ok((select count(*) from public.arbitrations where id = :'arb6'::uuid) = 0, 'G7 and he loses all access');
select t.as_user(:'dcla'::uuid);
select public.propose_arbitrator(:'arb6'::uuid, :'darb2'::uuid);
select t.as_user(:'dres'::uuid);
select public.party_respond_arbitrator((select id from public.arb_assignments where arbitration_id = :'arb6'::uuid and status = 'proposed'), true);
select t.as_user(:'darb2'::uuid);
select t.accept_rules(:'arb6'::uuid);
select public.arbitrator_respond((select id from public.arb_assignments where arbitration_id = :'arb6'::uuid and status = 'approved'), true, 'أقرّ بأنني لا أعرف الطرفين ولا تربطني بالنزاع أي صلة تمس استقلالي أو حيادي.');
select t.ok((select status = 'active' and arbitrator_id = :'darb2'::uuid from public.arbitrations where id = :'arb6'::uuid), 'G8 a replacement is chosen and seated');
select t.as_user(:'darb2'::uuid, 'aal1');
select t.fails(format('select public.set_arb_step(%L, ''other'', ''claimant'', now() + interval ''2 days'')', :'arb6'), 'G9 an arbitrator without the second step cannot act', 'خطوتين');
select t.ok((select count(*) from public.arbitrations) = 0, 'G10 and reads nothing');
select t.as_user(:'dcla'::uuid);
select t.fails(format('select public.terminate_arbitration(%L)', :'arb6'), 'G11 a party cannot terminate the proceedings', 'غير مصرح');
select t.as_user(:'darb2'::uuid);
select public.terminate_arbitration(:'arb6'::uuid, 'تنازل المدّعي عن الدعوى');
select t.as_super();
select t.ok((select status = 'closed' and outcome = 'terminated' from public.arbitrations where id = :'arb6'::uuid), 'G12 the arbitrator terminates the proceedings with a recorded outcome');

-- ====================================================== H. trust boundary and exposure
select t.as_user(:'dcla'::uuid);
select t.fails($$insert into public.arbitrations (title, summary, dispute_value_egp, claimant_id, respondent_id, created_by, rules_document_id) select 'x','y',1,id,id,id,(select id from public.legal_documents limit 1) from public.profiles where email='dcla@t.com'$$, 'H1 users cannot create arbitrations directly', 'permission denied');
select t.fails($$update public.arbitrations set status = 'closed'$$, 'H2 nor change them', 'permission denied');
select t.fails($$insert into public.arb_documents (arbitration_id, uploaded_by, file_name, file_path, file_size, mime_type, sha256_hash, doc_type) values (gen_random_uuid(), gen_random_uuid(), 'x', 'y', 1, 'a/b', 'h', 'other')$$, 'H3 nor insert evidence rows', 'permission denied');
select t.fails($$select public.register_arb_document_srv(gen_random_uuid(), 'aal2', gen_random_uuid(), 'p', 'n', 'application/pdf', 1, repeat('a', 64), 'other')$$, 'H4 the server-only registration is closed to users', 'permission denied');
select t.fails($$select public.confirm_arb_agreement_srv(gen_random_uuid(), 'aal2', gen_random_uuid(), gen_random_uuid(), '1.1.1.1', 'x')$$, 'H5 so is the server-only confirmation', 'permission denied');
select t.ok((select count(*) from public.audit_logs) = 0, 'H6 a party reads no raw audit rows');
select t.as_anon();
select t.fails($$select public.propose_escalation(gen_random_uuid(), 'عنوان الطلب', repeat('ملخص ', 10), 100000)$$, 'H7 anonymous users cannot call arbitration functions', 'permission denied');
select t.as_user(:'dmed'::uuid);
select t.ok(public.linked_arbitrations(:'src'::uuid) = '[]'::jsonb, 'H8 the mediator is not told about the arbitration');
select t.as_user(:'dcla'::uuid);
select t.ok(jsonb_array_length(public.linked_arbitrations(:'src'::uuid)) = 1 and position('title' in public.linked_arbitrations(:'src'::uuid)::text) = 0, 'H9 a party sees the link (number and status only)');
select t.fails(format('select public.arb_metrics()'), 'H10 arbitration metrics are admin-only', 'غير مصرح');
select t.as_user(:'dadm'::uuid, 'aal1');
select t.fails(format('select public.arb_metrics()'), 'H11 and need the second step', 'غير مصرح');
select t.as_user(:'dadm'::uuid);
select t.ok((public.arb_metrics()->'outcomes'->>'award_issued')::int >= 1 and (public.arb_metrics()->'outcomes'->>'terminated')::int >= 1
        and (public.arb_metrics()->'outcomes'->>'withdrawn')::int >= 1 and (public.arb_metrics()->'outcomes'->>'declined')::int >= 1
        and (public.arb_metrics()->>'escalated_from_mediation')::int >= 5 and (public.arb_metrics()->>'late_statements')::int >= 1, 'H12 metrics separate award, termination, withdrawal and refusal, and count escalations and late statements');
select t.ok((public.verify_audit_chain()->>'ok')::boolean, 'H13 the audit chain still verifies after all of it');
