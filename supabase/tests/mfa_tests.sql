-- Two-step verification. Reuses the accounts created in lifecycle_tests.sql (run after it).
\set ON_ERROR_STOP 1
\pset tuples_only on
\pset format unaligned

\set ladm b0000000-0000-0000-0000-000000000001
\set lm1  b0000000-0000-0000-0000-000000000002
\set lm2  b0000000-0000-0000-0000-000000000003
\set lcla b0000000-0000-0000-0000-000000000004
\set lres b0000000-0000-0000-0000-000000000005

select t.make_active(:'lcla'::uuid, :'lres'::uuid, :'lm1'::uuid, 'lres@t.com') as dm \gset

-- ============================================================ mediator without the second step
select t.as_user(:'lm1'::uuid, 'aal1');
select t.ok((select count(*) from public.disputes) = 0, 'M1 a mediator on a first-step session reads nothing');
select t.ok(public.dispute_gate_info(:'dm'::uuid) is null, 'M2 and is not even recognised as a member');
select t.fails(format('select public.schedule_session(%L, now() + interval ''1 day'', 60)', :'dm'), 'M3 cannot schedule a session', 'خطوتين');
select t.fails(format('select public.save_settlement(%L, repeat(''x'', 80))', :'dm'), 'M4 cannot draft a settlement', 'خطوتين');
select t.fails(format('select public.submit_settlement(%L)', :'dm'), 'M5 cannot open a settlement for signature', 'خطوتين');
select t.fails(format('select public.mediator_withdraw(%L)', :'dm'), 'M6 cannot step down through the API', 'خطوتين');
select t.fails(format('select public.close_dispute(%L, ''no_settlement'')', :'dm'), 'M7 cannot close a file', 'خطوتين');
select t.fails(format('select t.register_document(%L, ''a.pdf'', %L, ''application/pdf'', 1, %L)', :'dm', :'dm' || '/q', repeat('d', 64)),
  'M8 cannot register documents', 'غير مصرح');
select t.ok((public.mfa_status()->>'required')::boolean and not (public.mfa_status()->>'ok')::boolean, 'M9 the app is told: required, not yet satisfied');

select t.as_user(:'lm1'::uuid, 'aal2');
select t.ok((select count(*) from public.disputes where id = :'dm'::uuid) = 1, 'M10 the same mediator after the second step reads his file');
select public.schedule_session(:'dm'::uuid, now() + interval '1 day', 60);
select t.ok((select count(*) from public.sessions where dispute_id = :'dm'::uuid) = 1, 'M11 and acts normally');
select t.ok((public.mfa_status()->>'ok')::boolean, 'M12 status is satisfied');

-- ============================================================ parties are never asked
select t.as_user(:'lcla'::uuid, 'aal1');
select t.ok((select count(*) from public.disputes) >= 1 and not (public.mfa_status()->>'required')::boolean, 'M13 a party on a first-step session works normally');

-- ============================================================ admin without the second step
select t.as_user(:'ladm'::uuid, 'aal1');
select t.fails($$select public.admin_metrics()$$, 'M14 an admin on a first-step session has no metrics', 'غير مصرح');
select t.fails($$select public.publish_legal_document('terms','شروط','نص الشروط الجديد طويل بما يكفي هنا')$$, 'M15 cannot publish legal text', 'غير مصرح');
select t.fails($$select public.verify_audit_chain()$$, 'M16 cannot verify the audit chain', 'غير مصرح');
select t.fails($$select public.security_status()$$, 'M17 cannot read the security status', 'غير مصرح');
select t.ok((select count(*) from public.audit_logs) = 0, 'M18 cannot read the audit log');
update public.profiles set role = 'mediator' where id = :'lres'::uuid;
select t.as_super();
select t.ok((select role from public.profiles where id = :'lres'::uuid) = 'party', 'M19 an admin on a first-step session cannot change anyone''s role');

select t.as_user(:'ladm'::uuid, 'aal2');
select t.ok((public.admin_metrics()->'funnel'->>'created')::int >= 1, 'M20 the same admin after the second step has his tools');
select t.ok((public.security_status()->>'mfa_required')::boolean, 'M21 the security status reports MFA as required');
select t.ok((public.verify_audit_chain()->>'ok')::boolean, 'M22 the audit chain still verifies');

-- ============================================================ the setting itself
select t.fails($$select * from public.app_settings$$, 'M23 settings are not readable through the API', 'permission denied');
select t.fails($$update public.app_settings set value = 'false'$$, 'M24 nor changeable through the API', 'permission denied');
select t.as_super();
update public.app_settings set value = 'false' where key = 'require_mfa';
select t.ok((select count(*) from public.audit_logs where event_type = 'app_settings.UPDATE' and new_state->>'value' = 'false') = 1, 'M25 switching MFA off is written to the audit log');
select t.as_user(:'ladm'::uuid, 'aal1');
select t.ok((public.admin_metrics()->'funnel'->>'created')::int >= 1, 'M26 with the switch off, an admin works without the second step (demo mode)');
select t.as_super();
update public.app_settings set value = 'true' where key = 'require_mfa';
select t.as_user(:'ladm'::uuid, 'aal1');
select t.fails($$select public.admin_metrics()$$, 'M27 switching it back on restores the requirement immediately', 'غير مصرح');

-- ============================================================ audited admin actions
select t.fails($$select public.record_admin_event('mfa_reset', gen_random_uuid())$$, 'M28 an admin on a first-step session cannot log admin events', 'غير مصرح');
select t.as_user(:'lcla'::uuid);
select t.fails($$select public.record_admin_event('mfa_reset', gen_random_uuid())$$, 'M29 a party cannot log admin events', 'غير مصرح');
select t.as_user(:'ladm'::uuid, 'aal2');
select public.record_admin_event('mfa_reset', :'lm2'::uuid);
select public.record_admin_event('Bad Event; drop', :'lm2'::uuid);
select t.ok((select count(*) from public.audit_logs where event_type = 'admin.mfa_reset' and entity_id = :'lm2'::uuid) = 1, 'M30 an MFA reset is recorded with its target');
select t.ok((select count(*) from public.audit_logs where event_type = 'admin.adventdrop') = 1, 'M31 event names are sanitised');
