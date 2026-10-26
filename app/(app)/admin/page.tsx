import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import { STATUS_LABEL, STATUS_TONE, formatDate, formatEgp } from '@/lib/labels'
import type { Dispute } from '@/lib/types'

export default async function AdminDisputesPage() {
  const supabase = await createClient()
  const { data } = await supabase.from('disputes').select('*').order('created_at', { ascending: false })
  const disputes = (data ?? []) as Dispute[]
  const ids = [...new Set(disputes.flatMap((d) => [d.claimant_id, d.respondent_id, d.mediator_id]).filter(Boolean) as string[])]
  const { data: people } = await supabase.from('profiles').select('id, full_name').in('id', ids)
  const name = (id: string | null) => (id ? people?.find((p) => p.id === id)?.full_name ?? '—' : '—')

  return (
    <div className="space-y-4">
      <h1 className="text-2xl">كل النزاعات ({disputes.length.toLocaleString('ar-EG')})</h1>
      <div className="panel overflow-x-auto !p-0">
        <table className="w-full min-w-[720px] text-sm">
          <thead className="bg-navy-50 text-start">
            <tr>{['الرقم', 'العنوان', 'القيمة', 'مقدّم النزاع', 'الطرف الثاني', 'الوسيط', 'الحالة', 'التاريخ'].map((h) => <th key={h} className="p-3 text-start">{h}</th>)}</tr>
          </thead>
          <tbody>
            {disputes.map((d) => (
              <tr key={d.id} className="border-t border-navy-100">
                <td className="p-3" dir="ltr"><Link className="font-semibold text-gold-700 underline" href={`/disputes/${d.id}`}>{d.dispute_number}</Link></td>
                <td className="p-3">{d.title}</td>
                <td className="p-3">{formatEgp(d.dispute_value_egp)}</td>
                <td className="p-3">{name(d.claimant_id)}</td>
                <td className="p-3">{name(d.respondent_id)}</td>
                <td className="p-3">{name(d.mediator_id)}</td>
                <td className="p-3"><span className={`badge ${STATUS_TONE[d.status]}`}>{STATUS_LABEL[d.status]}</span></td>
                <td className="p-3">{formatDate(d.created_at)}</td>
              </tr>
            ))}
            {disputes.length === 0 && <tr><td colSpan={8} className="p-6 text-center hint">لا توجد نزاعات.</td></tr>}
          </tbody>
        </table>
      </div>
    </div>
  )
}
