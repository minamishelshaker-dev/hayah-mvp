-- Failure paths. Independent of tests.sql: uses its own accounts. Needs helpers.sql loaded first.
\set ON_ERROR_STOP 1
\pset tuples_only on
\pset format unaligned

\set ladm b0000000-0000-0000-0000-000000000001
\set lm1  b0000000-0000-0000-0000-000000000002
\set lm2  b0000000-0000-0000-0000-000000000003
\set lcla b0000000-0000-0000-0000-000000000004
\set lres b0000000-0000-0000-0000-000000000005
\set lstr b0000000-0000-0000-0000-000000000006
\set lres2 b0000000-0000-0000-0000-000000000007

-- Builds a dispute that is already ACTIVE: agreement accepted by all three, mediator in place.
create or replace function t.make_active(c uuid, r uuid, m uuid, r_email text) returns uuid language plpgsql as $$
declare j jsonb; v_id uuid; v_tok text; v_doc uuid;
begin
  perform t.as_user(c);
  j := public.create_dispute('نزاع اختبار', 'وصف طويل للنزاع يتجاوز الخمسين حرفا حتى يكون صالحا للاختبار في قاعدة البيانات', 'commercial', 100000, r_email, '');
  v_id := (j->>'id')::uuid; v_tok := j->>'token';
  v_doc := (public.dispute_gate_info(v_id)->'doc'->>'id')::uuid;
  perform t.accept_legal(v_doc, v_id, '1.1.1.1', 'ua');
  perform t.as_user(r);
  perform public.accept_invitation(v_tok);
  perform t.accept_legal(v_doc, v_id, '2.2.2.2', 'ua');
  perform t.as_user(c);
  perform public.propose_mediator(v_id, m);
  perform t.as_user(r);
  perform public.party_respond_mediator((select id from public.mediator_assignments where dispute_id = v_id and status = 'proposed'), true);
  perform t.as_user(m);
  perform t.accept_legal(v_doc, v_id, '3.3.3.3', 'ua');
  perform public.mediator_respond((select id from public.mediator_assignments where dispute_id = v_id and status = 'approved'), true);
  return v_id;
end $$;

select t.as_super();
insert into auth.users (id, email, raw_user_meta_data) values
 (:'ladm'::uuid, 'ladmin@t.com', '{"full_name":"Admin"}'),
 (:'lm1'::uuid,  'lm1@t.com',    '{"full_name":"Mediator A"}'),
 (:'lm2'::uuid,  'lm2@t.com',    '{"full_name":"Mediator B"}'),
 (:'lcla'::uuid, 'lcla@t.com',   '{"full_name":"Claimant"}'),
 (:'lres'::uuid, 'lres@t.com',   '{"full_name":"Respondent"}'),
 (:'lstr'::uuid, 'lstr@t.com',   '{"full_name":"Stranger"}'),
 (:'lres2'::uuid,'lres2@t.com',  '{"full_name":"Respondent Two"}');
update public.profiles set role = 'admin' where id = :'ladm'::uuid;
update public.profiles set role = 'mediator', kyc_status = 'verified' where id in (:'lm1'::uuid, :'lm2'::uuid);

-- ======================================================== L1. respondent declines
select t.as_user(:'lcla'::uuid);
select public.create_dispute('نزاع سيُرفض', 'وصف طويل للنزاع يتجاوز الخمسين حرفا حتى يكون صالحا للاختبار في قاعدة البيانات', 'commercial', 100000, 'lres@t.com', '')::text as r1 \gset
select (:'r1'::jsonb)->>'id' as d1 \gset
select (:'r1'::jsonb)->>'token' as k1 \gset
select t.as_user(:'lstr'::uuid);
select t.fails(format('select public.decline_invitation(%L)', :'k1'), 'L1 a different account cannot decline the invitation', 'بريد إلكتروني آخر');
select t.as_user(:'lres'::uuid);
select public.decline_invitation(:'k1', 'لا أرغب في الوساطة');
select t.as_super();
select t.ok((select status = 'cancelled' and outcome = 'declined' and outcome_reason = 'لا أرغب في الوساطة' and closed_at is not null from public.disputes where id = :'d1'::uuid), 'L2 declining cancels the file with outcome "declined" and the reason');
select t.ok((select status from public.invitations where dispute_id = :'d1'::uuid) = 'declined', 'L3 the invitation is marked declined');
select t.as_user(:'lres'::uuid);
select t.fails(format('select public.accept_invitation(%L)', :'k1'), 'L4 a declined invitation cannot be accepted afterwards', 'استخدام');
select t.as_user(:'lcla'::uuid);
select t.fails(format('select public.withdraw_dispute(%L)', :'d1'), 'L5 an ended file cannot be withdrawn again', 'لا يمكن سحب');

-- ================================================== L2. claimant withdraws (NULL respondent)
select public.create_dispute('نزاع سيُسحب', 'وصف طويل للنزاع يتجاوز الخمسين حرفا حتى يكون صالحا للاختبار في قاعدة البيانات', 'commercial', 100000, 'lres@t.com', '')::text as r2 \gset
select (:'r2'::jsonb)->>'id' as d2 \gset
select t.as_user(:'lstr'::uuid);
select t.fails(format('select public.withdraw_dispute(%L)', :'d2'), 'L6 an outsider cannot withdraw a file whose respondent is still empty (NULL-safe check)', 'غير مصرح');
select t.as_user(:'lcla'::uuid);
select public.withdraw_dispute(:'d2'::uuid, 'سوّينا الأمر ودّيًا خارج المنصة');
select t.as_super();
select t.ok((select status = 'cancelled' and outcome = 'withdrawn' from public.disputes where id = :'d2'::uuid), 'L7 withdrawing records outcome "withdrawn"');
select t.ok((select status from public.invitations where dispute_id = :'d2'::uuid) = 'cancelled', 'L8 the pending invitation is cancelled');
select t.as_user(:'lcla'::uuid);
select t.ok(jsonb_array_length(public.my_pending_agreements()) = 0 or not exists (select 1 from jsonb_array_elements(public.my_pending_agreements()) e where e->>'id' = :'d2'), 'L9 an ended file no longer appears as waiting for agreement');

-- ========================================================= L3. renew the invitation
select public.create_dispute('نزاع بعنوان بريد خاطئ', 'وصف طويل للنزاع يتجاوز الخمسين حرفا حتى يكون صالحا للاختبار في قاعدة البيانات', 'commercial', 100000, 'wrong@t.com', '')::text as r3 \gset
select (:'r3'::jsonb)->>'id' as d3 \gset
select (:'r3'::jsonb)->>'token' as k3 \gset
select t.as_user(:'lstr'::uuid);
select t.fails(format('select public.resend_invitation(%L, ''x@t.com'')', :'d3'), 'L10 only the claimant can renew an invitation', 'غير مصرح');
select t.as_user(:'lcla'::uuid);
select t.fails(format('select public.resend_invitation(%L, ''lcla@t.com'')', :'d3'), 'L11 the claimant cannot invite himself', 'نفسك');
select public.resend_invitation(:'d3'::uuid, 'LRES2@t.com')::text as rs \gset
select (:'rs'::jsonb)->>'token' as k3b \gset
select t.as_super();
select t.ok((select count(*) from public.invitations where dispute_id = :'d3'::uuid and status = 'pending') = 1
        and (select status from public.invitations where token = :'k3') = 'expired', 'L12 the old link is expired and exactly one fresh link is pending');
select t.as_user(:'lres2'::uuid);
select t.fails(format('select public.accept_invitation(%L)', :'k3'), 'L13 the old link no longer works', 'استخدام');
select public.accept_invitation(:'k3b') is not null;
select t.as_user(:'lcla'::uuid);
select t.fails(format('select public.resend_invitation(%L)', :'d3'), 'L14 an accepted invitation cannot be renewed', 'بعد قبولها');

-- ===================================================== L4. mediator steps down, replaced
select t.make_active(:'lcla'::uuid, :'lres'::uuid, :'lm1'::uuid, 'lres@t.com') as d4 \gset
select t.as_user(:'lm1'::uuid);
select public.schedule_session(:'d4'::uuid, now() + interval '2 days', 60);
select t.as_user(:'lcla'::uuid);
select t.fails(format('select public.mediator_withdraw(%L)', :'d4'), 'L15 a party cannot remove the mediator through the mediator function', 'غير مصرح');
select t.as_user(:'lm1'::uuid);
select public.mediator_withdraw(:'d4'::uuid, 'تعارض مصالح طرأ');
select t.ok((select count(*) from public.disputes) = 0, 'L16 the old mediator loses all access to the file');
select t.ok(public.dispute_gate_info(:'d4'::uuid) is null, 'L17 and is no longer a member');
select t.as_user(:'lcla'::uuid);
select t.ok((select status = 'mediator_selection' and mediator_id is null from public.disputes where id = :'d4'::uuid), 'L18 the file returns to mediator selection');
select t.ok((select status from public.sessions where dispute_id = :'d4'::uuid) = 'cancelled', 'L19 future sessions of the departed mediator are cancelled');
select t.ok((select status from public.mediator_assignments where dispute_id = :'d4'::uuid and mediator_id = :'lm1'::uuid) = 'ended', 'L20 the assignment is marked ended');
select public.propose_mediator(:'d4'::uuid, :'lm2'::uuid);
select t.as_user(:'lres'::uuid);
select public.party_respond_mediator((select id from public.mediator_assignments where dispute_id = :'d4'::uuid and status = 'proposed'), true);
select t.as_user(:'lm2'::uuid);
select t.accept_legal((public.dispute_gate_info(:'d4'::uuid)->'doc'->>'id')::uuid, :'d4'::uuid, '4.4.4.4', 'ua');
select public.mediator_respond((select id from public.mediator_assignments where dispute_id = :'d4'::uuid and status = 'approved'), true);
select t.ok((select status = 'active' and mediator_id = :'lm2'::uuid from public.disputes where id = :'d4'::uuid), 'L21 the replacement mediator takes over');

-- ===================================================== L5. end without a settlement
select t.as_user(:'lcla'::uuid);
select t.fails(format('select public.close_dispute(%L, ''settled'')', :'d4'), 'L22 cannot close as "settled" before signatures complete', 'قبل اكتمال التوقيع');
select t.fails(format('select public.close_dispute(%L, ''whatever'')', :'d4'), 'L23 an unknown outcome is refused', 'نتيجة غير صالحة');
select t.as_user(:'lstr'::uuid);
select t.fails(format('select public.close_dispute(%L, ''no_settlement'')', :'d4'), 'L24 an outsider cannot close a file', 'غير مصرح');
select t.as_user(:'lres'::uuid);
select public.close_dispute(:'d4'::uuid, 'no_settlement', 'لم نتفق على المبلغ');
select t.ok((select status = 'closed' and outcome = 'no_settlement' and closed_by = :'lres'::uuid from public.disputes where id = :'d4'::uuid), 'L25 a party ends the mediation without settlement; the outcome and who ended it are recorded');
select t.fails(format('select public.close_dispute(%L, ''no_settlement'')', :'d4'), 'L26 a closed file cannot be closed again', 'في هذه المرحلة');
select t.as_user(:'lm2'::uuid);
select t.fails(format('select public.schedule_session(%L, now() + interval ''1 day'', 60)', :'d4'), 'L27 no sessions can be scheduled in a closed file', 'في هذه المرحلة');
select t.put_object(:'d4' || '/z');
select t.fails(format('select t.register_document(%L, ''a.pdf'', %L, ''application/pdf'', 1, %L)', :'d4', :'d4' || '/z', repeat('c', 64)),
  'L28 no documents can be added to a closed file', 'مغلق');

-- ========================================================= L6. settled and closed
select t.make_active(:'lcla'::uuid, :'lres'::uuid, :'lm1'::uuid, 'lres@t.com') as d5 \gset
select public.save_settlement(:'d5'::uuid, 'اتفاق تسوية: يلتزم الطرف الثاني بسداد مبلغ مئة ألف جنيه خلال ثلاثين يوما من تاريخ هذا الاتفاق.');
select t.as_user(:'lm1'::uuid);
select public.save_settlement(:'d5'::uuid, 'اتفاق تسوية: يلتزم الطرف الثاني بسداد مبلغ مئة ألف جنيه خلال ثلاثين يوما من تاريخ هذا الاتفاق.');
select public.submit_settlement(:'d5'::uuid);
select t.fails(format('select public.mediator_withdraw(%L)', :'d5'), 'L29 the mediator cannot step down once signing is open', 'فُتح الاتفاق');
select t.as_user(:'lcla'::uuid);
select t.sign_settlement(:'d5'::uuid, '1.1.1.1', 'ua');
select t.as_user(:'lres'::uuid);
select t.sign_settlement(:'d5'::uuid, '2.2.2.2', 'ua');
select t.fails(format('select public.close_dispute(%L, ''no_settlement'')', :'d5'), 'L30 a signed file cannot be closed as "no settlement"', 'في هذه المرحلة');
select t.as_user(:'lm1'::uuid);
select public.close_dispute(:'d5'::uuid, 'settled');
select t.ok((select status = 'closed' and outcome = 'settled' from public.disputes where id = :'d5'::uuid), 'L31 closing after signature records outcome "settled"');

-- ====================================================== L7. record, metrics, gate info
select t.as_user(:'lcla'::uuid);
select public.issue_dispute_record(:'d4'::uuid) as rid4 \gset
select t.ok((select record->'data'->'dispute'->>'outcome' from public.record_exports where id = :'rid4'::uuid) = 'no_settlement'
        and (select record->'data'->'dispute'->>'outcome_reason' from public.record_exports where id = :'rid4'::uuid) = 'لم نتفق على المبلغ', 'L32 the record carries the outcome and its reason');
select t.ok((public.dispute_gate_info(:'d4'::uuid)->>'role') = 'claimant' and (public.dispute_gate_info(:'d4'::uuid)->>'status') = 'closed', 'L33 gate info reports role and status');
select t.as_user(:'ladm'::uuid);
select t.ok((public.admin_metrics()->'outcomes'->>'declined')::int >= 1
        and (public.admin_metrics()->'outcomes'->>'withdrawn')::int >= 1
        and (public.admin_metrics()->'outcomes'->>'no_settlement')::int >= 1
        and (public.admin_metrics()->'outcomes'->>'settled')::int >= 1, 'L34 metrics separate settled, no settlement, withdrawn and declined');
select t.ok((select count(*) from public.audit_logs where event_type = 'disputes.UPDATE' and new_state->>'status' = 'closed' and new_state->>'outcome' is not null) >= 2, 'L35 every closure is in the audit log with its outcome');
