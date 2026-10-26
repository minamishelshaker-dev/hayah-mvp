import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

// Default: the stored record exactly as issued (this is what /verify compares against the database).
// ?format=bundle: the record plus its Ed25519 signature, for offline verification (scripts/verify-record.mjs).
export async function GET(req: Request, ctx: { params: Promise<{ id: string }> }) {
  const params = await ctx.params
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'غير مصرح' }, { status: 401 })
  const { data } = await supabase
    .from('record_exports').select('record, signature, signing_key_id, signed_at').eq('id', params.id).maybeSingle()
  if (!data) return NextResponse.json({ error: 'غير موجود' }, { status: 404 })

  const number = (data.record as { data?: { dispute?: { number?: string } } })?.data?.dispute?.number ?? 'record'
  const bundle = new URL(req.url).searchParams.get('format') === 'bundle'
  const body = bundle
    ? {
        record: data.record,
        signature: data.signature
          ? { algorithm: 'Ed25519', key_id: data.signing_key_id, value: data.signature, signed_at: data.signed_at, covers: 'canonical-json-v1 of "record"' }
          : null,
      }
    : data.record
  return new NextResponse(JSON.stringify(body, null, 2), {
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Content-Disposition': `attachment; filename="hayah-record-${number}${bundle ? '.signed' : ''}.json"`,
    },
  })
}
