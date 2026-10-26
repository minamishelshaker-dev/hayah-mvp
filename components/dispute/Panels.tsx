import Link from 'next/link'
import FormAction from '@/components/FormAction'
import CopyLink from '@/components/CopyLink'
import ScheduleForm from '@/components/ScheduleForm'
import UploadDocument from '@/components/UploadDocument'
import DocumentActions from '@/components/DocumentActions'
import { DOC_TYPE_LABEL, formatDate, formatEgp, formatSize } from '@/lib/labels'
import {
  mediatorRespond, partyRespond, proposeMediator, resendInvitation, saveSettlement,
  reopenSettlement, scheduleSession, signSettlement, submitSettlement,
} from '@/app/(app)/disputes/actions'
import type { Assignment, Dispute, DocumentRow, SessionRow, Settlement, Signature } from '@/lib/types'

export type Names = Record<string, string>
export type MediatorOption = { id: string; name: string; bio: string | null; specializations: string[]; years_experience: number | null }
export const nm = (names: Names, id: string | null | undefined) => (id && names[id]) || 'مستخدم'

const ASSIGNMENT_LABEL: Record<string, string> = {
  proposed: 'بانتظار موافقة الطرف الآخر',
  approved: 'بانتظار قبول الوسيط',
  accepted: 'قبل المهمة',
  rejected: 'مرفوض',
  ended: 'انسحب من الملف',
}

export function InvitationPanel({ disputeId, link, email, expiresAt }: { disputeId: string; link: string; email: string; expiresAt: string }) {
  const expired = new Date(expiresAt).getTime() < Date.now()
  return (
    <section className="panel space-y-3 border-gold">
      <h2 className="text-lg">دعوة الطرف الثاني</h2>
      {expired ? (
        <p role="alert" className="rounded bg-red-50 p-2 text-sm font-semibold text-red-800">انتهت صلاحية الدعوة. أصدر رابطًا جديدًا أدناه أو اسحب النزاع من قسم الإنهاء.</p>
      ) : (
        <p className="hint">
          الدعوة موجّهة إلى <span dir="ltr" className="font-semibold">{email}</span> وتنتهي في {formatDate(expiresAt)}، ولا يقبلها إلا حساب مسجَّل بنفس البريد.
          إن لم يصل البريد، أرسل له هذا الرابط مباشرة:
        </p>
      )}
      {!expired && <CopyLink link={link} />}
      <FormAction action={resendInvitation.bind(null, disputeId)} submitLabel="إصدار رابط جديد" variant="ghost" className="flex flex-wrap items-end gap-2 border-t border-navy-100 pt-3">
        <div className="min-w-0 flex-1">
          <label className="label" htmlFor="resend-email">بريد آخر للطرف الثاني (اختياري، لتصحيح بريد خاطئ)</label>
          <input id="resend-email" name="email" type="email" dir="ltr" className="input" />
        </div>
      </FormAction>
    </section>
  )
}

export function MediatorPanel({ dispute, assignments, mediators, names, viewerId, isParty }: {
  dispute: Dispute; assignments: Assignment[]; mediators: MediatorOption[]; names: Names; viewerId: string; isParty: boolean
}) {
  const open = assignments.some((a) => a.status === 'proposed' || a.status === 'approved')
  const canPropose = isParty && ['accepted', 'mediator_selection'].includes(dispute.status) && !open

  if (dispute.mediator_id) {
    return (
      <section className="panel">
        <h2 className="mb-1 text-lg">الوسيط</h2>
        <p className="font-semibold">{nm(names, dispute.mediator_id)}</p>
        <p className="hint">اتفق عليه الطرفان وقبل المهمة.</p>
      </section>
    )
  }

  return (
    <section className="panel space-y-4">
      <div>
        <h2 className="text-lg">اختيار الوسيط</h2>
        <p className="hint">يقترح أحد الطرفين وسيطًا، ويوافق عليه الطرف الآخر، ثم يقبل الوسيط المهمة.</p>
      </div>

      {assignments.map((a) => (
        <div key={a.id} className="rounded-md border border-navy-100 p-3">
          <p className="font-semibold">{nm(names, a.mediator_id)} <span className="hint">— {ASSIGNMENT_LABEL[a.status]}</span></p>
          {a.status === 'proposed' && isParty && viewerId !== a.proposed_by && (
            <div className="mt-2 flex gap-2">
              <FormAction action={partyRespond.bind(null, dispute.id, a.id, true)} submitLabel="أوافق على هذا الوسيط" variant="gold" />
              <FormAction action={partyRespond.bind(null, dispute.id, a.id, false)} submitLabel="أرفض" variant="danger" />
            </div>
          )}
          {a.status === 'approved' && viewerId === a.mediator_id && (
            <div className="mt-2 flex gap-2">
              <FormAction action={mediatorRespond.bind(null, dispute.id, a.id, true)} submitLabel="أقبل المهمة" variant="gold" />
              <FormAction action={mediatorRespond.bind(null, dispute.id, a.id, false)} submitLabel="أعتذر" variant="danger" />
            </div>
          )}
        </div>
      ))}

      {canPropose && (
        <div className="space-y-3">
          <h3 className="text-sm">وسطاء تعتمدهم المنصة</h3>
          <p className="hint">يظهر هنا من رقّته الإدارة إلى وسيط بعد التحقق من هويته. الاعتماد قرار إداري لا شهادة مهنية.</p>
          {mediators.length === 0 && <p className="hint">لا يوجد وسطاء معتمدون بعد. يضيفهم المدير من صفحة المستخدمين.</p>}
          {mediators.map((m) => (
            <div key={m.id} className="flex flex-col justify-between gap-2 rounded-md border border-navy-100 p-3 sm:flex-row sm:items-center">
              <div>
                <p className="font-semibold">{m.name}</p>
                <p className="hint">
                  {m.years_experience ? `${m.years_experience} سنة خبرة` : ''}
                  {m.specializations.length ? ` — ${m.specializations.join('، ')}` : ''}
                </p>
                {m.bio && <p className="hint">{m.bio}</p>}
              </div>
              <FormAction action={proposeMediator.bind(null, dispute.id, m.id)} submitLabel="اقتراح" variant="ghost" />
            </div>
          ))}
        </div>
      )}
    </section>
  )
}

export function DocumentsPanel({ docs, names, canUpload, disputeId }: {
  docs: DocumentRow[]; names: Names; canUpload: boolean; disputeId: string
}) {
  return (
    <section className="panel">
      <h2 className="text-lg">المستندات</h2>
      <p className="hint mb-3">تُحسب بصمة SHA-256 لكل ملف على الخادم عند رفعه، ولا يمكن تعديل المستند أو حذفه بعد ذلك.</p>
      {docs.length === 0 && <p className="hint">لم يُرفع أي مستند بعد.</p>}
      <ul className="divide-y divide-navy-100">
        {docs.map((d) => (
          <li key={d.id} className="flex flex-col justify-between gap-2 py-3 sm:flex-row sm:items-center">
            <div className="min-w-0">
              <p className="truncate font-semibold">{d.file_name}</p>
              <p className="hint">
                {DOC_TYPE_LABEL[d.document_type]} — {formatSize(d.file_size)} — رفعه {nm(names, d.uploaded_by)} — {formatDate(d.created_at)}
              </p>
              <p dir="ltr" className="truncate text-start font-mono text-xs text-navy-500">SHA-256: {d.sha256_hash}</p>
            </div>
            <DocumentActions docId={d.id} />
          </li>
        ))}
      </ul>
      {canUpload && <UploadDocument disputeId={disputeId} />}
    </section>
  )
}

export function SessionsPanel({ dispute, sessions, canJoin, isMediator }: {
  dispute: Dispute; sessions: SessionRow[]; canJoin: boolean; isMediator: boolean
}) {
  const canSchedule = isMediator && ['active', 'settlement_draft'].includes(dispute.status)
  return (
    <section className="panel">
      <h2 className="mb-3 text-lg">جلسات الوساطة</h2>
      {sessions.length === 0 && <p className="hint mb-3">لم تُجدوَل جلسات بعد.</p>}
      <ul className="mb-3 divide-y divide-navy-100">
        {sessions.map((s) => (
          <li key={s.id} className="flex items-center justify-between py-2">
            <span className={s.status === 'cancelled' ? 'text-navy-500 line-through' : ''}>الجلسة {s.session_number.toLocaleString('ar-EG')} — {formatDate(s.scheduled_at)} ({s.duration_minutes.toLocaleString('ar-EG')} دقيقة){s.status === 'cancelled' ? ' — ملغاة' : ''}</span>
            {canJoin && s.status !== 'cancelled' && <Link href={`/sessions/${s.id}`} className="btn btn-primary !py-1">دخول الجلسة</Link>}
          </li>
        ))}
      </ul>
      {canSchedule && <ScheduleForm action={scheduleSession.bind(null, dispute.id)} />}
    </section>
  )
}

function defaultSettlementText(d: Dispute, names: Names) {
  return `اتفاق تسوية

رقم النزاع: ${d.dispute_number}
الطرف الأول (مقدّم النزاع): ${nm(names, d.claimant_id)}
الطرف الثاني: ${nm(names, d.respondent_id)}
الوسيط: ${nm(names, d.mediator_id)}
قيمة النزاع محل الوساطة: ${formatEgp(d.dispute_value_egp)}

أولًا: تمهيد
نشأ بين الطرفين نزاع حول: ${d.title}. وقد اتفقا على عرضه على الوساطة بحضور الوسيط المذكور أعلاه، وانتهيا بعد جلسات الوساطة إلى التسوية الودية وفق البنود التالية.

ثانيًا: شروط التسوية
١- [يكتب الوسيط التزامات الطرف الأول]
٢- [يكتب الوسيط التزامات الطرف الثاني]
٣- [مبلغ التسوية وطريقة وموعد السداد إن وُجد]

ثالثًا: إبراء وتنازل
[تحدد صيغة الإبراء ونطاقه بحسب ما اتفق عليه الطرفان]

رابعًا: السرية والقانون الواجب التطبيق
يلتزم الطرفان بسرية ما دار في الوساطة. [يحدد القانون الواجب التطبيق وجهة الاختصاص]

خامسًا: الإقرار
أقرّ كل طرف بقراءة هذا الاتفاق وفهمه وموافقته عليه بإرادة حرة.`
}

export function SettlementPanel({ dispute, settlement, signatures, names, viewerId, isMediator }: {
  dispute: Dispute; settlement: Settlement | null; signatures: Signature[]; names: Names; viewerId: string; isMediator: boolean
}) {
  const isClaimant = viewerId === dispute.claimant_id
  const isRespondent = viewerId === dispute.respondent_id
  const editable = isMediator && ['active', 'settlement_draft'].includes(dispute.status) && (!settlement || settlement.status === 'draft')
  const hasSigned = signatures.some((s) => s.user_id === viewerId)
  const canReopen = isMediator && settlement?.status === 'pending_signatures' && signatures.length === 0 && ['active', 'settlement_draft'].includes(dispute.status)
  const canSign = (isClaimant || isRespondent) && settlement?.status === 'pending_signatures' && !hasSigned

  if (!settlement && !editable) return null


  return (
    <section className="panel space-y-4">
      <div>
        <h2 className="text-lg">اتفاق التسوية</h2>
        {settlement && (
          <p className="hint">
            {settlement.status === 'draft' && `مسودة — النسخة ${settlement.version.toLocaleString('ar-EG')}`}
            {settlement.status === 'pending_signatures' && 'مفتوح للتوقيع — النص مغلق ولا يمكن تعديله'}
            {settlement.status === 'signed' && 'موقَّع من الطرفين'}
          </p>
        )}
      </div>

      {editable ? (
        <>
          <FormAction action={saveSettlement.bind(null, dispute.id)} submitLabel="حفظ المسودة" variant="ghost" resetOnSuccess={false}>
            <label className="label" htmlFor="content">نص الاتفاق (نموذج استرشادي يجب مراجعته قانونيًا)</label>
            <p className="hint mb-2">استبدل كل نص بين أقواس [..] قبل فتح الاتفاق للتوقيع؛ لن يُقبل مع بقائها.</p>
            <textarea
              id="content" name="content" rows={18} required minLength={50}
              defaultValue={settlement?.content ?? defaultSettlementText(dispute, names)}
              className="input mb-3 leading-8"
            />
          </FormAction>
          {settlement && (
            <div className="border-t border-navy-100 pt-3">
              <p className="hint mb-2">بعد فتح الاتفاق للتوقيع لا يمكن تعديله، وسيتلقى الطرفان النص المحفوظ آخر مرة.</p>
              <FormAction
                action={submitSettlement.bind(null, dispute.id)}
                submitLabel="فتح الاتفاق للتوقيع"
                variant="gold"
                confirmText="سيُغلق نص الاتفاق ويُفتح للتوقيع. هل أنت متأكد؟"
              />
            </div>
          )}
        </>
      ) : (
        settlement && (
          <div className="whitespace-pre-wrap rounded-md border border-navy-100 bg-navy-50 p-4 leading-8">{settlement.content}</div>
        )
      )}

      {settlement && (
        <p dir="ltr" className="break-all text-start font-mono text-xs text-navy-500">Content SHA-256: {settlement.content_hash}</p>
      )}

      {settlement && settlement.status !== 'draft' && (
        <div className="space-y-1 border-t border-navy-100 pt-3">
          {([['claimant', dispute.claimant_id, 'مقدّم النزاع'], ['respondent', dispute.respondent_id, 'الطرف الثاني']] as const).map(([role, uid, label]) => {
            const sig = signatures.find((s) => s.party_role === role)
            return (
              <p key={role} className="text-sm">
                <span className="font-semibold">{label} ({nm(names, uid)}):</span>{' '}
                {sig ? <span className="text-emerald-700">وقّع في {formatDate(sig.signed_at)}</span> : <span className="text-gold-700">لم يوقّع بعد</span>}
              </p>
            )
          })}
        </div>
      )}

      {canReopen && (
        <FormAction action={reopenSettlement.bind(null, dispute.id)} submitLabel="إعادة فتح المسودة للتعديل" variant="ghost" className="space-y-2 border-t border-navy-100 pt-3"
          confirmText="ستعود المسودة قابلة للتعديل ويُشعَر الطرفان. لا يمكن ذلك بعد أن يوقّع أحدهما.">
          <p className="hint">لم يوقّع أحد بعد، فيمكنك تصحيح النص. بعد أول توقيع يُقفل النص نهائيًا.</p>
        </FormAction>
      )}

      {canSign && (
        <FormAction action={signSettlement.bind(null, dispute.id)} submitLabel="أوقّع على الاتفاق" variant="gold" className="space-y-3 border-t border-navy-100 pt-3">
          <input type="hidden" name="expected_hash" value={settlement?.content_hash ?? ''} />
          <label className="flex items-start gap-2 text-sm">
            <input type="checkbox" name="agree" className="mt-1.5" />
            <span>قرأت نص الاتفاق أعلاه كاملًا، وأوافق عليه، وأقرّ بأن توقيعي الإلكتروني يعبّر عن إرادتي.</span>
          </label>
          <div>
            <label className="label" htmlFor="password">كلمة المرور (لتأكيد هويتك عند التوقيع)</label>
            <input id="password" name="password" type="password" autoComplete="current-password" dir="ltr" className="input max-w-xs" />
          </div>
        </FormAction>
      )}
    </section>
  )
}
