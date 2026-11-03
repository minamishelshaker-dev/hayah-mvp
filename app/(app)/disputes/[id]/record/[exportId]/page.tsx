import Link from 'next/link'
import { notFound } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import PrintButton from '@/components/PrintButton'
import { DOC_TYPE_LABEL, OUTCOME_LABEL, STATUS_LABEL, TYPE_LABEL, describeEvent, formatDate, formatEgp, formatSize } from '@/lib/labels'
import type { RecordEnvelope } from '@/lib/types'

const ROLE_AR: Record<string, string> = { claimant: 'مقدّم النزاع', respondent: 'الطرف الثاني' }
const H2 = 'mb-2 border-b border-navy-100 pb-1 text-lg'
const MONO = 'break-all text-start font-mono text-[11px] text-navy-500'

export default async function RecordViewPage(props: { params: Promise<{ id: string; exportId: string }> }) {
  const params = await props.params
  const supabase = await createClient()
  const { data } = await supabase
    .from('record_exports').select('id, dispute_id, record, record_hash, signature, signing_key_id, signed_at').eq('id', params.exportId).maybeSingle()
  if (!data || data.dispute_id !== params.id) notFound()
  const rec = data.record as RecordEnvelope
  const r = rec.data
  const base = process.env.NEXT_PUBLIC_APP_URL ?? 'http://localhost:3000'

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-2 print:hidden">
        <Link href={`/disputes/${params.id}/record`} className="hint underline">← المحاضر</Link>
        <div className="flex gap-2">
          <a href={`/api/records/${data.id}`} className="btn btn-ghost">تنزيل JSON</a>
          <a href={`/api/records/${data.id}?format=bundle`} className="btn btn-ghost">تنزيل مع التوقيع</a>
          <PrintButton />
        </div>
      </div>

      <article className="space-y-6 rounded-lg border border-navy-100 bg-white p-6 text-sm leading-7 print:rounded-none print:border-0 print:p-0">
        <header className="border-b-2 border-gold pb-3">
          <p className="text-xl font-extrabold">حياة<span className="text-gold">.</span></p>
          <h1 className="text-2xl">محضر موثّق لملف وساطة</h1>
          <p>
            النزاع <span dir="ltr" className="font-semibold">{r.dispute.number}</span> — صدر في {formatDate(rec.issued_at)} عن {rec.issued_by.name}
          </p>
          <p className="font-semibold">بصمة المحضر (SHA-256):</p>
          <p dir="ltr" className={MONO}>{data.record_hash}</p>
          {data.signature ? (
            <p className="text-xs">
              التوقيع الرقمي: Ed25519 — مفتاح <span dir="ltr" className="font-mono">{data.signing_key_id}</span> — {formatDate(data.signed_at as string)}.
              يمكن فحصه دون الرجوع إلى المنصة بالمفتاح العام (<span dir="ltr">{base}/api/record-key</span>) وملف «تنزيل مع التوقيع».
            </p>
          ) : (
            <p className="text-xs text-navy-500">هذا المحضر غير موقَّع رقميًا (التوقيع غير مضبوط على الخادم أو تعذّر). يبقى التحقق ممكنًا عبر صفحة التحقق.</p>
          )}
        </header>

        <section>
          <h2 className={H2}>بيانات النزاع</h2>
          <p className="font-bold">{r.dispute.title}</p>
          <p className="whitespace-pre-wrap">{r.dispute.description}</p>
          <p className="hint">{TYPE_LABEL[r.dispute.type]} — {formatEgp(r.dispute.value_egp)} — الحالة وقت الإصدار: {STATUS_LABEL[r.dispute.status] ?? r.dispute.status} — سُجّل في {formatDate(r.dispute.created_at)}</p>
          {r.dispute.outcome && <p className="font-semibold">نتيجة الملف: {OUTCOME_LABEL[r.dispute.outcome] ?? r.dispute.outcome}{r.dispute.outcome_reason ? ` — السبب المذكور: ${r.dispute.outcome_reason}` : ''}</p>}
          <p>مقدّم النزاع: {r.parties.claimant ?? '—'} — الطرف الثاني: {r.parties.respondent ?? '—'} — الوسيط: {r.parties.mediator ?? '—'}</p>
        </section>

        <section>
          <h2 className={H2}>قبول الوثائق القانونية</h2>
          {r.consents.length === 0 && <p className="hint">لا يوجد.</p>}
          <ul className="space-y-1">
            {r.consents.map((c, i) => (
              <li key={i}>
                {c.name} قبل «{c.document}» (النسخة {c.version.toLocaleString('ar-EG')}) في {formatDate(c.accepted_at)}
                {c.ip ? <> — IP: <span dir="ltr">{c.ip}</span></> : null}
                <span dir="ltr" className={`${MONO} block`}>{c.document_hash}</span>
              </li>
            ))}
          </ul>
        </section>

        <section>
          <h2 className={H2}>المستندات</h2>
          {r.documents.length === 0 && <p className="hint">لا يوجد.</p>}
          <ul className="space-y-2">
            {r.documents.map((x, i) => (
              <li key={i}>
                <span className="font-semibold">{x.file_name}</span> — {DOC_TYPE_LABEL[x.type]} — {formatSize(x.size)} — رفعه {x.uploaded_by} في {formatDate(x.uploaded_at)}
                <span dir="ltr" className={`${MONO} block`}>SHA-256: {x.sha256}</span>
              </li>
            ))}
          </ul>
        </section>

        <section>
          <h2 className={H2}>الجلسات</h2>
          {r.sessions.length === 0 && <p className="hint">لا يوجد.</p>}
          <ul>
            {r.sessions.map((s) => (
              <li key={s.number}>الجلسة {s.number.toLocaleString('ar-EG')} — {formatDate(s.scheduled_at)} — {s.duration_minutes.toLocaleString('ar-EG')} دقيقة — {s.status === 'scheduled' ? 'مجدولة' : s.status}</li>
            ))}
          </ul>
        </section>

        {r.settlement && (
          <section>
            <h2 className={H2}>اتفاق التسوية (النسخة {r.settlement.version.toLocaleString('ar-EG')})</h2>
            <div className="whitespace-pre-wrap rounded-md border border-navy-100 bg-navy-50 p-3 leading-8 print:bg-white">{r.settlement.content}</div>
            <p dir="ltr" className={MONO}>Content SHA-256: {r.settlement.content_hash}</p>
            <h3 className="mt-3 font-bold">التوقيعات</h3>
            {r.settlement.signatures.length === 0 && <p className="hint">لم يوقّع أحد بعد.</p>}
            <ul>
              {r.settlement.signatures.map((g, i) => (
                <li key={i}>
                  {ROLE_AR[g.party_role]}: {g.name} — {formatDate(g.signed_at)}{g.ip ? <> — IP: <span dir="ltr">{g.ip}</span></> : null}
                  {g.content_hash === r.settlement!.content_hash ? ' — البصمة مطابقة لنص الاتفاق' : ' — تحذير: البصمة لا تطابق نص الاتفاق'}
                </li>
              ))}
            </ul>
          </section>
        )}

        <section>
          <h2 className={H2}>السجل الزمني</h2>
          <ol className="space-y-1">
            {r.timeline.map((t) => (
              <li key={t.seq}>
                <span dir="ltr" className="font-mono text-xs text-navy-500">#{t.seq}</span>{' '}
                {describeEvent({ event_type: t.event_type, new_state: t.state, previous_state: { status: t.state.prev_status } })}
                {' — '}{t.actor} — {formatDate(t.at)}{' '}
                <span dir="ltr" className="font-mono text-[11px] text-navy-500">{t.row_hash.slice(0, 10)}</span>
              </li>
            ))}
          </ol>
          <p className={`mt-2 font-semibold ${r.chain_check.ok ? 'text-emerald-700' : 'text-red-700'}`}>
            {r.chain_check.ok
              ? `فحص سلامة السجل وقت الإصدار: سليم (${r.chain_check.checked.toLocaleString('ar-EG')} سجلًا أُعيد حساب بصمة كل منها والتحقق من ارتباطه بالسجل السابق له).`
              : `تحذير: اختلّ السجل عند الحدث رقم ${r.chain_check.first_bad_seq}.`}
          </p>
        </section>

        <footer className="space-y-1 border-t border-navy-100 pt-3 text-xs text-navy-500">
          <p>
            للتحقق من صدور هذا المحضر عن المنصة: افتح <span dir="ltr">{base}/verify</span> وأدخل البصمة أعلاه أو ارفع ملف JSON المرافق. يثبت التحقق صدور المحضر وسلامة محتواه كما صدر، ولا يثبت صحة وقائع النزاع.
          </p>
          <p>
            المحضر صادر آليًا ويعكس بيانات الملف وقت الإصدار فقط. لا يُغني عن التوقيع المرخّص ولا يُعدّ حكمًا أو تقريرًا قضائيًا. تُحجب الخانة الأخيرة من عناوين IP في المحاضر الصادرة للأطراف حماية لخصوصية بعضهم.
          </p>
        </footer>
      </article>
    </div>
  )
}
