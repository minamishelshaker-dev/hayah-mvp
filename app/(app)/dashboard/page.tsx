import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import { requireProfile } from '@/lib/auth'
import { STATUS_LABEL, STATUS_TONE, TYPE_LABEL, formatDate, formatEgp } from '@/lib/labels'
import { ARB_STATUS_LABEL, ARB_STATUS_TONE } from '@/lib/labels'
import type { Arbitration, Dispute } from '@/lib/types'

const ACTION_LABEL: Record<string, string> = {
  accept_agreement: 'اقرأ اتفاقية الوساطة واقبلها (لا يظهر محتوى الملف قبل ذلك)',
  approve_mediator: 'اقتُرح وسيط: وافق عليه أو ارفضه',
  accept_assignment: 'وافق الطرفان على تعيينك وسيطًا: اقبل المهمة أو اعتذر',
  choose_mediator: 'اختر وسيطًا للملف',
  renew_invitation: 'انتهت صلاحية الدعوة: جدّدها أو اسحب الملف',
  schedule_session: 'حدّد موعد جلسة',
  sign_settlement: 'اتفاق التسوية بانتظار توقيعك',
  accept_arb_rules: 'اقرأ قواعد التحكيم واقبلها (لا يظهر الملف قبل ذلك)',
  respond_escalation: 'طُلب تصعيد النزاع إلى التحكيم: وافق أو ارفض',
  confirm_agreement: 'أكّد ملف اتفاق التحكيم الموقَّع أو ارفعه',
  choose_arbitrator: 'اختر المحكّم',
  approve_arbitrator: 'اقتُرح محكّم: وافق عليه أو ارفضه',
  accept_arb_assignment: 'وافق الطرفان على تعيينك محكّمًا: اقبل وقدّم إقرار الاستقلال',
  set_timetable: 'حدّد الجدول الإجرائي',
  submit_statement: 'مذكرة مطلوبة منك في ملف تحكيم',
  issue_award: 'المداولة: صُغ الحكم وسجّل المسح الموقَّع',
}

export default async function DashboardPage() {
  const profile = await requireProfile()
  const supabase = await createClient()
  const { data } = await supabase.from('disputes').select('*').order('created_at', { ascending: false })
  const disputes = (data ?? []) as Dispute[]

  const { data: arbData } = await supabase.from('arbitrations').select('*').order('created_at', { ascending: false })
  const arbs = (arbData ?? []) as Arbitration[]
  const { data: actionsData } = await supabase.rpc('my_actions')
  const actions = (actionsData ?? []) as { case_kind?: string; case_id?: string; dispute_id?: string; dispute_number: string; code: string }[]
  const canCreate = profile.role === 'party' || profile.role === 'lawyer'

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-2xl">أهلًا {profile.full_name.split(' ')[0]}</h1>
        {canCreate && <Link href="/disputes/new" className="btn btn-gold">نزاع جديد</Link>}
      </div>

      {actions.length > 0 && (
        <section className="panel border-gold" aria-labelledby="todo">
          <h2 id="todo" className="mb-2 text-lg">ينتظرك ({actions.length.toLocaleString('ar-EG')})</h2>
          <ul className="space-y-1">
            {actions.map((a) => (
              <li key={(a.case_id ?? a.dispute_id) + a.code}>
                <Link href={a.case_kind === 'arbitration' ? `/arbitrations/${a.case_id}` : `/disputes/${a.case_id ?? a.dispute_id}`} className="font-semibold text-gold-700 underline">
                  <span dir="ltr">{a.dispute_number}</span>
                </Link>{' '}
                — {ACTION_LABEL[a.code] ?? a.code}
              </li>
            ))}
          </ul>
        </section>
      )}

      {profile.kyc_status !== 'verified' && profile.role !== 'admin' && (
        <p className="panel hint">حسابك بانتظار التحقق من الهوية من قبل المدير. يمكنك استخدام المنصة في هذه الأثناء.</p>
      )}

      {arbs.length > 0 && (
        <section aria-labelledby="arbs">
          <h2 id="arbs" className="mb-2 text-lg">ملفات التحكيم</h2>
          <ul className="space-y-3">
            {arbs.map((a) => (
              <li key={a.id}>
                <Link href={`/arbitrations/${a.id}`} className="panel flex flex-col justify-between gap-2 hover:border-gold sm:flex-row sm:items-center">
                  <div>
                    <p className="font-bold">{a.title}</p>
                    <p className="hint"><span dir="ltr">{a.arb_number}</span> — {formatEgp(a.dispute_value_egp)} — {formatDate(a.created_at)}</p>
                  </div>
                  <span className={`badge ${ARB_STATUS_TONE[a.status]}`}>{ARB_STATUS_LABEL[a.status]}</span>
                </Link>
              </li>
            ))}
          </ul>
        </section>
      )}

      {disputes.length === 0 ? (
        <div className="panel text-center">
          <p className="mb-1 font-semibold">لا توجد نزاعات ظاهرة بعد</p>
          <p className="hint">
            {canCreate ? 'سجّل نزاعًا جديدًا وادعُ الطرف الثاني للوساطة.' : 'ستظهر هنا الملفات التي تُعيَّن لك.'}
            {' '}ولديك رابط دعوة؟ افتحه من بريدك أو من الرسالة التي وصلتك.
          </p>
        </div>
      ) : (
        <ul className="space-y-3">
          {disputes.map((d) => (
            <li key={d.id}>
              <Link href={`/disputes/${d.id}`} className="panel flex flex-col justify-between gap-2 hover:border-gold sm:flex-row sm:items-center">
                <div>
                  <p className="font-bold">{d.title}</p>
                  <p className="hint">
                    <span dir="ltr">{d.dispute_number}</span> — {TYPE_LABEL[d.dispute_type]} — {formatEgp(d.dispute_value_egp)} — {formatDate(d.created_at)}
                  </p>
                </div>
                <span className={`badge ${STATUS_TONE[d.status]}`}>{STATUS_LABEL[d.status]}</span>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
