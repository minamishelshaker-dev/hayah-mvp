import { NextResponse } from 'next/server'
import { createAdminClient } from '@/lib/supabase/admin'
import { sendAnchorEmail } from '@/lib/email'

// Called once a day by Vercel Cron (see vercel.json). Vercel sends "Authorization: Bearer $CRON_SECRET".
export async function GET(request: Request) {
  const secret = process.env.CRON_SECRET
  if (!secret || request.headers.get('authorization') !== `Bearer ${secret}`) {
    return NextResponse.json({ error: 'unauthorized' }, { status: 401 })
  }
  const to = process.env.ANCHOR_EMAIL
  if (!to) return NextResponse.json({ error: 'ANCHOR_EMAIL is not set' }, { status: 500 })

  const { data, error } = await createAdminClient().rpc('audit_head')
  if (error) return NextResponse.json({ error: 'could not read the audit head' }, { status: 500 })
  const head = data as { seq?: number; row_hash?: string; at?: string }
  if (!head?.seq || !head.row_hash) return NextResponse.json({ ok: true, note: 'audit log is empty' })

  const sent = await sendAnchorEmail(to, { seq: head.seq, row_hash: head.row_hash, at: head.at ?? '' })
  return NextResponse.json({ ok: sent, seq: head.seq }, { status: sent ? 200 : 502 })
}
