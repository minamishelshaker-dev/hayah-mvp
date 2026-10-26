-- Migration 11: a mediation settlement signature is accepted only for the text hash the signer was shown.
\set ON_ERROR_STOP 1
\pset tuples_only on
\pset format unaligned

\set zmed f1000000-0000-0000-0000-000000000002
\set zcla f1000000-0000-0000-0000-000000000004
\set zres f1000000-0000-0000-0000-000000000005

select t.as_super();
insert into auth.users (id, email, raw_user_meta_data) values
 (:'zmed'::uuid, 'zmed@t.com', '{"full_name":"Mediator Z"}'),
 (:'zcla'::uuid, 'zcla@t.com', '{"full_name":"Claimant Z"}'),
 (:'zres'::uuid, 'zres@t.com', '{"full_name":"Respondent Z"}');
update public.profiles set role = 'mediator', kyc_status = 'verified' where id = :'zmed'::uuid;

select t.make_active(:'zcla'::uuid, :'zres'::uuid, :'zmed'::uuid, 'zres@t.com') as zd \gset
select t.as_user(:'zmed'::uuid);
select public.save_settlement(:'zd'::uuid, 'اتفاق تسوية: ١- يلتزم الطرف الأول بتسليم البضاعة ٢- يلتزم الطرف الثاني بسداد مبلغ مئة ألف جنيه.');
select public.submit_settlement(:'zd'::uuid);
select t.as_user(:'zcla'::uuid);
select content_hash as zh1 from public.settlements where dispute_id = :'zd'::uuid \gset

-- the mediator reopens and edits after the claimant's page was rendered
select t.as_user(:'zmed'::uuid);
select public.reopen_settlement(:'zd'::uuid, 'تصحيح بند');
select public.save_settlement(:'zd'::uuid, 'اتفاق تسوية (معدّل): ١- يلتزم الطرف الأول بتسليم البضاعة خلال أسبوع ٢- يلتزم الطرف الثاني بسداد مبلغ مئة ألف جنيه.');
select public.submit_settlement(:'zd'::uuid);
select t.as_user(:'zcla'::uuid);
select content_hash as zh2 from public.settlements where dispute_id = :'zd'::uuid \gset
select t.ok(:'zh1' <> :'zh2', 'Z0 editing the text changes its hash');

select t.fails(format('select t.sign_settlement_bound(%L, %L, ''1.1.1.1'', ''ua'')', :'zd', :'zh1'),
               'Z1 a party who saw the OLD text cannot sign the new one', 'تغيّر نص الاتفاق');
select t.as_super();
select t.ok((select count(*) from public.settlement_signatures where dispute_id = :'zd'::uuid) = 0, 'Z2 the refused attempt left no signature behind');

select t.as_user(:'zmed'::uuid);
select t.fails(format('select t.sign_settlement_bound(%L, %L, ''1.1.1.1'', ''ua'')', :'zd', :'zh2'), 'Z3 the mediator still cannot sign', 'للأطراف فقط');
select t.fails(format('select public.sign_settlement_bound_srv(%L, ''aal2'', %L, %L, ''1.1.1.1'', ''ua'')', :'zcla', :'zd', :'zh2'),
               'Z4 users cannot call the server-only function', 'permission denied');

select t.as_user(:'zcla'::uuid);
select t.sign_settlement_bound(:'zd'::uuid, :'zh2', '1.1.1.1', 'ua');
select t.as_user(:'zres'::uuid);
select t.sign_settlement_bound(:'zd'::uuid, :'zh2', '2.2.2.2', 'ua');
select t.as_super();
select t.ok((select count(*) = 2 and bool_and(content_hash = :'zh2') from public.settlement_signatures where dispute_id = :'zd'::uuid), 'Z5 both signatures carry the hash they were shown');
select t.ok((select status = 'signed' from public.disputes where id = :'zd'::uuid), 'Z6 the dispute is signed after the second signature');
