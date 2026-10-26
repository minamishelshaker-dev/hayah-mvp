import Link from 'next/link'
import FormAction from '@/components/FormAction'
import ScheduleForm from '@/components/ScheduleForm'
import DueForm from '@/components/arbitration/DueForm'
import UploadArbDocument from '@/components/arbitration/UploadArbDocument'
import ArbDocumentActions from '@/components/arbitration/ArbDocumentActions'
import {
  ARB_DOC_LABEL, ARB_OUTCOME_LABEL, ARB_STATUS_LABEL, ARB_STATUS_TONE, PARTY_LABEL, STEP_KIND_LABEL,
  formatDate, formatEgp, formatSize,
} from '@/lib/labels'
import {
  acceptArbRules, arbitratorRespond, arbitratorWithdraw, closeProceedings, confirmArbAgreement, extendStep, issueAward,
  openArbAgreement, partyRespondArbitrator, proposeArbitrator, reopenArbAgreement, respondEscalation, retryArbAttestation,
  saveAwardDraft, saveArbAgreement, scheduleHearing, setStep, signArbAgreement, signAward,
  submitStatement, terminateArbitration, withdrawArbitration,
} from '@/app/(app)/arbitrations/actions'
import type { ArbAgreement, ArbAssignment, ArbAward, ArbDocument, ArbHearing, ArbStep, ArbSubmission, Arbitration } from '@/lib/types'

type Names = Record<string, string>
export type Neutral = { id: string; name: string; bio: string | null; specializations: string[]; years_experience: number | null }
const nm = (names: Names, id: string | null | undefined) => (id && names[id]) || 'مستخدم'
const PRE_SEAT = ['proposed', 'agreement', 'selection']

const Reason = ({ id, label }: { id: string; label: string }) => (
  <div className="mb-3">
    <label className="label" htmlFor={id}>{label}</label>
    <textarea id={id} name="reason" rows={2} maxLength={500} className="input" />
  </div>
)

// ------------------------------------------------------------------ gate: nothing of the file before the rules are accepted
export function ArbGate({ arbId, number, doc, role, status, assignmentId }: {
  arbId: string; number: string; role: string; status: string; assignmentId?: string | null
  doc: { id: string; version: number; title: string; body: string; is_placeholder: boolean }
}) {
  return (
    <div className="mx-auto max-w-2xl space-y-4">
      <div>
        <p dir="ltr" className="text-start text-sm font-semibold text-gold-700">{number}</p>
        <h1 className="text-2xl">{doc.title}</h1>
        <p className="hint">النسخة {doc.version.toLocaleString('ar-EG')} — لا يُفتح ملف التحكيم قبل قبول هذه القواعد. يُسجَّل قبولك بوقته وعنوان اتصالك.</p>
      </div>
      {doc.is_placeholder && (
        <p role="alert" className="rounded bg-red-50 p-3 text-sm font-semibold text-red-800">
          هذا نص مؤقت للتجربة التقنية فقط، ولا يجوز استخدام المنصة في تحكيم حقيقي قبل استبداله بالنص المعتمد.
        </p>
      )}
      <div className="panel max-h-96 overflow-auto whitespace-pre-wrap leading-8">{doc.body}</div>
      <FormAction action={acceptArbRules.bind(null, arbId, doc.id)} submitLabel="أقبل قواعد التحكيم" variant="gold" className="panel space-y-3">
        <label className="flex items-start gap-2 text-sm">
          <input type="checkbox" name="agree" className="mt-1.5" />
          <span>قرأت قواعد استخدام المنصة في التحكيم كاملة وأوافق عليها، وأفهم أن المنصة أداة لإدارة الإجراءات وتوثيقها وليست جهة تحكيم.</span>
        </label>
      </FormAction>
      {(role === 'claimant' || role === 'respondent') && PRE_SEAT.includes(status) && (
        <FormAction action={withdrawArbitration.bind(null, arbId)} submitLabel="لا أقبل: الانسحاب من التحكيم" variant="danger" className="panel space-y-2"
          confirmText="سيُغلق الملف نهائيًا وتُسجَّل النتيجة. هل أنت متأكد؟">
          <p className="hint">التحكيم هنا اتفاقي. إن لم توافق فيمكنك الانسحاب الآن.</p>
        </FormAction>
      )}
      {role === 'arbitrator_candidate' && assignmentId && (
        <FormAction action={arbitratorRespond.bind(null, arbId, assignmentId, false)} submitLabel="أعتذر عن المهمة" variant="danger" className="panel space-y-2"
          confirmText="سيُرفض طلب التعيين. هل أنت متأكد؟">
          <p className="hint">إن لم تقبل القواعد أو لا تستطيع تولي الملف فاعتذر هنا.</p>
        </FormAction>
      )}
    </div>
  )
}

export function EndedNotice({ number, outcome }: { number: string; outcome: string | null }) {
  return (
    <div className="panel mx-auto max-w-xl space-y-2">
      <p dir="ltr" className="text-start text-sm font-semibold text-gold-700">{number}</p>
      <h1 className="text-xl">انتهى هذا الملف</h1>
      <p>{outcome ? ARB_OUTCOME_LABEL[outcome] : 'أُغلق الملف.'} ولا يتطلب منك أي إجراء.</p>
    </div>
  )
}

// ------------------------------------------------------------------ header
const STEPS = ['الطلب', 'اتفاق التحكيم', 'المحكّم', 'الإجراءات', 'الحكم']
const STEP_INDEX: Record<string, number> = { proposed: 0, agreement: 1, selection: 2, active: 3, deliberation: 4, closed: 4, cancelled: 0 }

export function ArbHeader({ arb, names, rulesAccepted }: { arb: Arbitration; names: Names; rulesAccepted: string[] }) {
  const step = STEP_INDEX[arb.status] ?? 0
  const ended = ['closed', 'cancelled'].includes(arb.status)
  return (
    <>
      <header className="panel space-y-3">
        <div className="flex flex-wrap items-start justify-between gap-2">
          <div>
            <p dir="ltr" className="text-start text-sm font-semibold text-gold-700">{arb.arb_number}</p>
            <h1 className="text-2xl">{arb.title}</h1>
          </div>
          <span className={`badge ${ARB_STATUS_TONE[arb.status]}`}>{ARB_STATUS_LABEL[arb.status]}</span>
        </div>
        <p className="whitespace-pre-wrap">{arb.summary}</p>
        <p className="hint">{formatEgp(arb.dispute_value_egp)} — فُتح في {formatDate(arb.created_at)}</p>
        <p className="text-sm">
          <span className="font-semibold">مقدّم الطلب:</span> {nm(names, arb.claimant_id)}{'  '}
          <span className="font-semibold">الطرف الآخر:</span> {nm(names, arb.respondent_id)}{'  '}
          <span className="font-semibold">المحكّم:</span> {arb.arbitrator_id ? nm(names, arb.arbitrator_id) : 'لم يُعيَّن بعد'}
        </p>
        {arb.prior_clause && <p className="hint">أفاد مقدّم الطلب بوجود شرط تحكيم سابق في العقد. هذا إقرار منه تسجّله المنصة ولا تحكم فيه.</p>}
        {arb.source_dispute_id && (
          <p className="hint">
            مرتبط بملف وساطة سابق، لكن لم يُنقل منه شيء إلى هذا الملف. <Link className="underline" href={`/disputes/${arb.source_dispute_id}`}>فتح ملف الوساطة</Link>
          </p>
        )}
        <p className="text-sm">
          <span className="font-semibold">قبول قواعد التحكيم:</span>{' '}
          {([['مقدّم الطلب', arb.claimant_id], ['الطرف الآخر', arb.respondent_id], ['المحكّم', arb.arbitrator_id]] as const)
            .filter(([, id]) => id).map(([l, id]) => `${l} ${rulesAccepted.includes(id as string) ? '✓' : '…'}`).join('، ')}
        </p>
        <ol className="flex flex-wrap gap-x-5 gap-y-1 border-t border-navy-100 pt-3 text-sm">
          {STEPS.map((s, i) => (
            <li key={s} className={i < step || (ended && arb.status === 'closed') ? 'font-semibold text-gold-700' : i === step ? 'font-bold' : 'text-navy-500'}>
              {(i + 1).toLocaleString('ar-EG')}. {s}{i < step ? ' ✓' : ''}
            </li>
          ))}
        </ol>
      </header>
      {ended && (
        <section className="panel border-navy-500 bg-navy-50">
          <h2 className="text-lg">{arb.status === 'closed' ? 'الملف مغلق' : 'الملف ملغى'}</h2>
          <p className="font-semibold">{arb.outcome ? ARB_OUTCOME_LABEL[arb.outcome] : '—'}{arb.closed_at ? ` — ${formatDate(arb.closed_at)}` : ''}</p>
          {arb.outcome_reason && <p className="hint">السبب المذكور: {arb.outcome_reason}</p>}
          <p className="hint">الملف للقراءة فقط.</p>
        </section>
      )}
    </>
  )
}

// ------------------------------------------------------------------ stage 1: the request
export function ProposedPanel({ arb, isRespondent }: { arb: Arbitration; isRespondent: boolean }) {
  return (
    <section className="panel space-y-3">
      <h2 className="text-lg">طلب التحكيم</h2>
      <p className="hint">التحكيم اتفاقي: لا يبدأ إلا بموافقة الطرف الآخر. ولم يُنقل إلى هذا الملف شيء مما قيل أو عُرض في الوساطة.</p>
      {isRespondent ? (
        <div className="flex flex-wrap gap-3">
          <FormAction action={respondEscalation.bind(null, arb.id, true)} submitLabel="أوافق على التحكيم" variant="gold" />
          <FormAction action={respondEscalation.bind(null, arb.id, false)} submitLabel="أرفض" variant="danger" className="space-y-2" confirmText="سيُلغى الطلب وتُسجَّل النتيجة. هل أنت متأكد؟">
            <Reason id="decl-reason" label="سبب الرفض (اختياري)" />
          </FormAction>
        </div>
      ) : (
        <p className="font-semibold">بانتظار رد الطرف الآخر.</p>
      )}
    </section>
  )
}

// ------------------------------------------------------------------ stage 2: the arbitration agreement
// Two routes. (1) Draft and sign ON the platform: both parties sign the same text with their password; the platform then seals it
// with its own Ed25519 signature. (2) Sign outside the platform and upload the scan; both confirm the same file.
// Whichever route gets its first signature/confirmation closes the other.
const SignFields = ({ label }: { label: string }) => (
  <div className="space-y-2">
    <label className="flex items-start gap-2 text-sm">
      <input type="checkbox" name="agree" className="mt-1" /> <span>{label}</span>
    </label>
    <div>
      <label className="label" htmlFor="sign-password">كلمة المرور (لتأكيد هويتك عند التوقيع)</label>
      <input id="sign-password" name="password" type="password" autoComplete="current-password" dir="ltr" className="input max-w-xs" />
    </div>
  </div>
)

const SealInfo = ({ signature, keyId, arbId, kind }: { signature: string | null; keyId: string | null; arbId: string; kind: 'agreement' | 'award' }) => (
  <div className="space-y-2 rounded-md border border-navy-100 bg-navy-50 p-3 text-sm">
    {signature ? (
      <>
        <p className="font-semibold">ختم المنصة الرقمي (Ed25519) <span dir="ltr" className="font-mono text-xs">key {keyId}</span></p>
        <p className="hint">يثبت أن هذا السجل صدر عن المنصة ولم يتغير بعد صدوره. يمكن فحصه خارج المنصة بالمفتاح العام (<span dir="ltr">/api/record-key</span>) وسكربت <span dir="ltr">scripts/verify-record.mjs</span>. وهو ليس توقيعًا معتمدًا من ITIDA.</p>
        <a className="font-semibold text-gold-700 underline" href={`/api/arb-instruments/${arbId}?kind=${kind}`}>تنزيل السجل الموقَّع (JSON)</a>
      </>
    ) : (
      <>
        <p className="font-semibold text-red-700">لم يُختم هذا السجل بختم المنصة بعد.</p>
        <FormAction action={retryArbAttestation.bind(null, arbId, kind)} submitLabel="ختم المنصة" variant="ghost" resetOnSuccess={false} />
      </>
    )}
  </div>
)

export function AgreementPanel({ arb, docs, confirmations, names, viewerId, isParty, agreement, signers, template }: {
  arb: Arbitration; docs: ArbDocument[]; confirmations: { user_id: string; document_id: string; confirmed_at: string }[]
  names: Names; viewerId: string; isParty: boolean; agreement: ArbAgreement | null
  signers: { user_id: string; signed_at: string }[]; template: string
}) {
  const agr = docs.filter((d) => d.doc_type === 'arbitration_agreement')
  const iConfirmed = confirmations.some((c) => c.user_id === viewerId)
  const iSigned = signers.some((x) => x.user_id === viewerId)
  const platformStarted = !!agreement && agreement.status !== 'draft'
  const scanStarted = confirmations.length > 0

  if (agreement?.status === 'signed') {
    return (
      <section className="panel space-y-3">
        <h2 className="text-lg">اتفاق التحكيم <span className="hint">— وُقّع على المنصة</span></h2>
        <div className="whitespace-pre-wrap rounded-md border border-navy-100 bg-navy-50 p-4 leading-8">{agreement.body}</div>
        <p dir="ltr" className="break-all text-start font-mono text-[11px] text-navy-500">Text SHA-256: {agreement.body_hash}</p>
        <p className="text-sm">{signers.map((x) => `${nm(names, x.user_id)} وقّع في ${formatDate(x.signed_at)}`).join('، ')}</p>
        <SealInfo signature={agreement.platform_signature} keyId={agreement.signing_key_id} arbId={arb.id} kind="agreement" />
      </section>
    )
  }

  return (
    <section className="panel space-y-4">
      <h2 className="text-lg">اتفاق التحكيم</h2>
      <p className="rounded bg-gold-100 p-3 text-sm">
        يمكن توقيع اتفاق التحكيم <b>على المنصة</b> (يوقّع الطرفان النص نفسه بكلمة المرور، وتختمه المنصة)، أو <b>خارجها</b> برفع مسح الاتفاق الموقَّع.
        التوقيع على المنصة توقيع إلكتروني بسيط وليس توقيعًا معتمدًا من ITIDA؛ راجع محاميك في قبول المحكمة له قبل الاعتماد عليه. المنصة لا تحكم في صحة الاتفاق.
      </p>

      {!scanStarted && (
        <div className="space-y-3 rounded-lg border border-navy-100 p-4">
          <h3 className="text-base">المسار الأول: التوقيع على المنصة</h3>
          {!agreement && !isParty && <p className="hint">لم يُصَغ نص الاتفاق بعد.</p>}
          {isParty && (!agreement || agreement.status === 'draft') && (
            <>
              <FormAction action={saveArbAgreement.bind(null, arb.id)} submitLabel="حفظ المسودة" variant="ghost" resetOnSuccess={false}>
                <label className="label" htmlFor="agr-body">نص الاتفاق{agreement ? ` (النسخة ${agreement.version})` : ' (نموذج استرشادي يحتاج مراجعة محامٍ)'}</label>
                <p className="hint mb-2">استبدل كل نص بين أقواس [..]؛ لا يُفتح الاتفاق للتوقيع وفيه أقواس. يستطيع أي من الطرفين تعديل المسودة قبل فتحها للتوقيع.</p>
                <textarea id="agr-body" name="body" rows={20} required minLength={200} defaultValue={agreement?.body ?? template} className="input mb-3 leading-8" />
              </FormAction>
              {agreement && (
                <FormAction action={openArbAgreement.bind(null, arb.id)} submitLabel="فتح الاتفاق للتوقيع" variant="gold"
                  confirmText="بعد الفتح لا يُعدَّل النص إلا بإعادة فتحه قبل أي توقيع. هل أنت متأكد؟" />
              )}
            </>
          )}
          {agreement?.status === 'open' && (
            <>
              <div className="whitespace-pre-wrap rounded-md border border-navy-100 bg-navy-50 p-4 leading-8">{agreement.body}</div>
              <p dir="ltr" className="break-all text-start font-mono text-[11px] text-navy-500">Text SHA-256: {agreement.body_hash}</p>
              <p className="text-sm">{signers.length ? signers.map((x) => `${nm(names, x.user_id)} وقّع في ${formatDate(x.signed_at)}`).join('، ') : 'لم يوقّع أحد بعد.'}</p>
              {isParty && !iSigned && (
                <FormAction action={signArbAgreement.bind(null, arb.id)} submitLabel="أوقّع الاتفاق" variant="gold" className="space-y-3"
                  confirmText="بتوقيعك تقرّ بالنص المعروض أعلاه وتلتزم به. هل أنت متأكد؟">
                  <input type="hidden" name="expected_hash" value={agreement.body_hash} />
                  <SignFields label="قرأت نص اتفاق التحكيم كاملًا وأوافق عليه، وأوقّعه إلكترونيًا عبر المنصة." />
                </FormAction>
              )}
              {isParty && iSigned && <p className="hint">وقّعت. بانتظار توقيع الطرف الآخر.</p>}
              {isParty && signers.length === 0 && (
                <FormAction action={reopenArbAgreement.bind(null, arb.id)} submitLabel="إعادة فتح النص للتعديل" variant="ghost" />
              )}
            </>
          )}
        </div>
      )}

      {!platformStarted && (
        <details className="rounded-lg border border-navy-100 p-4" open={scanStarted || agr.length > 0}>
          <summary className="cursor-pointer font-semibold">المسار الثاني: اتفاق موقَّع خارج المنصة (رفع المسح)</summary>
          <div className="mt-3 space-y-3">
            <p className="hint">يرفع أحد الطرفين مسح الاتفاق الموقَّع ويؤكد الطرفان <b>الملف نفسه</b>. إن أكّد أحدهما ملفًا فلا يؤكد الآخر إلا الملف نفسه.</p>
            {agr.length === 0 && <p className="hint">لم يُرفع اتفاق التحكيم بعد.</p>}
            <ul className="divide-y divide-navy-100">
              {agr.map((d) => (
                <li key={d.id} className="space-y-2 py-3">
                  <p className="font-semibold">{d.file_name} <span className="hint">— رفعه {nm(names, d.uploaded_by)} — {formatSize(d.file_size)} — {formatDate(d.created_at)}</span></p>
                  <p dir="ltr" className="break-all text-start font-mono text-[11px] text-navy-500">SHA-256: {d.sha256_hash}</p>
                  <ArbDocumentActions docId={d.id} />
                  <p className="text-sm">
                    {confirmations.filter((c) => c.document_id === d.id).map((c) => `${nm(names, c.user_id)} أكّد في ${formatDate(c.confirmed_at)}`).join('، ') || 'لم يؤكده أحد بعد'}
                  </p>
                  {isParty && !iConfirmed && (!scanStarted || confirmations.some((c) => c.document_id === d.id)) && (
                    <FormAction action={confirmArbAgreement.bind(null, arb.id, d.id)} submitLabel="أقرّ وأؤكد" variant="gold" className="space-y-1" confirmText="أقرّ بأن هذا الملف هو اتفاق التحكيم الموقَّع بيني وبين الطرف الآخر. هل أنت متأكد؟">
                      <p className="hint">بتأكيدك تقرّ بأن هذا الملف هو اتفاق التحكيم الموقَّع بينك وبين الطرف الآخر.</p>
                    </FormAction>
                  )}
                </li>
              ))}
            </ul>
            {isParty && confirmations.length === 0 && <UploadArbDocument arbId={arb.id} docType="arbitration_agreement" label="مسح اتفاق التحكيم الموقَّع" />}
          </div>
        </details>
      )}
    </section>
  )
}

// ------------------------------------------------------------------ stage 3: choosing the arbitrator
export function SelectionPanel({ arb, assignments, directory, names, viewerId, isParty }: {
  arb: Arbitration; assignments: ArbAssignment[]; directory: Neutral[]; names: Names; viewerId: string; isParty: boolean
}) {
  const open = assignments.some((a) => a.status === 'proposed' || a.status === 'approved')
  const label: Record<string, string> = { proposed: 'بانتظار موافقة الطرف الآخر', approved: 'بانتظار قبول المحكّم', accepted: 'قبل المهمة', rejected: 'مرفوض', ended: 'انسحب' }
  const mine = assignments.find((a) => a.status === 'approved' && a.arbitrator_id === viewerId)
  return (
    <section className="panel space-y-4">
      <div>
        <h2 className="text-lg">اختيار المحكّم</h2>
        <p className="hint">محكّم منفرد يتفق عليه الطرفان. لا يجوز لمن عمل وسيطًا في الوساطة السابقة أن يكون محكّمًا في هذا الملف، ولا يوجد استثناء من ذلك في المنصة.</p>
      </div>
      {assignments.map((a) => (
        <div key={a.id} className="rounded-md border border-navy-100 p-3">
          <p className="font-semibold">{nm(names, a.arbitrator_id)} <span className="hint">— {label[a.status]}</span></p>
          {a.status === 'proposed' && isParty && viewerId !== a.proposed_by && (
            <div className="mt-2 flex gap-2">
              <FormAction action={partyRespondArbitrator.bind(null, arb.id, a.id, true)} submitLabel="أوافق على هذا المحكّم" variant="gold" />
              <FormAction action={partyRespondArbitrator.bind(null, arb.id, a.id, false)} submitLabel="أرفض" variant="danger" />
            </div>
          )}
        </div>
      ))}
      {mine && (
        <FormAction action={arbitratorRespond.bind(null, arb.id, mine.id, true)} submitLabel="أقبل المهمة وأقدّم إقرار الاستقلال" variant="gold" className="space-y-3 border-t border-navy-100 pt-3"
          confirmText="سيُسجَّل إقرارك ويُعرض على الطرفين. هل أنت متأكد؟">
          <label className="label" htmlFor="disclosure">إقرار الاستقلال والحياد (إلزامي)</label>
          <p className="hint mb-2">اذكر أي علاقة سابقة أو حالية بالطرفين أو بوكلائهما أو بالنزاع، أو أقرّ بعدمها. يراه الطرفان.</p>
          <textarea id="disclosure" name="disclosure" rows={5} required minLength={30} className="input" />
        </FormAction>
      )}
      {isParty && !open && (
        <div className="space-y-3">
          <h3 className="text-sm">محكّمون تعتمدهم المنصة</h3>
          <p className="hint">يظهر هنا من رقّته الإدارة إلى محكّم بعد التحقق من هويته. الاعتماد قرار إداري لا شهادة مهنية.</p>
          {directory.length === 0 && <p className="hint">لا يوجد محكّمون معتمدون بعد.</p>}
          {directory.map((m) => (
            <div key={m.id} className="flex flex-col justify-between gap-2 rounded-md border border-navy-100 p-3 sm:flex-row sm:items-center">
              <div>
                <p className="font-semibold">{m.name}</p>
                <p className="hint">{m.years_experience ? `${m.years_experience} سنة خبرة` : ''}{m.specializations.length ? ` — ${m.specializations.join('، ')}` : ''}</p>
                {m.bio && <p className="hint">{m.bio}</p>}
              </div>
              <FormAction action={proposeArbitrator.bind(null, arb.id, m.id)} submitLabel="اقتراح" variant="ghost" />
            </div>
          ))}
        </div>
      )}
    </section>
  )
}

// ------------------------------------------------------------------ stage 4: the procedure
export function ProcedurePanel({ arb, steps, submissions, docs, hearings, names, viewerId, isArbitrator, isParty }: {
  arb: Arbitration; steps: ArbStep[]; submissions: ArbSubmission[]; docs: ArbDocument[]; hearings: ArbHearing[]
  names: Names; viewerId: string; isArbitrator: boolean; isParty: boolean
}) {
  const active = arb.status === 'active'
  const myRole = viewerId === arb.claimant_id ? 'claimant' : viewerId === arb.respondent_id ? 'respondent' : null
  const docName = (id: string) => docs.find((d) => d.id === id)
  const myExhibits = docs.filter((d) => d.doc_type === 'exhibit' && d.uploaded_by === viewerId)
  const now = Date.now()
  return (
    <section className="panel space-y-4">
      <h2 className="text-lg">سير الإجراءات</h2>
      {steps.length === 0 && <p className="hint">لم يحدد المحكّم جدولًا إجرائيًا بعد.</p>}
      <ol className="space-y-3">
        {steps.map((st) => {
          const sub = submissions.find((x) => x.step_id === st.id)
          const overdue = !sub && new Date(st.due_at).getTime() < now
          return (
            <li key={st.id} className="rounded-md border border-navy-100 p-3">
              <p className="font-semibold">
                {st.seq.toLocaleString('ar-EG')}. {STEP_KIND_LABEL[st.kind]} — على {PARTY_LABEL[st.party]}
                <span className={`hint ${overdue ? '!text-red-700 font-semibold' : ''}`}> — الموعد {formatDate(st.due_at)}{overdue ? ' (انقضى)' : ''}</span>
              </p>
              {st.note && <p className="hint">{st.note}</p>}
              {sub ? (
                <div className="mt-2 space-y-1">
                  <p className="text-sm font-semibold">{nm(names, sub.submitted_by)} قدّم في {formatDate(sub.submitted_at)}{sub.late ? <span className="badge ms-2 bg-red-100 text-red-800">بعد الموعد</span> : null}</p>
                  <p className="whitespace-pre-wrap rounded bg-navy-50 p-3 leading-8">{sub.body}</p>
                  {sub.document_ids.map((id) => {
                    const d = docName(id)
                    return d ? <div key={id} className="flex items-center justify-between gap-2 text-sm"><span>📎 {d.file_name}</span><ArbDocumentActions docId={d.id} /></div> : null
                  })}
                </div>
              ) : (
                <>
                  {active && myRole === st.party && (
                    <FormAction action={submitStatement.bind(null, arb.id, st.id)} submitLabel="تقديم المذكرة" variant="gold" className="mt-3 space-y-3" confirmText="لا تُعدَّل المذكرة بعد التقديم. هل أنت متأكد؟">
                      <label className="label" htmlFor={`body-${st.id}`}>نص المذكرة</label>
                      <textarea id={`body-${st.id}`} name="body" rows={6} required minLength={20} className="input leading-8" />
                      {myExhibits.length > 0 && (
                        <fieldset className="text-sm">
                          <legend className="label">المرفقات (ما رفعتَه أنت)</legend>
                          {myExhibits.map((d) => (
                            <label key={d.id} className="flex items-center gap-2"><input type="checkbox" name="documents" value={d.id} /> {d.file_name}</label>
                          ))}
                        </fieldset>
                      )}
                    </FormAction>
                  )}
                  {active && isArbitrator && (
                    <div className="mt-3 border-t border-navy-100 pt-3">
                      <p className="hint mb-1">تمديد الموعد</p>
                      <DueForm action={extendStep.bind(null, arb.id, st.id)} submitLabel="تمديد" />
                    </div>
                  )}
                </>
              )}
            </li>
          )
        })}
      </ol>
      {active && isArbitrator && (
        <div className="border-t border-navy-100 pt-3">
          <h3 className="mb-2 text-sm">إضافة موعد إجرائي</h3>
          <DueForm action={setStep.bind(null, arb.id)} submitLabel="إضافة" full />
        </div>
      )}
      {active && isParty && (
        <div className="border-t border-navy-100 pt-3">
          <h3 className="text-sm">مرفقاتي</h3>
          <p className="hint">ارفع المستندات هنا ثم أرفقها بمذكرتك عند تقديمها.</p>
          {myExhibits.map((d) => <p key={d.id} className="text-sm">📎 {d.file_name}</p>)}
          <UploadArbDocument arbId={arb.id} docType="exhibit" label="مرفق جديد" />
        </div>
      )}

      <div className="border-t border-navy-100 pt-3">
        <h3 className="mb-2 text-sm">جلسات التحكيم</h3>
        {hearings.length === 0 && <p className="hint mb-2">لم تُجدوَل جلسات.</p>}
        <ul className="mb-3 divide-y divide-navy-100">
          {hearings.map((h) => (
            <li key={h.id} className="flex items-center justify-between py-2">
              <span className={h.status === 'cancelled' ? 'text-navy-500 line-through' : ''}>
                الجلسة {h.number.toLocaleString('ar-EG')} — {formatDate(h.scheduled_at)} ({h.duration_minutes.toLocaleString('ar-EG')} دقيقة){h.status === 'cancelled' ? ' — ملغاة' : ''}
              </span>
              {h.status !== 'cancelled' && (isParty || isArbitrator) && <Link href={`/hearings/${h.id}`} className="btn btn-primary !py-1">دخول الجلسة</Link>}
            </li>
          ))}
        </ul>
        {active && isArbitrator && <ScheduleForm action={scheduleHearing.bind(null, arb.id)} />}
      </div>

      {active && isArbitrator && (
        <FormAction action={closeProceedings.bind(null, arb.id)} submitLabel="إقفال الإجراءات وبدء المداولة" variant="danger" className="border-t border-navy-100 pt-3"
          confirmText="لن تُقبل مذكرات ولا جلسات بعد الإقفال وتُلغى الجلسات القادمة. هل أنت متأكد؟" />
      )}
    </section>
  )
}

// ------------------------------------------------------------------ stage 5: the award
// Two routes: sign it ON the platform (password + second factor, sealed by the platform key), or sign on paper and record the scan.
export function AwardPanel({ arb, award, docs, isArbitrator }: { arb: Arbitration; award: ArbAward | null; docs: ArbDocument[]; isArbitrator: boolean }) {
  const signedDocs = docs.filter((d) => d.doc_type === 'award_signed')
  if (arb.status === 'deliberation' && isArbitrator) {
    return (
      <section className="panel space-y-4">
        <div>
          <h2 className="text-lg">الحكم</h2>
          <p className="rounded bg-gold-100 p-3 text-sm">
            تحفظ المنصة مسودتك سرًّا (لا يراها الطرفان ولا المدير). يمكنك <b>توقيع الحكم على المنصة</b> (كلمة المرور + الخطوة الثانية، وتختمه المنصة)، أو <b>توقيعه ورقيًا</b> ورفع مسحه.
            التوقيع على المنصة توقيع إلكتروني بسيط وليس معتمدًا من ITIDA؛ والإيداع والتنفيذ يتمان وفق القانون خارج المنصة، فتأكّد من قبول المحكمة المختصة له وإلا فاختر المسار الورقي.
          </p>
        </div>
        <FormAction action={saveAwardDraft.bind(null, arb.id)} submitLabel="حفظ المسودة" variant="ghost" resetOnSuccess={false}>
          <label className="label" htmlFor="draft">نص الحكم (النسخة {award?.version ?? 0})</label>
          <p className="hint mb-2">استبدل كل نص بين أقواس [..] قبل الإصدار؛ لن يُقبل معها.</p>
          <textarea id="draft" name="draft" rows={18} required minLength={100} defaultValue={award?.draft_text ?? ''} className="input mb-3 leading-8" />
        </FormAction>
        {award && (
          <>
            <p><Link className="font-semibold text-gold-700 underline" href={`/arbitrations/${arb.id}/award`}>نسخة للطباعة</Link></p>
            <div className="space-y-3 rounded-lg border border-navy-100 p-4">
              <h3 className="text-base">المسار الأول: توقيع الحكم على المنصة</h3>
              <p dir="ltr" className="break-all text-start font-mono text-[11px] text-navy-500">Text SHA-256: {award.draft_hash}</p>
              <p className="hint">تأكد من حفظ آخر نسخة من النص؛ يُوقَّع النص المحفوظ بالبصمة أعلاه.</p>
              <FormAction action={signAward.bind(null, arb.id)} submitLabel="أوقّع الحكم وأصدره" variant="gold" className="space-y-3"
                confirmText="سيُغلق الملف نهائيًا ويطّلع الطرفان على الحكم، ولا يُعدَّل بعد التوقيع. هل أنت متأكد؟">
                <div>
                  <label className="label" htmlFor="award_date_p">تاريخ الحكم</label>
                  <input id="award_date_p" name="award_date" type="date" required className="input max-w-xs" />
                </div>
                <input type="hidden" name="expected_hash" value={award.draft_hash} />
                <SignFields label="هذا النص هو حكمي، وأوقّعه إلكترونيًا عبر المنصة." />
              </FormAction>
            </div>
            <details className="rounded-lg border border-navy-100 p-4">
              <summary className="cursor-pointer font-semibold">المسار الثاني: حكم موقَّع ورقيًا (رفع المسح)</summary>
              <div className="mt-3">
                <UploadArbDocument arbId={arb.id} docType="award_signed" label="مسح الحكم الموقَّع" />
                {signedDocs.length > 0 && (
                  <FormAction action={issueAward.bind(null, arb.id)} submitLabel="تسجيل صدور الحكم وإغلاق الملف" variant="gold" className="mt-3 space-y-3"
                    confirmText="سيُغلق الملف نهائيًا ويطّلع الطرفان على الحكم. هل أنت متأكد؟">
                    <p className="hint">ملاحظة: لا تتحقق المنصة من تطابق المسح مع النص المحفوظ؛ المسار الأول يربط التوقيع ببصمة النص نفسه.</p>
                    <div className="grid gap-3 sm:grid-cols-2">
                      <div>
                        <label className="label" htmlFor="signed_doc">الملف الموقَّع</label>
                        <select id="signed_doc" name="signed_doc" className="input" required>
                          {signedDocs.map((d) => <option key={d.id} value={d.id}>{d.file_name}</option>)}
                        </select>
                      </div>
                      <div>
                        <label className="label" htmlFor="award_date">تاريخ الحكم</label>
                        <input id="award_date" name="award_date" type="date" required className="input" />
                      </div>
                    </div>
                  </FormAction>
                )}
              </div>
            </details>
          </>
        )}
      </section>
    )
  }
  if (award?.status === 'issued') {
    const signed = docs.find((d) => d.id === award.signed_document_id)
    const platform = award.signing_mode === 'platform'
    return (
      <section className="panel space-y-3">
        <h2 className="text-lg">الحكم</h2>
        <p className="hint">
          {platform
            ? `وقّع المحكّم الحكم على المنصة بتاريخ ${award.award_date}. النص المعروض هو النص الموقَّع.`
            : `سجّل المحكّم صدور الحكم بتاريخ ${award.award_date}. هذه نسخة المنصة من النص؛ المرجع هو الحكم الموقَّع الذي رفعه المحكّم.`}
        </p>
        <div className="whitespace-pre-wrap rounded-md border border-navy-100 bg-navy-50 p-4 leading-8">{award.draft_text}</div>
        <p dir="ltr" className="break-all text-start font-mono text-[11px] text-navy-500">Text SHA-256: {award.draft_hash}</p>
        {platform && <SealInfo signature={award.platform_signature} keyId={award.signing_key_id} arbId={arb.id} kind="award" />}
        {signed && (
          <div className="flex flex-wrap items-center justify-between gap-2 border-t border-navy-100 pt-3">
            <span className="font-semibold">الحكم الموقَّع: {signed.file_name}</span>
            <ArbDocumentActions docId={signed.id} />
          </div>
        )}
        <p><Link className="font-semibold text-gold-700 underline" href={`/arbitrations/${arb.id}/award`}>نسخة للطباعة</Link></p>
      </section>
    )
  }
  return null
}

// ------------------------------------------------------------------ documents
export function ArbDocumentsPanel({ docs, names }: { docs: ArbDocument[]; names: Names }) {
  const list = docs.filter((d) => d.doc_type !== 'arbitration_agreement')
  if (list.length === 0) return null
  return (
    <section className="panel">
      <h2 className="mb-2 text-lg">المستندات</h2>
      <ul className="divide-y divide-navy-100">
        {list.map((d) => (
          <li key={d.id} className="flex flex-col justify-between gap-2 py-3 sm:flex-row sm:items-center">
            <div className="min-w-0">
              <p className="truncate font-semibold">{d.file_name}</p>
              <p className="hint">{ARB_DOC_LABEL[d.doc_type]} — {formatSize(d.file_size)} — رفعه {nm(names, d.uploaded_by)} — {formatDate(d.created_at)}</p>
              <p dir="ltr" className="truncate text-start font-mono text-xs text-navy-500">SHA-256: {d.sha256_hash}</p>
            </div>
            <ArbDocumentActions docId={d.id} />
          </li>
        ))}
      </ul>
    </section>
  )
}

// ------------------------------------------------------------------ ways out
export function ArbLifecycle({ arb, isParty, isArbitrator }: { arb: Arbitration; isParty: boolean; isArbitrator: boolean }) {
  const canWithdraw = isParty && PRE_SEAT.includes(arb.status)
  const inProceedings = ['active', 'deliberation'].includes(arb.status)
  if (!(canWithdraw || (isArbitrator && inProceedings))) return null
  return (
    <details className="panel">
      <summary className="cursor-pointer font-semibold">الانسحاب أو إنهاء الإجراءات</summary>
      <div className="mt-4 space-y-5">
        {canWithdraw && (
          <FormAction action={withdrawArbitration.bind(null, arb.id)} submitLabel="الانسحاب من التحكيم" variant="danger" confirmText="سيُغلق الملف نهائيًا وتُسجَّل النتيجة. هل أنت متأكد؟">
            <p className="hint mb-2">يمكنك الانسحاب قبل تعيين المحكّم. بعد تعيينه ينهي المحكّم وحده الإجراءات.</p>
            <Reason id="w-reason" label="السبب (اختياري، يراه الطرف الآخر)" />
          </FormAction>
        )}
        {isArbitrator && inProceedings && (
          <>
            <FormAction action={terminateArbitration.bind(null, arb.id)} submitLabel="إنهاء الإجراءات دون حكم" variant="danger" confirmText="ستُغلق الإجراءات نهائيًا دون حكم. هل أنت متأكد؟">
              <p className="hint mb-2">للمحكّم إنهاء الإجراءات (كتنازل المدّعي أو تسوية الطرفين). تُسجَّل النتيجة «أنهى المحكّم الإجراءات».</p>
              <Reason id="t-reason" label="السبب (يُسجَّل)" />
            </FormAction>
            <FormAction action={arbitratorWithdraw.bind(null, arb.id)} submitLabel="انسحاب من الملف" variant="danger"
              confirmText="ستفقد وصولك إلى الملف وتُحذف مسودة الحكم ولا تنتقل إلى من يخلفك، ويختار الطرفان محكّمًا آخر. هل أنت متأكد؟">
              <p className="hint mb-2">يعود الملف إلى اختيار المحكّم.</p>
              <Reason id="aw-reason" label="السبب (اختياري)" />
            </FormAction>
          </>
        )}
      </div>
    </details>
  )
}
