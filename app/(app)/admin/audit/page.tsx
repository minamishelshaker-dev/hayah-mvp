import { createClient } from '@/lib/supabase/server'
import FormAction from '@/components/FormAction'
import { verifyAuditChain, checkAuditAnchor } from '../actions'
import { describeEvent, formatDate } from '@/lib/labels'
import type { AuditLog } from '@/lib/types'

export default async function AdminAuditPage() {
  const supabase = await createClient()
  const { data } = await supabase.from('audit_logs').select('*').order('seq', { ascending: false }).limit(200)
  const logs = (data ?? []) as AuditLog[]
  const ids = [...new Set(logs.map((l) => l.actor_id).filter(Boolean) as string[])]
  const { data: people } = await supabase.from('profiles').select('id, full_name').in('id', ids)
  const name = (id: string | null) => (id ? people?.find((p) => p.id === id)?.full_name ?? '—' : 'النظام')
  const { data: disputes } = await supabase.from('disputes').select('id, dispute_number')
  const number = (id: string | null) => disputes?.find((d) => d.id === id)?.dispute_number ?? '—'

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl">سجل التدقيق</h1>
          <p className="hint">آخر 200 حدث. كل سطر مرتبط ببصمة السطر السابق، فيُكتشف التعديل العادي لسطر قديم. لكن من يملك صلاحية مدير قاعدة البيانات يستطيع إعادة حساب السلسلة كلها، ولهذا تُرسل بصمة آخر حدث يوميًا إلى بريدك خارج النظام (نقاط التحقق أدناه).</p>
        </div>
        <FormAction action={verifyAuditChain} submitLabel="فحص سلامة السلسلة" variant="gold" />
      </div>
      <section className="panel">
        <h2 className="mb-1 text-lg">فحص نقطة تحقق محفوظة خارج النظام</h2>
        <p className="hint mb-3">أدخل رقم الحدث وبصمته من رسالة نقطة التحقق اليومية. إن لم تطابق بصمة السجل الحالية فقد أُعيدت كتابة السجل.</p>
        <FormAction action={checkAuditAnchor} submitLabel="افحص النقطة" variant="ghost" className="flex flex-wrap items-end gap-2">
          <div>
            <label className="label" htmlFor="seq">رقم الحدث</label>
            <input id="seq" name="seq" type="number" min={1} required dir="ltr" className="input w-32" />
          </div>
          <div className="min-w-0 flex-1">
            <label className="label" htmlFor="hash">البصمة (64 خانة)</label>
            <input id="hash" name="hash" required dir="ltr" className="input font-mono text-xs" />
          </div>
        </FormAction>
      </section>
      <div className="panel overflow-x-auto !p-0">
        <table className="w-full min-w-[720px] text-sm">
          <thead className="bg-navy-50">
            <tr>{['#', 'التوقيت', 'الحدث', 'الفاعل', 'النزاع', 'الختم'].map((h) => <th key={h} className="p-3 text-start">{h}</th>)}</tr>
          </thead>
          <tbody>
            {logs.map((l) => (
              <tr key={l.id} className="border-t border-navy-100">
                <td className="p-3" dir="ltr">{l.seq}</td>
                <td className="p-3">{formatDate(l.created_at)}</td>
                <td className="p-3">{describeEvent(l)}</td>
                <td className="p-3">{name(l.actor_id)}</td>
                <td className="p-3" dir="ltr">{number(l.dispute_id)}</td>
                <td className="p-3 font-mono text-xs" dir="ltr">{l.row_hash?.slice(0, 10)}</td>
              </tr>
            ))}
            {logs.length === 0 && <tr><td colSpan={6} className="p-6 text-center hint">لا توجد أحداث.</td></tr>}
          </tbody>
        </table>
      </div>
    </div>
  )
}
