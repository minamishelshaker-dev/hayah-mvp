import { NextResponse } from 'next/server'
import { keyIdOf, publicKeyPem } from '@/lib/signing'

// The PUBLIC key used to sign records. Public by design: anyone can verify a record offline with it.
export async function GET() {
  const pem = publicKeyPem()
  if (!pem) return NextResponse.json({ error: 'record signing is not configured' }, { status: 404 })
  return NextResponse.json({ algorithm: 'Ed25519', key_id: keyIdOf(pem), public_key_pem: pem, canonicalization: 'canonical-json-v1' })
}
