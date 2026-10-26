import Link from 'next/link'
import { notFound, redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { requireProfile } from '@/lib/auth'
import DailyRoom from '@/components/DailyRoom'
import { formatDate } from '@/lib/labels'

export default async function SessionPage(props: { params: Promise<{ id: string }> }) {
  const params = await props.params
  const profile = await requireProfile()
  const supabase = await createClient()
  const { data: s } = await supabase.from('sessions').select('*').eq('id', params.id).maybeSingle()
  if (!s) notFound()
  const { data: d } = await supabase.from('disputes').select('*').eq('id', s.dispute_id).single()
  if (!d || ![d.claimant_id, d.respondent_id, d.mediator_id].includes(profile.id)) redirect(`/disputes/${s.dispute_id}`)

  const ids = [d.claimant_id, d.respondent_id, d.mediator_id].filter(Boolean) as string[]
  const { data: people } = await supabase.rpc('profile_names', { p_ids: ids })
  const name = (id: string | null) => ((id && (people as Record<string, string> | null)?.[id]) || 'مشارك')

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <h1 className="text-xl">الجلسة {s.session_number.toLocaleString('ar-EG')} — {d.title}</h1>
          <p className="hint">{formatDate(s.scheduled_at)} — جلسة سرّية: لا يُسجَّل الصوت ولا الفيديو.</p>
        </div>
        <Link href={`/disputes/${d.id}`} className="btn btn-ghost">العودة إلى الملف</Link>
      </div>
      <DailyRoom
        sessionId={s.id}
        participants={[
          { name: name(d.mediator_id), role: 'الوسيط' },
          { name: name(d.claimant_id), role: 'مقدّم النزاع' },
          { name: name(d.respondent_id), role: 'الطرف الثاني' },
        ]}
      />
    </div>
  )
}
