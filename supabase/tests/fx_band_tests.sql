-- Migration 16: first-release value band (1,500 to 50,000 USD), supported currencies, approved exchange rates.
\set ON_ERROR_STOP 1
\pset tuples_only on
\pset format unaligned

\set fadm e1000000-0000-0000-0000-000000000001
\set fcla e1000000-0000-0000-0000-000000000002
\set fstr e1000000-0000-0000-0000-000000000003

select t.as_super();
insert into auth.users (id, email, raw_user_meta_data) values
 (:'fadm'::uuid, 'fadmin@t.com', '{"full_name":"Admin F"}'),
 (:'fcla'::uuid, 'fcla@t.com',   '{"full_name":"Claimant F"}'),
 (:'fstr'::uuid, 'fstr@t.com',   '{"full_name":"Stranger F"}');
update public.profiles set role = 'admin' where id = :'fadm'::uuid;
select egp_per_unit as egp_usd from public.fx_rates where currency = 'USD' \gset

-- ====================================================== A. rates
select t.as_user(:'fcla'::uuid);
select t.ok((select count(*) from public.fx_rates) = 6, 'F1 six currencies are configured (EGP, USD, SAR, AED, GBP, EUR)');
select t.ok((select egp_per_unit from public.fx_rates where currency = 'EGP') = 1, 'F2 the pound is the base (1)');
select t.ok((select egp_per_unit = round((buy + sell) / 2, 6) from public.fx_rates where currency = 'USD'), 'F3 the approved rate is the average of the central bank buy and sell rates');
select t.fails($$select public.set_fx_rates('{}'::jsonb, 'مصدر الأسعار', current_date)$$, 'F4 a normal user cannot set rates', 'غير مصرح');
select t.fails($$update public.fx_rates set buy = 1 where currency = 'USD'$$, 'F5 rates cannot be edited directly', 'permission denied');
select t.as_user(:'fadm'::uuid);
select t.fails($$select public.set_fx_rates('{"USD":{"buy":50,"sell":51}}'::jsonb, 'مصدر الأسعار', current_date)$$, 'F6 all five foreign rates are required', 'غير صالح');
select t.fails($$select public.set_fx_rates('{"USD":{"buy":52,"sell":51},"EUR":{"buy":1,"sell":2},"GBP":{"buy":1,"sell":2},"SAR":{"buy":1,"sell":2},"AED":{"buy":1,"sell":2}}'::jsonb, 'مصدر الأسعار', current_date)$$,
               'F7 the sell rate cannot be below the buy rate', 'سعر البيع أقل');
select t.fails($$select public.set_fx_rates('{"USD":{"buy":50,"sell":51},"EUR":{"buy":1,"sell":2},"GBP":{"buy":1,"sell":2},"SAR":{"buy":1,"sell":2},"AED":{"buy":1,"sell":2}}'::jsonb, 'x', current_date)$$,
               'F8 the source of the rates is mandatory', 'مصدر');

-- ====================================================== B. conversion
select t.as_user(:'fcla'::uuid);
select t.ok((public.fx_quote(10000, 'USD')->>'usd')::numeric = 10000, 'F9 USD converts to itself');
select t.ok(abs((public.fx_quote(round(:egp_usd * 2000), 'EGP')->>'usd')::numeric - 2000) < 0.1, 'F10 an EGP amount worth 2,000 USD converts to about 2,000');
select t.ok((public.fx_quote(1000, 'EUR')->>'usd')::numeric = round(1000 * (select egp_per_unit from public.fx_rates where currency = 'EUR') / :egp_usd, 2), 'F11 EUR converts through the pound at the approved rates');
select t.fails($$select public.fx_quote(100, 'JPY')$$, 'F12 an unsupported currency is refused', 'غير مدعومة');
select t.fails($$select public.fx_quote(0, 'USD')$$, 'F13 a zero value is refused', 'غير صالحة');

-- ====================================================== C. the band is enforced in the database
select t.fails($$select public.create_dispute('نزاع دون الحد', 'وصف طويل للنزاع يتجاوز الخمسين حرفا حتى يكون صالحا للاختبار في قاعدة البيانات', 'commercial', 1499, 'fres@t.com', '', 'USD')$$,
               'F14 1,499 USD is below the band', 'خارج نطاق الإصدار الأول');
select t.fails($$select public.create_dispute('نزاع فوق الحد', 'وصف طويل للنزاع يتجاوز الخمسين حرفا حتى يكون صالحا للاختبار في قاعدة البيانات', 'commercial', 50001, 'fres@t.com', '', 'USD')$$,
               'F15 50,001 USD is above the band', 'خارج نطاق الإصدار الأول');
select t.fails($$select public.create_dispute('نزاع بالجنيه فوق الحد', 'وصف طويل للنزاع يتجاوز الخمسين حرفا حتى يكون صالحا للاختبار في قاعدة البيانات', 'commercial', 3000000, 'fres@t.com', '')$$,
               'F16 3,000,000 EGP (about 56,000 USD) is above the band, EGP being the default currency', 'خارج نطاق');
select t.fails($$select public.create_dispute('نزاع بعملة غير مدعومة', 'وصف طويل للنزاع يتجاوز الخمسين حرفا حتى يكون صالحا للاختبار في قاعدة البيانات', 'commercial', 5000, 'fres@t.com', '', 'JPY')$$,
               'F17 an unsupported dispute currency is refused', 'غير مدعومة');
select t.fails($$select public.create_dispute('نزاع بعملة سداد غير مدعومة', 'وصف طويل للنزاع يتجاوز الخمسين حرفا حتى يكون صالحا للاختبار في قاعدة البيانات', 'commercial', 5000, 'fres@t.com', '', 'USD', 'JPY')$$,
               'F18 an unsupported fee currency is refused', 'عملة السداد');

select public.create_dispute('نزاع بالدولار عند الحد الأدنى', 'وصف طويل للنزاع يتجاوز الخمسين حرفا حتى يكون صالحا للاختبار في قاعدة البيانات', 'commercial', 1500, 'fres@t.com', '', 'USD', 'SAR')->>'id' as d1 \gset
select public.create_dispute('نزاع باليورو عند الحد الأعلى', 'وصف طويل للنزاع يتجاوز الخمسين حرفا حتى يكون صالحا للاختبار في قاعدة البيانات', 'commercial', 40000, 'fres2@t.com', '', 'EUR', 'AED')->>'id' as d2 \gset
select public.create_dispute('نزاع بالجنيه بلا ذكر العملة', 'وصف طويل للنزاع يتجاوز الخمسين حرفا حتى يكون صالحا للاختبار في قاعدة البيانات', 'commercial', 200000, 'fres3@t.com', '')->>'id' as d3 \gset
select t.as_super();   -- a party reads the file only after accepting the agreement; the checks below read the stored values directly
select t.ok((select value_usd from public.disputes where id = :'d1'::uuid) = 1500 and (select value_currency from public.disputes where id = :'d1'::uuid) = 'USD', 'F19 exactly 1,500 USD is accepted and stored');
select t.ok((select fee_currency from public.disputes where id = :'d1'::uuid) = 'SAR' and (select fee_currency from public.disputes where id = :'d2'::uuid) = 'AED', 'F20 the chosen fee currency is stored');
select t.ok((select value_currency from public.disputes where id = :'d3'::uuid) = 'EGP' and (select fee_currency from public.disputes where id = :'d3'::uuid) = 'EGP', 'F21 EGP is the default currency, and the fee currency defaults to the value currency');
select t.ok((select dispute_value_egp from public.disputes where id = :'d2'::uuid) = round(40000 * (select egp_per_unit from public.fx_rates where currency = 'EUR'), 2), 'F22 the EGP equivalent is kept for the reports');
select t.ok((select fx_egp_per_usd from public.disputes where id = :'d2'::uuid) = :egp_usd and (select fx_rate_date from public.disputes where id = :'d2'::uuid) is not null, 'F23 the rate used and its date are stored with the dispute');

-- ====================================================== D. rates changing later do not move an existing dispute
select t.as_user(:'fadm'::uuid);
select public.set_fx_rates('{"USD":{"buy":60,"sell":61},"EUR":{"buy":65,"sell":66},"GBP":{"buy":75,"sell":76},"SAR":{"buy":16,"sell":16.2},"AED":{"buy":16.4,"sell":16.6}}'::jsonb, 'اختبار تحديث الأسعار', current_date);
select t.ok((select egp_per_unit from public.fx_rates where currency = 'USD') = 60.5, 'F24 the admin updates the rates (the average is recomputed)');
select t.as_super();
select t.ok((select value_usd from public.disputes where id = :'d2'::uuid) = round(40000 * (select fx_egp_per_unit from public.disputes where id = :'d2'::uuid) / :egp_usd, 2), 'F25 an existing dispute keeps the USD value computed with the rates of its day');
select t.as_super();
select t.ok(exists (select 1 from public.audit_logs where event_type = 'fx_rates.UPDATE'), 'F26 a rate change is in the audit log');

-- put the rates back (the central bank bulletin of Friday 13 November 2026) so nothing after this file is affected
select t.as_user(:'fadm'::uuid);
select public.set_fx_rates('{"USD":{"buy":53.3653,"sell":53.5047},"EUR":{"buy":59.1821,"sell":59.3474},"GBP":{"buy":70.8051,"sell":71.0061},"SAR":{"buy":14.2190,"sell":14.2569},"AED":{"buy":14.5295,"sell":14.5682}}'::jsonb, 'البنك المركزي المصري: آخر نشرة منشورة', date '2026-11-13');
