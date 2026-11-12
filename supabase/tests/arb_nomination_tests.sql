-- Migration 15: arbitrator nomination by the platform. Needs helpers.sql, lifecycle_tests.sql (t.make_active) and arbitration_tests.sql (t.make_arb).
\set ON_ERROR_STOP 1
\pset tuples_only on
\pset format unaligned

\set nadm e0000000-0000-0000-0000-000000000001
\set nmed e0000000-0000-0000-0000-000000000002
\set ncla e0000000-0000-0000-0000-000000000003
\set nres e0000000-0000-0000-0000-000000000004
\set nstr e0000000-0000-0000-0000-000000000005
\set na1  e0000000-0000-0000-0000-0000000000a1
\set na2  e0000000-0000-0000-0000-0000000000a2
\set na3  e0000000-0000-0000-0000-0000000000a3
\set na4  e0000000-0000-0000-0000-0000000000a4
\set na5  e0000000-0000-0000-0000-0000000000a5
\set na6  e0000000-0000-0000-0000-0000000000a6
\set na7  e0000000-0000-0000-0000-0000000000a7

select t.as_super();
insert into auth.users (id, email, raw_user_meta_data) values
 (:'nadm'::uuid, 'nadmin@t.com', '{"full_name":"Admin N"}'),
 (:'nmed'::uuid, 'nmed@t.com',   '{"full_name":"Mediator N"}'),
 (:'ncla'::uuid, 'ncla@t.com',   '{"full_name":"Claimant N"}'),
 (:'nres'::uuid, 'nres@t.com',   '{"full_name":"Respondent N"}'),
 (:'nstr'::uuid, 'nstr@t.com',   '{"full_name":"Stranger N"}'),
 (:'na1'::uuid,  'na1@t.com',    '{"full_name":"Arbitrator N1"}'),
 (:'na2'::uuid,  'na2@t.com',    '{"full_name":"Arbitrator N2"}'),
 (:'na3'::uuid,  'na3@t.com',    '{"full_name":"Arbitrator N3"}'),
 (:'na4'::uuid,  'na4@t.com',    '{"full_name":"Arbitrator N4"}'),
 (:'na5'::uuid,  'na5@t.com',    '{"full_name":"Arbitrator N5"}'),
 (:'na6'::uuid,  'na6@t.com',    '{"full_name":"Arbitrator N6"}'),
 (:'na7'::uuid,  'na7@t.com',    '{"full_name":"Arbitrator N7"}');
update public.profiles set role = 'admin' where id = :'nadm'::uuid;
update public.profiles set role = 'mediator', kyc_status = 'verified' where id = :'nmed'::uuid;
update public.profiles set role = 'arbitrator', kyc_status = 'verified', phone = '01333333333'
 where id in (:'na1'::uuid, :'na2'::uuid, :'na3'::uuid, :'na4'::uuid, :'na5'::uuid, :'na6'::uuid, :'na7'::uuid);

select count(*) as npool from public.profiles where role = 'arbitrator' and kyc_status = 'verified' \gset

-- ====================================================== A. the parties agree on one of the nominees
select t.make_arb(:'ncla'::uuid, :'nres'::uuid, :'nmed'::uuid, :'na1'::uuid, 'nres@t.com', 'selection') as arb \gset

select t.as_user(:'nstr'::uuid);
select t.fails(format('select public.request_nomination(%L)', :'arb'), 'N1 an outsider cannot ask for a nomination', 'غير مصرح');
select t.ok(public.arb_nomination_state(:'arb'::uuid) is null, 'N2 an outsider sees no nomination state');

select t.as_user(:'ncla'::uuid);
select public.request_nomination(:'arb'::uuid) as nom \gset
select t.ok((select array_length(nominees, 1) from public.arb_nominations where id = :'nom'::uuid) = 5, 'N3 the platform nominates at most 5 (more than 5 were eligible)');
select t.ok((select eligible_count from public.arb_nominations where id = :'nom'::uuid) = :npool, 'N4 the whole eligible pool is counted (every verified arbitrator; the parties and the mediator are not arbitrators)');
select t.ok((select draw_seed from public.arb_nominations where id = :'nom'::uuid) ~ '^[0-9a-f]{64}$', 'N5 the draw seed is stored (the draw can be re-run)');
select t.fails(format('select public.request_nomination(%L)', :'arb'), 'N6 only one open nomination at a time', 'ترشيح قائم');

select (public.arb_nomination_state(:'arb'::uuid)->'nominees'->0->>'id') as n0, (public.arb_nomination_state(:'arb'::uuid)->'nominees'->1->>'id') as n1 \gset
select t.fails(format('select public.choose_nominee(%L, %L)', :'nom', :'nadm'), 'N8 a pick must come from the nominated list', 'ليس من قائمة الترشيح');
select t.ok(public.choose_nominee(:'nom'::uuid, :'n0'::uuid) = 'waiting', 'N9 the first pick waits for the other party');
select t.fails(format('select public.choose_nominee(%L, %L)', :'nom', :'n0'), 'N10 a party cannot pick twice', 'سبق أن سجّلت');

select t.as_user(:'nres'::uuid);
select t.ok((select (public.arb_nomination_state(:'arb'::uuid)->>'other_chose')::boolean) and (public.arb_nomination_state(:'arb'::uuid)->'other_choice') = 'null'::jsonb,
            'N11 the respondent sees THAT the claimant picked but not WHOM, before deciding');
select t.ok((select count(*) from public.arb_nomination_choices where party_id = :'ncla'::uuid) = 0, 'N12 the claimant''s pick row is private to him (RLS)');
select t.ok(public.choose_nominee(:'nom'::uuid, :'n0'::uuid) = 'agreed', 'N13 the same pick on both sides: agreed');
select t.ok((select status from public.arb_assignments where arbitration_id = :'arb'::uuid and arbitrator_id = :'n0'::uuid) = 'approved'
        and (select appointed_by from public.arb_assignments where arbitration_id = :'arb'::uuid and arbitrator_id = :'n0'::uuid) = 'parties_nomination',
            'N14 the agreed nominee becomes an approved assignment, marked as chosen from the nomination');
select t.ok((select status from public.arb_nominations where id = :'nom'::uuid) = 'agreed', 'N15 the nomination is closed as agreed');
select t.as_user(:'n0'::uuid);
select t.accept_rules(:'arb'::uuid);
select public.arbitrator_respond((select id from public.arb_assignments where arbitration_id = :'arb'::uuid and status = 'approved'), true, repeat('أقرّ باستقلالي وحيادي التام تجاه الطرفين والنزاع. ', 2));
select t.ok((select status from public.arbitrations where id = :'arb'::uuid) = 'active' and (select arbitrator_id from public.arbitrations where id = :'arb'::uuid) = :'n0'::uuid,
            'N16 the nominee accepts with his declaration and the arbitration opens');

-- ====================================================== B. no agreement: acknowledgment, then the platform draws
select t.make_arb(:'ncla'::uuid, :'nres'::uuid, :'nmed'::uuid, :'na1'::uuid, 'nres@t.com', 'selection') as arb2 \gset
select t.as_user(:'nres'::uuid);
select public.request_nomination(:'arb2'::uuid) as nom2 \gset
select (public.arb_nomination_state(:'arb2'::uuid)->'nominees'->0->>'id') as m0, (public.arb_nomination_state(:'arb2'::uuid)->'nominees'->1->>'id') as m1 \gset
select t.fails(format('select public.ack_platform_appointment(%L)', :'nom2'), 'B1 no acknowledgment while the nomination is still open', 'لا يُطلب هذا الإقرار');
select public.choose_nominee(:'nom2'::uuid, :'m0'::uuid);
select t.as_user(:'ncla'::uuid);
select t.ok(public.choose_nominee(:'nom2'::uuid, :'m1'::uuid) = 'no_agreement', 'B2 different picks: no agreement');
select t.ok((select (public.arb_nomination_state(:'arb2'::uuid)->>'other_choice')::uuid) = :'m0'::uuid, 'B3 once decided, each party sees the other''s pick');
select t.fails(format('select public.choose_nominee(%L, %L)', :'nom2', :'m0'), 'B4 the nomination is closed to further picks', 'تم حسم');

select t.as_user(:'nstr'::uuid);
select t.fails(format('select public.ack_platform_appointment(%L)', :'nom2'), 'B5 an outsider cannot sign the acknowledgment', 'غير مصرح');
select t.as_user(:'ncla'::uuid);
select t.ok(public.ack_platform_appointment(:'nom2'::uuid) = 'waiting', 'B6 the first acknowledgment waits');
select t.fails(format('select public.ack_platform_appointment(%L)', :'nom2'), 'B7 nobody signs twice', 'سبق أن وقّعت');
select t.ok((select count(*) from public.arb_assignments where arbitration_id = :'arb2'::uuid) = 0, 'B8 nothing is appointed on one signature');
select t.as_user(:'nres'::uuid);
select t.ok(public.ack_platform_appointment(:'nom2'::uuid) = 'appointed', 'B9 both signed: the platform appoints');
select t.ok((select appointed_by from public.arb_assignments where arbitration_id = :'arb2'::uuid and status = 'approved') = 'platform_draw'
        and (select nominees from public.arb_nominations where id = :'nom2'::uuid) @> array[(select arbitrator_id from public.arb_assignments where arbitration_id = :'arb2'::uuid and status = 'approved')],
            'B10 the appointed arbitrator is one of the nominees shown to the parties, marked as a platform draw');
select t.ok((select ack_text_hash from public.arb_nominations where id = :'nom2'::uuid) = encode(sha256(convert_to(public.arb_appointment_ack_text(), 'UTF8')), 'hex')
        and (select platform_draw_seed from public.arb_nominations where id = :'nom2'::uuid) is not null, 'B11 the signed text hash and the platform draw seed are recorded');
select t.ok((select count(*) from public.arb_appointment_acks where nomination_id = :'nom2'::uuid) = 2, 'B12 both acknowledgments are on record');

-- the drawn arbitrator may still refuse; the next round skips him
select arbitrator_id as drawn from public.arb_assignments where arbitration_id = :'arb2'::uuid and status = 'approved' \gset
select t.as_user(:'drawn'::uuid);
select t.accept_rules(:'arb2'::uuid);
select public.arbitrator_respond((select id from public.arb_assignments where arbitration_id = :'arb2'::uuid and status = 'approved'), false);
select t.as_user(:'ncla'::uuid);
select t.ok((select status from public.arbitrations where id = :'arb2'::uuid) = 'selection', 'B13 a refusal leaves the file in selection');
select public.request_nomination(:'arb2'::uuid) as nom3 \gset
select t.ok((select round from public.arb_nominations where id = :'nom3'::uuid) = 2 and not ((select nominees from public.arb_nominations where id = :'nom3'::uuid) @> array[:'drawn'::uuid]),
            'B14 round 2 starts and excludes the arbitrator who refused');

-- ====================================================== C. nobody else can read it
select t.as_user(:'nstr'::uuid);
select t.ok((select count(*) from public.arb_nominations) = 0 and (select count(*) from public.arb_appointment_acks) = 0, 'C1 an outsider reads no nomination and no acknowledgment (RLS)');
select t.as_user(:'ncla'::uuid);
select t.fails('insert into public.arb_nominations (arbitration_id, round, requested_by, draw_seed, eligible_count, nominees) select id, 99, claimant_id, ''x'', 1, ''{}'' from public.arbitrations limit 1',
               'C2 nobody can write a nomination directly', 'permission denied');

-- the admin can read the audit trail of the whole selection
select t.as_user(:'nadm'::uuid);
select t.ok(exists (select 1 from public.audit_logs where event_type = 'arb_nominations.INSERT' and entity_id = :'nom'::uuid), 'C3 the nomination (with its seed) is in the audit log');
select t.ok(exists (select 1 from public.audit_logs where event_type = 'arb_nomination_choices.INSERT') and exists (select 1 from public.audit_logs where event_type = 'arb_appointment_acks.INSERT'),
            'C4 the picks and the signed acknowledgments are in the audit log too');
select t.ok((public.verify_audit_chain()->>'ok')::boolean, 'C5 the audit chain still verifies');
