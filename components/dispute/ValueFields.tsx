'use client'

import { useState } from 'react'
import { BAND, fromUsd, inBand, quotePath, toUsd, type RateLite } from '@/lib/fees'
import { CURRENCIES, CURRENCY_LABEL, formatMoney } from '@/lib/labels'

type Props = {
  rates: (RateLite & { rate_date?: string })[]
  amountName?: string; currencyName?: string; feeName?: string
  defaultCurrency?: string; defaultAmount?: number | string
  showFee?: boolean; idPrefix?: string
}

// Value of the dispute in a currency chosen by the user, with the live USD equivalent (the platform's standard currency),
// the first-release band check, and a fee estimate in the currency the user will pay in. The database repeats every check.
export default function ValueFields({ rates, amountName = 'dispute_value', currencyName = 'dispute_currency', feeName = 'fee_currency',
  defaultCurrency = 'EGP', defaultAmount = '', showFee = true, idPrefix = 'v' }: Props) {
  const [amount, setAmount] = useState(String(defaultAmount ?? ''))
  const [currency, setCurrency] = useState(defaultCurrency)
  const [feeCurrency, setFeeCurrency] = useState(defaultCurrency)
  const n = Number(amount)
  const known = rates.some((r) => r.currency === currency) && rates.some((r) => r.currency === 'USD')
  const usd = known && n > 0 ? toUsd(n, currency, rates) : null
  const ok = usd != null && inBand(usd)
  const path = usd != null && ok ? quotePath(usd) : null
  const money = (v: number) => (rates.some((r) => r.currency === feeCurrency) ? formatMoney(fromUsd(v, feeCurrency, rates), feeCurrency) : '')
  const date = rates.find((r) => r.currency === 'USD')?.rate_date
  return (
    <div className="space-y-3">
      <div className="grid gap-3 sm:grid-cols-[1fr_1fr_1fr]">
        <div>
          <label className="label" htmlFor={`${idPrefix}-amount`}>قيمة النزاع</label>
          <input id={`${idPrefix}-amount`} name={amountName} type="number" required min="0.01" step="0.01" dir="ltr" className="input"
            value={amount} onChange={(e) => setAmount(e.target.value)} />
        </div>
        <div>
          <label className="label" htmlFor={`${idPrefix}-currency`}>عملة قيمة النزاع</label>
          <select id={`${idPrefix}-currency`} name={currencyName} className="input" value={currency}
            onChange={(e) => { setCurrency(e.target.value); setFeeCurrency(e.target.value) }}>
            {CURRENCIES.map((c) => <option key={c} value={c}>{CURRENCY_LABEL[c]} ({c})</option>)}
          </select>
        </div>
        {showFee && (
          <div>
            <label className="label" htmlFor={`${idPrefix}-fee`}>عملة سداد الرسوم</label>
            <select id={`${idPrefix}-fee`} name={feeName} className="input" value={feeCurrency} onChange={(e) => setFeeCurrency(e.target.value)}>
              {CURRENCIES.map((c) => <option key={c} value={c}>{CURRENCY_LABEL[c]} ({c})</option>)}
            </select>
          </div>
        )}
      </div>
      <p className="hint">
        الإصدار الأول يقبل منازعات تتراوح قيمتها بين {BAND.minUsd.toLocaleString('ar-EG')} و{BAND.maxUsd.toLocaleString('ar-EG')} دولار أمريكي أو ما يعادلها.
        الدولار عملة معيارية داخل المنصة فقط (لتحديد الشريحة)، وتُحوَّل القيمة بسعر الصرف المعتمد{date ? ` بتاريخ ${date}` : ''}.
      </p>
      {usd != null && (
        <p className={`text-sm font-semibold ${ok ? 'text-emerald-700' : 'text-red-700'}`} role={ok ? undefined : 'alert'}>
          المعادل بالدولار الأمريكي: {formatMoney(usd, 'USD')} — {ok ? 'ضمن نطاق الإصدار الأول' : 'خارج نطاق الإصدار الأول'}
        </p>
      )}
      {showFee && path && (
        <div className="rounded-md border border-navy-100 bg-white p-3 text-sm">
          <p className="font-semibold">تقدير الرسوم (للعرض فقط)</p>
          <ul className="mt-1 list-disc space-y-1 pr-5">
            <li>الوساطة: {money(path.mediation.due)}</li>
            <li>التحكيم مباشرة: {money(path.arbitrationDirect.due)}</li>
            <li>التحكيم بعد وساطة: {money(path.arbitrationAfterMediation.due)} (أتعاب المحايد كاملة، وتُخصم من حصة المنصة حصتها المحصَّلة في الوساطة)</li>
          </ul>
          <p className="hint mt-1">لا تُحصَّل أي رسوم في التجربة الأولى. التقدير بالأسعار المعتمدة اليوم، وقد يختلف عند السداد.</p>
        </div>
      )}
    </div>
  )
}
