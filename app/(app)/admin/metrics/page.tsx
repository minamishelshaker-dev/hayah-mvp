import { createClient } from '@/lib/supabase/server'
import { formatDuration } from '@/lib/utils'
import { formatEgp } from '@/lib/labels'

type Metrics = {
  outcomes: { settled: number; no_settlement: number; withdrawn: number; declined: number; open: number }
  funnel: { created: number; accepted: number; active: number; draft: number; signed: number }
  median_secs: { to_accept: number | null; to_mediator: number | null; to_signature: number | null; total: number | null }
  value_total: number; value_settled: number
  sessions_total: number; sessions_per_settled: number | null
  documents_total: number; invitations_sent: number; invitations_accepted: number
  placeholder_docs: number; verified_mediators: number; users_total: number
}

const pct = (a: number, b: number) => (b > 0 ? `${Math.round((a / b) * 100).toLocaleString('ar-EG')}٪` : '—')
const num = (n: number) => n.toLocaleString('ar-EG')

export default async function MetricsPage() {
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('admin_metrics')
  const { data: sec } = await supabase.rpc('security_status')
  const { data: arbData } = await supabase.rpc('arb_metrics')
  const arb = arbData as { total: number; outcomes: Record<string, number>; escalated_from_mediation: number; mediations_without_settlement: number; late_statements: number; by_status: Record<string, number> } | null
  if (error || !data) return <p role="alert" className="font-semibold text-red-700">تعذّر حساب المؤشرات: {error?.message}</p>
  const m = data as Metrics

  const readiness = [
    { ok: Boolean(process.env.RECORD_SIGNING_PRIVATE_KEY), text: 'مفتاح توقيع المحاضر مضبوط (RECORD_SIGNING_PRIVATE_KEY)، وإلا تصدر المحاضر بلا توقيع رقمي' },
    { ok: sec?.mfa_required === true, text: 'التحقق بخطوتين مفروض على المدير والوسطاء (app_settings.require_mfa)' },
    { ok: m.placeholder_docs === 0, text: 'النصوص القانونية المعتمدة منشورة (لا نصوص مؤقتة)' },
    { ok: m.verified_mediators >= 2, text: `وسيطان معتمدان على الأقل (الحالي: ${num(m.verified_mediators)})` },
    { ok: Boolean(process.env.DAILY_API_KEY), text: 'مفتاح Daily.co مضبوط (فيديو حقيقي)' },
    { ok: Boolean(process.env.RESEND_API_KEY), text: 'مفتاح Resend مضبوط (بريد الدعوات)' },
    { ok: Boolean(process.env.SUPABASE_SERVICE_ROLE_KEY), text: 'مفتاح خدمة Supabase مضبوط (مطلوب لتسجيل المستندات والتوقيع وقبول الاتفاقيات وغرف الفيديو)' },
    { ok: Boolean(process.env.CRON_SECRET && process.env.ANCHOR_EMAIL && process.env.RESEND_API_KEY), text: 'نقطة التحقق اليومية للسجل مضبوطة (CRON_SECRET وANCHOR_EMAIL)' },
    { ok: !(process.env.NEXT_PUBLIC_APP_URL ?? 'localhost').includes('localhost'), text: 'رابط الموقع الفعلي مضبوط في NEXT_PUBLIC_APP_URL' },
  ]

  const steps = [
    ['سُجّل النزاع', m.funnel.created],
    ['قبل الطرف الثاني', m.funnel.accepted],
    ['بدأت الوساطة بوسيط', m.funnel.active],
    ['صِيغ اتفاق التسوية', m.funnel.draft],
    ['وُقّع الاتفاق', m.funnel.signed],
  ] as const

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl">مؤشرات التجربة</h1>
        <p className="hint">تُحسب من سجل التدقيق مباشرة، فلا يمكن تعديلها يدويًا. الأعداد الصغيرة لا تثبت اتجاهًا؛ اعرضها كما هي دون تعميم.</p>
      </div>

      <section className="panel space-y-3">
        <h2 className="text-lg">مسار النزاعات</h2>
        {steps.map(([label, n]) => (
          <div key={label}>
            <div className="mb-1 flex justify-between text-sm">
              <span>{label}</span>
              <span className="font-semibold">{num(n)} <span className="hint">({pct(n, m.funnel.created)})</span></span>
            </div>
            <div className="h-3 rounded bg-navy-100">
              <div className="h-3 rounded bg-gold" style={{ width: `${m.funnel.created ? (n / m.funnel.created) * 100 : 0}%` }} />
            </div>
          </div>
        ))}
        <p className="hint">
          نسبة قبول الدعوات: {pct(m.invitations_accepted, m.invitations_sent)} — من بدأت وساطتها وانتهت بتسوية: {pct(m.funnel.signed, m.funnel.active)}
        </p>
      </section>

      <section className="panel space-y-3">
        <h2 className="text-lg">نتائج الملفات</h2>
        <dl className="grid gap-3 sm:grid-cols-5">
          {([
            ['تسوية موقّعة', m.outcomes.settled],
            ['انتهت دون تسوية', m.outcomes.no_settlement],
            ['سحبها مقدّم النزاع', m.outcomes.withdrawn],
            ['رفضها الطرف الثاني', m.outcomes.declined],
            ['ما زالت جارية', m.outcomes.open],
          ] as const).map(([k, v]) => (
            <div key={k} className="rounded-md border border-navy-100 p-3">
              <dt className="hint">{k}</dt>
              <dd className="text-lg font-bold">{num(v)}</dd>
            </div>
          ))}
        </dl>
        <p className="hint">
          نسبة التسوية بين الملفات التي بدأت وساطتها وانتهت: {pct(m.outcomes.settled, m.outcomes.settled + m.outcomes.no_settlement)} — ملفات انتهت قبل أي وساطة (سحب أو رفض): {pct(m.outcomes.withdrawn + m.outcomes.declined, m.funnel.created)} من كل الملفات.
          الملفات الجارية لا تدخل في نسبة التسوية.
        </p>
      </section>

      {arb && (
        <section className="panel space-y-3">
          <h2 className="text-lg">التحكيم</h2>
          <dl className="grid gap-3 sm:grid-cols-4">
            {([
              ['ملفات التحكيم', arb.total],
              ['صدر فيها حكم', arb.outcomes.award_issued],
              ['أنهى المحكّم إجراءاتها', arb.outcomes.terminated],
              ['سُحبت أو رُفضت', arb.outcomes.withdrawn + arb.outcomes.declined],
            ] as const).map(([k, v]) => (
              <div key={k} className="rounded-md border border-navy-100 p-3"><dt className="hint">{k}</dt><dd className="text-lg font-bold">{num(v)}</dd></div>
            ))}
          </dl>
          <p className="hint">
            التصعيد: {num(arb.escalated_from_mediation)} ملف تحكيم من أصل {num(arb.mediations_without_settlement)} وساطة انتهت دون تسوية ({pct(arb.escalated_from_mediation, arb.mediations_without_settlement)}).
            مذكرات قُدمت بعد موعدها: {num(arb.late_statements)}. الأعداد الصغيرة لا تثبت اتجاهًا.
          </p>
        </section>
      )}

      <section className="panel">
        <h2 className="mb-3 text-lg">الأزمنة (الوسيط الحسابي للنزاعات المكتملة للمرحلة)</h2>
        <dl className="grid gap-3 sm:grid-cols-2">
          {([
            ['من التسجيل إلى قبول الدعوة', m.median_secs.to_accept],
            ['من القبول إلى بدء الوساطة بوسيط', m.median_secs.to_mediator],
            ['من بدء الوساطة إلى توقيع الاتفاق', m.median_secs.to_signature],
            ['من التسجيل إلى توقيع الاتفاق', m.median_secs.total],
          ] as const).map(([k, v]) => (
            <div key={k} className="rounded-md border border-navy-100 p-3">
              <dt className="hint">{k}</dt>
              <dd className="text-lg font-bold">{formatDuration(v)}</dd>
            </div>
          ))}
        </dl>
      </section>

      <section className="panel">
        <h2 className="mb-3 text-lg">الحجم والقيمة</h2>
        <dl className="grid gap-3 sm:grid-cols-3">
          {([
            ['قيمة النزاعات المسجّلة', formatEgp(m.value_total)],
            ['قيمة النزاعات المسوّاة', formatEgp(m.value_settled)],
            ['المستخدمون', num(m.users_total)],
            ['الجلسات', num(m.sessions_total)],
            ['متوسط الجلسات للنزاع المسوّى', m.sessions_per_settled == null ? '—' : num(Number(m.sessions_per_settled))],
            ['المستندات الموثّقة', num(m.documents_total)],
          ] as const).map(([k, v]) => (
            <div key={k} className="rounded-md border border-navy-100 p-3">
              <dt className="hint">{k}</dt>
              <dd className="font-bold">{v}</dd>
            </div>
          ))}
        </dl>
      </section>

      <section className="panel">
        <h2 className="mb-3 text-lg">جاهزية التجربة</h2>
        <ul className="space-y-1 text-sm">
          {readiness.map((r) => (
            <li key={r.text} className={r.ok ? 'text-emerald-700' : 'font-semibold text-red-700'}>{r.ok ? '✓' : '✗'} {r.text}</li>
          ))}
        </ul>
        <p className="hint mt-3">بنود لا تستطيع المنصة فحصها بنفسها، وتراجعها يدويًا في لوحة Supabase: تفعيل تأكيد البريد، وSMTP، والنسخ الاحتياطي، ومنطقة الاستضافة (راجع docs/TRIAL_SETUP.md).</p>
      </section>
    </div>
  )
}
