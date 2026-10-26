import FormAction from '@/components/FormAction'
import { closeDispute, mediatorWithdraw, withdrawDispute } from '@/app/(app)/disputes/actions'
import { OUTCOME_LABEL, formatDate } from '@/lib/labels'
import type { Dispute } from '@/lib/types'

const PRE_MEDIATION = ['invited', 'accepted', 'mediator_selection']
const IN_MEDIATION = ['active', 'settlement_draft']

const Reason = ({ id, label }: { id: string; label: string }) => (
  <div className="mb-3">
    <label className="label" htmlFor={id}>{label}</label>
    <textarea id={id} name="reason" rows={2} maxLength={500} className="input" />
  </div>
)

export function EndedBanner({ dispute }: { dispute: Pick<Dispute, 'status' | 'outcome' | 'outcome_reason' | 'closed_at'> }) {
  if (!['closed', 'cancelled'].includes(dispute.status)) return null
  return (
    <section className="panel border-navy-500 bg-navy-50">
      <h2 className="text-lg">{dispute.status === 'closed' ? 'الملف مغلق' : 'الملف ملغى'}</h2>
      <p className="font-semibold">{dispute.outcome ? OUTCOME_LABEL[dispute.outcome] : '—'}{dispute.closed_at ? ` — ${formatDate(dispute.closed_at)}` : ''}</p>
      {dispute.outcome_reason && <p className="hint">السبب المذكور: {dispute.outcome_reason}</p>}
      <p className="hint">الملف للقراءة فقط: لا مستندات ولا جلسات ولا تعديل بعد الإغلاق.</p>
    </section>
  )
}

export function EndedNotice({ number, outcome }: { number: string; outcome: string | null }) {
  return (
    <div className="panel mx-auto max-w-xl space-y-2">
      <p dir="ltr" className="text-start text-sm font-semibold text-gold-700">{number}</p>
      <h1 className="text-xl">انتهى هذا الملف</h1>
      <p>{outcome ? OUTCOME_LABEL[outcome] : 'أُغلق الملف.'} ولا يتطلب منك أي إجراء.</p>
    </div>
  )
}

export default function Lifecycle({ dispute, isParty, isMediator, isAdmin, settlementLocked }: {
  dispute: Dispute; isParty: boolean; isMediator: boolean; isAdmin: boolean; settlementLocked: boolean
}) {
  const s = dispute.status
  const canWithdraw = isParty && PRE_MEDIATION.includes(s)
  const canMediatorLeave = isMediator && IN_MEDIATION.includes(s) && !settlementLocked
  const canEnd = (isParty || isMediator || isAdmin) && IN_MEDIATION.includes(s)
  const canCloseSettled = (isParty || isMediator || isAdmin) && s === 'signed'
  if (!(canWithdraw || canMediatorLeave || canEnd || canCloseSettled)) return null

  return (
    <details className="panel">
      <summary className="cursor-pointer font-semibold">إنهاء الوساطة أو الانسحاب</summary>
      <div className="mt-4 space-y-5">
        {canWithdraw && (
          <FormAction action={withdrawDispute.bind(null, dispute.id)} submitLabel="سحب النزاع" variant="danger" confirmText="سيُلغى الملف نهائيًا وتُسجَّل النتيجة. هل أنت متأكد؟">
            <p className="hint mb-2">الوساطة اختيارية؛ يحق لك الانسحاب قبل أن يتسلّم وسيط الملف.</p>
            <Reason id="w-reason" label="السبب (اختياري، يراه الطرف الآخر والوسيط)" />
          </FormAction>
        )}
        {canMediatorLeave && (
          <FormAction action={mediatorWithdraw.bind(null, dispute.id)} submitLabel="انسحاب من الملف" variant="danger" confirmText="ستفقد وصولك إلى الملف وتُلغى جلساتك القادمة، ويختار الطرفان وسيطًا آخر. هل أنت متأكد؟">
            <p className="hint mb-2">يعود الملف إلى اختيار الوسيط. لا يمكن الانسحاب بعد فتح الاتفاق للتوقيع.</p>
            <Reason id="m-reason" label="السبب (اختياري)" />
          </FormAction>
        )}
        {canEnd && (
          <FormAction action={closeDispute.bind(null, dispute.id, 'no_settlement')} submitLabel="إنهاء الوساطة دون تسوية" variant="danger" confirmText="ستُغلق الوساطة نهائيًا دون تسوية وتُلغى الجلسات القادمة. هل أنت متأكد؟">
            <p className="hint mb-2">يحق لأي طرف إنهاء الوساطة في أي وقت. تُسجَّل النتيجة «انتهت دون تسوية».</p>
            <Reason id="e-reason" label="السبب (اختياري)" />
          </FormAction>
        )}
        {canCloseSettled && (
          <FormAction action={closeDispute.bind(null, dispute.id, 'settled')} submitLabel="إغلاق الملف بعد التسوية" variant="gold" confirmText="سيُغلق الملف ويصبح للقراءة فقط. هل أنت متأكد؟" />
        )}
      </div>
    </details>
  )
}
