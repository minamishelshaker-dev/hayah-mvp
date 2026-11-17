-- Migrations 17 and 18: kinds of legal documents, the registration gate, public reading, separation from consent to any procedure.
\set ON_ERROR_STOP 1
\pset tuples_only on
\pset format unaligned

\set ladm e2000000-0000-0000-0000-000000000001
\set lusr e2000000-0000-0000-0000-000000000002
select t.as_super();
insert into auth.users (id, email, raw_user_meta_data) values
 (:'ladm'::uuid, 'legaladmin@t.com', '{"full_name":"Admin L"}'),
 (:'lusr'::uuid, 'legaluser@t.com',   '{"full_name":"User L"}');
update public.profiles set role = 'admin' where id = :'ladm'::uuid;

-- ====================================================== A. structure
select t.ok((select count(*) from public.legal_kinds) = 18, 'L1 eighteen kinds are defined');
select t.ok((select count(*) from public.legal_kinds where scope = 'registration') = 5, 'L2 five documents are accepted at registration: terms, privacy, acceptable use, disclaimer, e-signature notice');
select t.ok(not exists (select 1 from public.legal_kinds where scope = 'registration' and kind in ('mediation_agreement', 'arbitration_rules')),
            'L3 registration never includes the mediation agreement or the arbitration rules (signing up is not a consent to any procedure)');
select t.ok((select scope from public.legal_kinds where kind = 'mediation_agreement') = 'dispute' and (select scope from public.legal_kinds where kind = 'arbitration_rules') = 'arbitration', 'L4 those two are accepted per file');
select t.ok((select count(*) from public.legal_documents d join public.legal_kinds k on k.kind = d.kind where d.is_current and not d.is_placeholder and k.scope in ('registration', 'public', 'arbitration')) = 17,
            'L5 seventeen reviewed documents are current: 5 registration, 11 public policies, the arbitration rules');
select t.ok(not exists (select 1 from public.legal_documents where is_current and (body like '%مسودة%' or title like '%مسودة%') and kind in (select kind from public.legal_kinds where scope <> 'dispute')), 'L6 no published document calls itself a draft');
select t.ok(exists (select 1 from public.legal_documents where kind = 'terms' and body like '%ويقتصر الإصدار الأول على الوساطة والتحكيم%'), 'L7 the published terms state that the first release is mediation and arbitration only');
select t.ok(not exists (select 1 from public.legal_documents where is_current and body_hash <> encode(extensions.digest(convert_to(body, 'UTF8'), 'sha256'), 'hex')), 'L8 every current text matches its stored hash');
select t.ok(exists (select 1 from public.legal_documents where kind = 'arbitration_rules' and body like '%CRCICA%' and body like '%الأعلى مرتبة في كل حال%'), 'L9 the published arbitration rules carry the redrafted CRCICA clause');

-- ====================================================== B. public reading
select t.as_super();
select count(*) as ncur from public.legal_documents where is_current and not is_placeholder \gset
select t.as_anon();
select t.ok(jsonb_array_length(public.legal_public()) = :ncur and :ncur >= 17, 'L10 anyone can read every current published document (at least the 17 reviewed ones) without signing in');
select t.ok((select count(*) from jsonb_array_elements(public.legal_public()) e where e->>'scope' = 'registration') = 5, 'L11 the public listing marks the registration documents');
select t.fails($$insert into public.legal_kinds values ('x', 'public', 99, 'x')$$, 'L12 nobody can add a kind directly', 'permission denied');
select t.fails($$update public.legal_documents set body = 'x'$$, 'L13 nobody can edit a published text', 'permission denied');

-- ====================================================== C. the gate asks for every registration document, one by one
select t.as_user(:'lusr'::uuid);
select t.ok(not public.has_platform_consent(), 'L14 a new user has no platform consent');
select t.accept_legal(id, null, 'ip', 'ua') from public.legal_documents where kind in ('terms', 'privacy') and is_current;
select t.ok(not public.has_platform_consent(), 'L15 accepting only terms and privacy is not enough any more');
select t.accept_platform();
select t.ok(public.has_platform_consent(), 'L16 accepting all five registration documents opens the platform');
select t.ok((select count(*) from public.consents where user_id = :'lusr'::uuid) = 5 and not exists (select 1 from public.consents c join public.legal_documents d on d.id = c.document_id where c.user_id = :'lusr'::uuid and d.kind in ('mediation_agreement', 'arbitration_rules')),
            'L17 registration produced five acceptances and none for a mediation or an arbitration');

-- a new version of a PUBLIC policy does not interrupt anyone; a new registration document does
select t.as_user(:'ladm'::uuid);
select public.publish_legal_document('cookies', 'سياسة ملفات تعريف الارتباط', 'نص جديد لسياسة ملفات تعريف الارتباط يتضمن التفاصيل المطلوبة بما يكفي هنا.');
select t.as_user(:'lusr'::uuid);
select t.ok(public.has_platform_consent(), 'L18 a new version of a public policy needs no new acceptance');
select t.as_user(:'ladm'::uuid);
select public.publish_legal_document('acceptable_use', 'سياسة الاستخدام المقبول', 'نص جديد لسياسة الاستخدام المقبول يتضمن التفاصيل المطلوبة بما يكفي هنا.');
select t.as_user(:'lusr'::uuid);
select t.ok(not public.has_platform_consent(), 'L19 a new version of a registration document needs a new acceptance');
select t.accept_platform();
select t.ok(public.has_platform_consent(), 'L20 and accepting it restores access');
