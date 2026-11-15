import Link from 'next/link'
import FormAction from '@/components/FormAction'
import { proposeEscalation } from '@/app/(app)/arbitrations/actions'
import { ARB_STATUS_LABEL } from '@/lib/labels'
import ValueFields from '@/components/dispute/ValueFields'
import type { RateLite } from '@/lib/fees'
import type { Dispute } from '@/lib/types'

export default function EscalationPanel({ dispute, isParty, linked, rates }: {
  dispute: Dispute; isParty: boolean; linked: { id: string; arb_number: string; status: string }[]; rates: (RateLite & { rate_date?: string })[]
}) {
  const eligible = isParty && (['active', 'settlement_draft'].includes(dispute.status) || (dispute.status === 'closed' && dispute.outcome === 'no_settlement'))
  const hasOpen = linked.some((l) => l.status !== 'cancelled')
  if (linked.length === 0 && !eligible) return null
  return (
    <section className="panel space-y-3">
      <h2 className="text-lg">التصعيد إلى التحكيم</h2>
      {linked.map((l) => (
        <p key={l.id} className="text-sm">
          ملف التحكيم <Link className="font-semibold text-gold-700 underline" href={`/arbitrations/${l.id}`}><span dir="ltr">{l.arb_number}</span></Link> — {ARB_STATUS_LABEL[l.status]}
        </p>
      ))}
      {eligible && !hasOpen && (
        <details>
          <summary className="cursor-pointer font-semibold">طلب تحكيم جديد بعد هذه الوساطة</summary>
          <div className="mt-3 space-y-3">
            <ul className="list-inside list-disc text-sm text-navy-500">
              <li>التحكيم اتفاقي: لا يبدأ إلا بموافقة الطرف الآخر وبتوقيع اتفاق تحكيم خارج المنصة.</li>
              <li>يُفتح ملف <b>جديد ومنفصل</b>، ولا يُنقل إليه شيء مما قيل أو عُرض أو صيغ في الوساطة. تكتب الطلب من جديد.</li>
              <li>لا يجوز لوسيط هذا الملف أن يكون محكّمًا فيه.</li>
            </ul>
            <FormAction action={proposeEscalation.bind(null, dispute.id)} submitLabel="إرسال طلب التحكيم" variant="gold" className="space-y-3" resetOnSuccess={false}
              confirmText="سيُرسَل الطلب إلى الطرف الآخر ويُفتح ملف تحكيم جديد. هل أنت متأكد؟">
              <div>
                <label className="label" htmlFor="esc-title">عنوان الطلب</label>
                <input id="esc-title" name="title" required minLength={5} className="input" />
              </div>
              <div>
                <label className="label" htmlFor="esc-summary">ملخص الطلب (30 حرفًا على الأقل)</label>
                <textarea id="esc-summary" name="summary" required minLength={30} rows={5} className="input" />
              </div>
              <ValueFields rates={rates} amountName="value" currencyName="currency" showFee={false} idPrefix="esc"
                defaultCurrency={dispute.value_currency ?? 'EGP'} defaultAmount={dispute.value_amount ?? dispute.dispute_value_egp} />
              <label className="flex items-start gap-2 text-sm">
                <input type="checkbox" name="prior_clause" className="mt-1.5" />
                <span>العقد يتضمن شرط تحكيم سابقًا (إقرار مني تسجّله المنصة ولا تحكم فيه)</span>
              </label>
            </FormAction>
          </div>
        </details>
      )}
    </section>
  )
}
