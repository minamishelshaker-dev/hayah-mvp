import FormAction from '@/components/FormAction'
import { acceptAgreement, mediatorRespond, withdrawDispute } from '@/app/(app)/disputes/actions'

export default function AgreementGate({ disputeId, disputeNumber, doc, role, status, assignmentId }: {
  disputeId: string
  disputeNumber: string
  role?: string
  status?: string
  assignmentId?: string | null
  doc: { id: string; version: number; title: string; body: string; is_placeholder: boolean }
}) {
  return (
    <div className="mx-auto max-w-2xl space-y-4">
      <div>
        <p dir="ltr" className="text-start text-sm font-semibold text-gold-700">{disputeNumber}</p>
        <h1 className="text-2xl">{doc.title}</h1>
        <p className="hint">النسخة {doc.version.toLocaleString('ar-EG')} — لا يُفتح ملف النزاع قبل قبول هذه الاتفاقية. يُسجَّل قبولك بوقته وعنوان اتصالك.</p>
      </div>
      {doc.is_placeholder && (
        <p role="alert" className="rounded bg-red-50 p-3 text-sm font-semibold text-red-800">
          هذا نص مؤقت للتجربة التقنية فقط، ولا يجوز استخدام المنصة في حالة حقيقية قبل استبداله بالنص المعتمد.
        </p>
      )}
      <div className="panel max-h-96 overflow-auto whitespace-pre-wrap leading-8">{doc.body}</div>
      <FormAction action={acceptAgreement.bind(null, disputeId, doc.id)} submitLabel="أقبل اتفاقية الوساطة" variant="gold" className="panel space-y-3">
        <label className="flex items-start gap-2 text-sm">
          <input type="checkbox" name="agree" className="mt-1.5" />
          <span>قرأت اتفاقية الوساطة كاملة وأوافق على أحكامها، وأفهم أن الوساطة اختيارية وسرّية.</span>
        </label>
      </FormAction>

      {(role === 'claimant' || role === 'respondent') && ['invited', 'accepted', 'mediator_selection'].includes(status ?? '') && (
        <FormAction action={withdrawDispute.bind(null, disputeId)} submitLabel={role === 'claimant' ? 'لا أقبل: سحب النزاع' : 'لا أقبل: الانسحاب من الوساطة'} variant="danger" className="panel space-y-2" confirmText="سيُلغى الملف نهائيًا وتُسجَّل النتيجة. هل أنت متأكد؟">
          <p className="hint">الوساطة اختيارية. إن لم توافق على هذه الاتفاقية فيمكنك الانسحاب الآن.</p>
        </FormAction>
      )}
      {role === 'mediator_candidate' && assignmentId && (
        <FormAction action={mediatorRespond.bind(null, disputeId, assignmentId, false)} submitLabel="أعتذر عن المهمة" variant="danger" className="panel space-y-2" confirmText="سيُرفض طلب التعيين. هل أنت متأكد؟">
          <p className="hint">إن لم تقبل الاتفاقية أو لا تستطيع تولي الملف فاعتذر هنا.</p>
        </FormAction>
      )}
    </div>
  )
}
