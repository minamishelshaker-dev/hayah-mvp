import { createClient } from '@/lib/supabase/server'
import FormAction from '@/components/FormAction'
import { setFxRates } from '../actions'
import { CURRENCY_LABEL } from '@/lib/labels'
import type { FxRate } from '@/lib/types'

const FOREIGN = ['USD', 'EUR', 'GBP', 'SAR', 'AED']

export default async function AdminRatesPage() {
  const { data } = await (await createClient()).from('fx_rates').select('currency, buy, sell, egp_per_unit, rate_date, source').order('currency')
  const rates = (data ?? []) as FxRate[]
  const by = Object.fromEntries(rates.map((r) => [r.currency, r]))
  const date = by.USD?.rate_date
  const ageDays = date ? Math.floor((Date.now() - new Date(date).getTime()) / 86_400_000) : null
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl">أسعار الصرف المعتمدة</h1>
        <p className="hint">
          الدولار الأمريكي عملة معيارية داخل المنصة فقط: به يُحدَّد نطاق الإصدار الأول (من 1,500 إلى 50,000 دولار) وشريحة الرسوم. يختار المستخدم عملة قيمة النزاع وعملة سداد الرسوم من:
          الجنيه المصري، الدولار الأمريكي، الريال السعودي، الدرهم الإماراتي، الجنيه الإسترليني، اليورو. السعر المعتمد هو متوسط سعري الشراء والبيع المعلنين من البنك المركزي المصري.
        </p>
      </div>
      {ageDays != null && ageDays > 7 && (
        <p className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-700" role="alert">آخر تحديث للأسعار قبل {ageDays} يومًا. حدّثها من موقع البنك المركزي المصري قبل قبول نزاعات جديدة.</p>
      )}
      <section className="panel space-y-3">
        <h2 className="text-lg">الأسعار الحالية (جنيه مصري لكل وحدة)</h2>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead><tr className="text-right text-navy-500"><th className="p-2">العملة</th><th className="p-2">شراء</th><th className="p-2">بيع</th><th className="p-2">المعتمد (المتوسط)</th><th className="p-2">التاريخ</th><th className="p-2">المصدر</th></tr></thead>
            <tbody>
              {rates.map((r) => (
                <tr key={r.currency} className="border-t border-navy-100">
                  <td className="p-2">{CURRENCY_LABEL[r.currency] ?? r.currency} ({r.currency})</td>
                  <td className="p-2" dir="ltr">{Number(r.buy)}</td><td className="p-2" dir="ltr">{Number(r.sell)}</td>
                  <td className="p-2 font-semibold" dir="ltr">{Number(r.egp_per_unit)}</td><td className="p-2">{r.rate_date}</td><td className="p-2 text-xs">{r.source}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
      <section className="panel space-y-3">
        <h2 className="text-lg">تحديث الأسعار</h2>
        <p className="hint">أدخل سعري الشراء والبيع لكل عملة كما في نشرة البنك المركزي المصري. يُسجَّل كل تحديث في سجل التدقيق، ولا يغيّر نزاعًا قائمًا: كل نزاع يحتفظ بالسعر الذي حُوّلت به قيمته.</p>
        <FormAction action={setFxRates} submitLabel="اعتماد الأسعار" variant="gold" className="space-y-3" confirmText="ستُطبَّق هذه الأسعار على النزاعات الجديدة. هل أنت متأكد؟">
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {FOREIGN.map((c) => (
              <fieldset key={c} className="rounded-md border border-navy-100 p-3">
                <legend className="px-1 text-sm font-semibold">{CURRENCY_LABEL[c]} ({c})</legend>
                <label className="label" htmlFor={`${c}_buy`}>شراء</label>
                <input id={`${c}_buy`} name={`${c}_buy`} type="number" step="0.0001" min="0.0001" required dir="ltr" className="input" defaultValue={Number(by[c]?.buy ?? '')} />
                <label className="label" htmlFor={`${c}_sell`}>بيع</label>
                <input id={`${c}_sell`} name={`${c}_sell`} type="number" step="0.0001" min="0.0001" required dir="ltr" className="input" defaultValue={Number(by[c]?.sell ?? '')} />
              </fieldset>
            ))}
          </div>
          <div className="grid gap-3 sm:grid-cols-2">
            <div><label className="label" htmlFor="date">تاريخ النشرة</label><input id="date" name="date" type="date" required className="input" defaultValue={date} /></div>
            <div><label className="label" htmlFor="source">المصدر</label><input id="source" name="source" required minLength={5} className="input" defaultValue="البنك المركزي المصري: نشرة أسعار الصرف" /></div>
          </div>
        </FormAction>
      </section>
    </div>
  )
}
