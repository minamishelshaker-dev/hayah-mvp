-- Migration 16: first-release value scope and currencies (pricing model + standalone legal documents, document 13).
-- * The US dollar is the platform's STANDARD currency only (to place a dispute in a fee tier and to apply the value band).
-- * The user states the dispute value in a currency of his choice (EGP, USD, SAR, AED, GBP, EUR) and picks the currency in which he will pay fees.
-- * First release accepts disputes worth 1,500 to 50,000 USD (inclusive). The check lives in the database, so it cannot be bypassed.
-- * Conversion uses the platform's approved rate: the average of the Central Bank of Egypt buy and sell rates, set by the admin, and the rate
--   used is stored with the dispute (value in USD, the rate and its date) so the tier can always be re-derived.

create table public.fx_rates (
  id uuid not null default gen_random_uuid() unique,
  currency text primary key check (currency in ('EGP', 'USD', 'SAR', 'AED', 'GBP', 'EUR')),
  buy numeric(14, 6) not null check (buy > 0),
  sell numeric(14, 6) not null check (sell > 0),
  egp_per_unit numeric(14, 6) generated always as (round((buy + sell) / 2, 6)) stored,   -- EGP for one unit of the currency
  rate_date date not null,
  source text not null,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id)
);

alter table public.fx_rates enable row level security;
create policy fx_rates_select on public.fx_rates for select to authenticated using (true);   -- rates are public information
revoke all on public.fx_rates from anon;
revoke insert, update, delete, truncate on public.fx_rates from authenticated;
create trigger audit_fx_rates after insert or update or delete on public.fx_rates for each row execute function public.audit_changes();

insert into public.fx_rates (currency, buy, sell, rate_date, source) values
  ('EGP', 1, 1, date '2026-11-13', 'عملة الأساس'),
  ('USD', 53.3653, 53.5047, date '2026-11-13', 'البنك المركزي المصري: آخر نشرة منشورة (الجمعة 13 نوفمبر 2026)'),
  ('EUR', 59.1821, 59.3474, date '2026-11-13', 'البنك المركزي المصري: آخر نشرة منشورة (الجمعة 13 نوفمبر 2026)'),
  ('GBP', 70.8051, 71.0061, date '2026-11-13', 'البنك المركزي المصري: آخر نشرة منشورة (الجمعة 13 نوفمبر 2026)'),
  ('SAR', 14.2190, 14.2569, date '2026-11-13', 'البنك المركزي المصري: آخر نشرة منشورة (الجمعة 13 نوفمبر 2026)'),
  ('AED', 14.5295, 14.5682, date '2026-11-13', 'البنك المركزي المصري: آخر نشرة منشورة (الجمعة 13 نوفمبر 2026)');

-- the admin updates the five foreign rates at once; EGP stays 1
create or replace function public.set_fx_rates(p_rates jsonb, p_source text, p_date date) returns void
language plpgsql security definer set search_path = public as $$
declare v_cur text; v_buy numeric; v_sell numeric;
begin
  if not public.is_admin() then raise exception 'غير مصرح'; end if;
  perform public.require_mfa();
  if length(trim(coalesce(p_source, ''))) < 5 then raise exception 'اكتب مصدر الأسعار'; end if;
  if p_date is null or p_date > current_date + 1 then raise exception 'تاريخ الأسعار غير صالح'; end if;
  foreach v_cur in array array['USD', 'EUR', 'GBP', 'SAR', 'AED'] loop
    v_buy := (p_rates -> v_cur ->> 'buy')::numeric; v_sell := (p_rates -> v_cur ->> 'sell')::numeric;
    if v_buy is null or v_sell is null or v_buy <= 0 or v_sell <= 0 then raise exception 'سعر % غير صالح', v_cur; end if;
    if v_sell < v_buy then raise exception 'سعر البيع أقل من سعر الشراء في %', v_cur; end if;
    update public.fx_rates set buy = v_buy, sell = v_sell, rate_date = p_date, source = trim(p_source), updated_at = now(), updated_by = auth.uid()
     where currency = v_cur;
  end loop;
end $$;

-- value in a currency -> standard USD value, with the rates used (read-only, any signed-in user)
create or replace function public.fx_quote(p_amount numeric, p_currency text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_unit numeric; v_usd numeric; v_date date;
begin
  if p_amount is null or p_amount <= 0 then raise exception 'قيمة النزاع غير صالحة'; end if;
  select egp_per_unit, rate_date into v_unit, v_date from public.fx_rates where currency = upper(coalesce(p_currency, 'EGP'));
  if v_unit is null then raise exception 'العملة غير مدعومة'; end if;
  select egp_per_unit into v_usd from public.fx_rates where currency = 'USD';
  return jsonb_build_object('amount', p_amount, 'currency', upper(coalesce(p_currency, 'EGP')),
    'egp_per_unit', v_unit, 'egp_per_usd', v_usd, 'rate_date', v_date,
    'usd', round(p_amount * v_unit / v_usd, 2), 'egp', round(p_amount * v_unit, 2));
end $$;

-- the first-release band, in USD
create or replace function public.assert_value_band(p_usd numeric) returns void
language plpgsql immutable set search_path = public as $$
begin
  if p_usd < 1500 or p_usd > 50000 then
    raise exception 'قيمة النزاع تعادل % دولارًا أمريكيًا، وهي خارج نطاق الإصدار الأول: من 1,500 إلى 50,000 دولار أمريكي', to_char(p_usd, 'FM999,999,990.00');
  end if;
end $$;

-- ------------------------------------------------------------ columns (old rows keep NULL here and fall back to their EGP value)
alter table public.disputes
  add column value_amount numeric(15, 2) check (value_amount > 0),
  add column value_currency text check (value_currency in ('EGP', 'USD', 'SAR', 'AED', 'GBP', 'EUR')),
  add column value_usd numeric(15, 2),
  add column fx_egp_per_unit numeric(14, 6),
  add column fx_egp_per_usd numeric(14, 6),
  add column fx_rate_date date,
  add column fee_currency text check (fee_currency in ('EGP', 'USD', 'SAR', 'AED', 'GBP', 'EUR'));
alter table public.arbitrations
  add column value_amount numeric(15, 2) check (value_amount > 0),
  add column value_currency text check (value_currency in ('EGP', 'USD', 'SAR', 'AED', 'GBP', 'EUR')),
  add column value_usd numeric(15, 2),
  add column fx_egp_per_unit numeric(14, 6),
  add column fx_egp_per_usd numeric(14, 6),
  add column fx_rate_date date,
  add column fee_currency text check (fee_currency in ('EGP', 'USD', 'SAR', 'AED', 'GBP', 'EUR'));

-- ------------------------------------------------------------ create_dispute: value in any supported currency, band enforced
drop function public.create_dispute(text, text, text, numeric, text, text);
create or replace function public.create_dispute(
  p_title text, p_description text, p_type text, p_value numeric, p_email text, p_phone text,
  p_currency text default 'EGP', p_fee_currency text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_email text; d public.disputes; v_token text; v_agreement uuid; v_q jsonb; v_cur text; v_fee text;
begin
  perform public.check_invite_quota(auth.uid());
  if v_uid is null then raise exception 'يجب تسجيل الدخول'; end if;
  if p_type = 'labor' then
    raise exception 'منازعات العمل خارج نطاق المنصة في هذه النسخة، فهي قد تستوجب جهات تحكيم عمالي حكومية. استشر محاميًا';
  end if;
  v_cur := upper(coalesce(nullif(trim(p_currency), ''), 'EGP'));
  v_fee := upper(coalesce(nullif(trim(p_fee_currency), ''), v_cur));
  if v_fee not in ('EGP', 'USD', 'SAR', 'AED', 'GBP', 'EUR') then raise exception 'عملة السداد غير مدعومة'; end if;
  v_q := public.fx_quote(p_value, v_cur);
  perform public.assert_value_band((v_q ->> 'usd')::numeric);
  select id into v_agreement from public.legal_documents where kind = 'mediation_agreement' and is_current;
  if v_agreement is null then raise exception 'لا توجد اتفاقية وساطة منشورة'; end if;
  select email into v_email from public.profiles where id = v_uid;
  if lower(trim(p_email)) = lower(v_email) then
    raise exception 'لا يمكنك دعوة نفسك كطرف ثانٍ في النزاع';
  end if;
  insert into public.disputes (title, description, dispute_type, dispute_value_egp, created_by, claimant_id, agreement_document_id,
                               value_amount, value_currency, value_usd, fx_egp_per_unit, fx_egp_per_usd, fx_rate_date, fee_currency)
  values (p_title, p_description, p_type, (v_q ->> 'egp')::numeric, v_uid, v_uid, v_agreement,
          p_value, v_cur, (v_q ->> 'usd')::numeric, (v_q ->> 'egp_per_unit')::numeric, (v_q ->> 'egp_per_usd')::numeric, (v_q ->> 'rate_date')::date, v_fee)
  returning * into d;
  v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  insert into public.invitations (dispute_id, invited_email, invited_phone, token, expires_at)
  values (d.id, lower(trim(p_email)), nullif(trim(p_phone), ''), v_token, now() + interval '7 days');
  return jsonb_build_object('id', d.id, 'dispute_number', d.dispute_number, 'token', v_token);
end $$;

-- ------------------------------------------------------------ propose_escalation: the arbitration value is in the same band
drop function public.propose_escalation(uuid, text, text, numeric, boolean);
create or replace function public.propose_escalation(p_dispute uuid, p_title text, p_summary text, p_value numeric, p_prior_clause boolean default false, p_currency text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); d public.disputes; v_rules uuid; v_id uuid; v_resp uuid; v_q jsonb; v_cur text;
begin
  select * into d from public.disputes where id = p_dispute for update;
  if not found or (v_uid is distinct from d.claimant_id and v_uid is distinct from d.respondent_id) then raise exception 'غير مصرح'; end if;
  if not public.has_agreement(p_dispute, v_uid) then raise exception 'يجب قبول اتفاقية الوساطة أولًا'; end if;
  if not (d.status in ('active', 'settlement_draft') or (d.status = 'closed' and d.outcome = 'no_settlement')) then
    raise exception 'لا يُصعَّد إلى التحكيم إلا من وساطة جارية أو انتهت دون تسوية';
  end if;
  if exists (select 1 from public.arbitrations where source_dispute_id = p_dispute and status <> 'cancelled') then
    raise exception 'يوجد ملف تحكيم مرتبط بهذا النزاع';
  end if;
  if length(trim(coalesce(p_title, ''))) < 5 or length(trim(coalesce(p_summary, ''))) < 30 then
    raise exception 'اكتب عنوانًا وملخصًا للطلب (لا يُنقل شيء من ملف الوساطة تلقائيًا)';
  end if;
  if p_value is null or p_value <= 0 then raise exception 'قيمة النزاع غير صالحة'; end if;
  v_cur := upper(coalesce(nullif(trim(p_currency), ''), d.value_currency, 'EGP'));
  v_q := public.fx_quote(p_value, v_cur);
  perform public.assert_value_band((v_q ->> 'usd')::numeric);
  select id into v_rules from public.legal_documents where kind = 'arbitration_rules' and is_current;
  if v_rules is null then raise exception 'لا توجد قواعد تحكيم منشورة'; end if;
  v_resp := case when v_uid = d.claimant_id then d.respondent_id else d.claimant_id end;
  insert into public.arbitrations (source_dispute_id, title, summary, dispute_value_egp, prior_clause, claimant_id, respondent_id, created_by, rules_document_id,
                                   value_amount, value_currency, value_usd, fx_egp_per_unit, fx_egp_per_usd, fx_rate_date, fee_currency)
  values (p_dispute, trim(p_title), trim(p_summary), (v_q ->> 'egp')::numeric, coalesce(p_prior_clause, false), v_uid, v_resp, v_uid, v_rules,
          p_value, v_cur, (v_q ->> 'usd')::numeric, (v_q ->> 'egp_per_unit')::numeric, (v_q ->> 'egp_per_usd')::numeric, (v_q ->> 'rate_date')::date,
          coalesce(d.fee_currency, v_cur))
  returning id into v_id;
  return v_id;
end $$;

revoke execute on function public.set_fx_rates(jsonb, text, date), public.fx_quote(numeric, text), public.assert_value_band(numeric),
  public.create_dispute(text, text, text, numeric, text, text, text, text),
  public.propose_escalation(uuid, text, text, numeric, boolean, text) from public, anon, authenticated;
grant execute on function public.set_fx_rates(jsonb, text, date), public.fx_quote(numeric, text),
  public.create_dispute(text, text, text, numeric, text, text, text, text),
  public.propose_escalation(uuid, text, text, numeric, boolean, text) to authenticated;
