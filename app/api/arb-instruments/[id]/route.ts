import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

// Download the frozen record of a signed arbitration agreement or award, with the platform's Ed25519 signature, for OFFLINE checking:
//   node scripts/verify-record.mjs <file>.json <public-key.pem>      (public key: /api/record-key)
// :id is the arbitration id; ?kind=agreement|award. RLS decides who may read it (the parties; the seated arbitrator; the admin).
export async function GET(req: Request, ctx: { params: Promise<{ id: string }> }) {
  const params = await ctx.params
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'غير مصرح' }, { status: 401 })

  const kind = new URL(req.url).searchParams.get('kind') === 'award' ? 'award' : 'agreement'
  const { data } = await supabase
    .from(kind === 'award' ? 'arb_awards' : 'arb_agreements')
    .select('signed_record, platform_signature, signing_key_id')
    .eq('arbitration_id', params.id)
    .maybeSingle()
  if (!data?.signed_record) return NextResponse.json({ error: 'غير موجود' }, { status: 404 })

  const number = (data.signed_record as { arbitration_number?: string }).arbitration_number ?? 'arbitration'
  const body = {
    record: data.signed_record,
    signature: data.platform_signature
      ? { algorithm: 'Ed25519', key_id: data.signing_key_id, value: data.platform_signature, covers: 'canonical-json-v1 of "record"' }
      : null,
  }
  return new NextResponse(JSON.stringify(body, null, 2), {
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Content-Disposition': `attachment; filename="hayah-${kind}-${number}.signed.json"`,
    },
  })
}
