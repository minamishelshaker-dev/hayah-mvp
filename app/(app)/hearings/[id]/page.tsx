import Link from 'next/link'
import { notFound, redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { requireProfile } from '@/lib/auth'
import DailyRoom from '@/components/DailyRoom'
import { formatDate } from '@/lib/labels'

export default async function HearingPage(props: { params: Promise<{ id: string }> }) {
  const params = await props.params
  const profile = await requireProfile()
  const supabase = await createClient()
  const { data: h } = await supabase.from('arb_hearings').select('*').eq('id', params.id).maybeSingle()
  if (!h) notFound()
  const { data: a } = await supabase.from('arbitrations').select('*').eq('id', h.arbitration_id).single()
  if (!a || ![a.claimant_id, a.respondent_id, a.arbitrator_id].includes(profile.id)) redirect(`/arbitrations/${h.arbitration_id}`)

  const ids = [a.claimant_id, a.respondent_id, a.arbitrator_id].filter(Boolean) as string[]
  const { data: people } = await supabase.rpc('profile_names', { p_ids: ids })
  const name = (id: string | null) => ((id && (people as Record<string, string> | null)?.[id]) || 'مشارك')

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <h1 className="text-xl">جلسة التحكيم {h.number.toLocaleString('ar-EG')} — {a.title}</h1>
          <p className="hint">{formatDate(h.scheduled_at)} — لا يُسجَّل الصوت ولا الفيديو.</p>
        </div>
        <Link href={`/arbitrations/${a.id}`} className="btn btn-ghost">العودة إلى الملف</Link>
      </div>
      <DailyRoom sessionId={h.id} tokenUrl={`/api/arb-hearings/${h.id}/token`}
        participants={[
          { name: name(a.arbitrator_id), role: 'المحكّم' },
          { name: name(a.claimant_id), role: 'مقدّم الطلب' },
          { name: name(a.respondent_id), role: 'الطرف الآخر' },
        ]} />
    </div>
  )
}
