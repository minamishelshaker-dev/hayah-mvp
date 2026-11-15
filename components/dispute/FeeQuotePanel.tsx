import { fromUsd, inBand, quotePath, type RateLite } from '@/lib/fees'
import { CURRENCY_LABEL, formatMoney } from '@/lib/labels'

// Fee estimate for the first release (mediation and arbitration), shown in the currency the user chose to pay in.
export default function FeeQuotePanel({ valueUsd, feeCurrency, rates }: { valueUsd: number | null | undefined; feeCurrency: string | null | undefined; rates: RateLite[] }) {
  if (valueUsd == null || !inBand(Number(valueUsd))) return null
  const cur = feeCurrency ?? 'EGP'
  if (!rates.some((r) => r.currency === cur) || !rates.some((r) => r.currency === 'USD')) return null
  const q = quotePath(Number(valueUsd))
  const m = (v: number) => formatMoney(fromUsd(v, cur, rates), cur)
  const rows: [string, { neutral: number; platformDue: number; due: number }][] = [
    ['الوساطة', q.mediation],
    ['التحكيم مباشرة', q.arbitrationDirect],
    ['التحكيم بعد وساطة', q.arbitrationAfterMediation],
  ]
  return (
    <section className="panel space-y-2">
      <h2 className="text-lg">تقدير الرسوم</h2>
      <p className="hint">عملة السداد المختارة: {CURRENCY_LABEL[cur] ?? cur}. التقدير للعرض فقط، ولا تُحصَّل أي رسوم في التجربة الأولى.</p>
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead><tr className="text-right text-navy-500"><th className="p-2">الخدمة</th><th className="p-2">أتعاب المحايد</th><th className="p-2">حصة المنصة</th><th className="p-2">المستحق</th></tr></thead>
          <tbody>
            {rows.map(([label, r]) => (
              <tr key={label} className="border-t border-navy-100"><td className="p-2">{label}</td><td className="p-2">{m(r.neutral)}</td><td className="p-2">{m(r.platformDue)}</td><td className="p-2 font-semibold">{m(r.due)}</td></tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="hint">عند الانتقال من الوساطة إلى التحكيم يُسدَّد أتعاب المحكّم كاملة، وتُخصم من حصة المنصة حصتها المحصَّلة في الوساطة فقط.</p>
    </section>
  )
}
