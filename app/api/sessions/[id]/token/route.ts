import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { createMeetingToken, dailyEnabled } from '@/lib/daily'
import { rateLimited } from '@/lib/ratelimit'

const OPENS_BEFORE_MIN = 15
const GRACE_AFTER_MIN = 30

export async function GET(_req: Request, ctx: { params: Promise<{ id: string }> }) {
  const params = await ctx.params
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'غير مصرح' }, { status: 401 })
  if (await rateLimited('session-token', 60, 600, user.id)) return NextResponse.json({ error: 'طلبات كثيرة. حاول بعد قليل.' }, { status: 429 })

  // RLS: this only returns the session if the caller belongs to the dispute (and accepted its agreement).
  const { data: s } = await supabase
    .from('sessions')
    .select('id, dispute_id, status, scheduled_at, duration_minutes, daily_room_name, daily_room_url')
    .eq('id', params.id)
    .maybeSingle()
  if (!s) return NextResponse.json({ error: 'الجلسة غير موجودة' }, { status: 404 })

  const { data: d } = await supabase
    .from('disputes')
    .select('claimant_id, respondent_id, mediator_id, status')
    .eq('id', s.dispute_id)
    .single()
  // Only the mediator and the two parties may enter (an admin can read the file, but not join the room).
  if (!d || ![d.claimant_id, d.respondent_id, d.mediator_id].includes(user.id)) {
    return NextResponse.json({ error: 'غير مصرح بدخول هذه الجلسة' }, { status: 403 })
  }
  if (s.status === 'cancelled') return NextResponse.json({ error: 'أُلغيت هذه الجلسة.' }, { status: 410 })
  if (['closed', 'cancelled'].includes(d.status)) return NextResponse.json({ error: 'انتهى هذا الملف ولا تُعقد فيه جلسات.' }, { status: 410 })

  const start = new Date(s.scheduled_at).getTime()
  const now = Date.now()
  if (now < start - OPENS_BEFORE_MIN * 60_000) {
    return NextResponse.json({ error: `تُفتح الجلسة قبل موعدها بـ ${OPENS_BEFORE_MIN} دقيقة.` }, { status: 425 })
  }
  const end = start + (s.duration_minutes + GRACE_AFTER_MIN) * 60_000
  if (now > end) return NextResponse.json({ error: 'انتهى وقت هذه الجلسة.' }, { status: 410 })

  if (!dailyEnabled() || !s.daily_room_name) return NextResponse.json({ demo: true })

  const { data: me } = await supabase.from('profiles').select('full_name').eq('id', user.id).single()
  const token = await createMeetingToken(
    s.daily_room_name,
    me?.full_name ?? 'مشارك',
    d.mediator_id === user.id,
    Math.max(300, Math.floor((end - now) / 1000)),
    Math.floor((start - OPENS_BEFORE_MIN * 60_000) / 1000)
  )
  return NextResponse.json({ url: s.daily_room_url, token })
}
