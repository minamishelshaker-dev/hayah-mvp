import { createHash, createPrivateKey, createPublicKey, sign, verify } from 'crypto'

// Canonical JSON (v1): object keys sorted, no whitespace, arrays in order. A record is signed over THIS text,
// so anyone with the public key can re-check a downloaded record offline. Keep scripts/verify-record.mjs in sync.
export function canonicalize(value: unknown): string {
  if (value === null || typeof value !== 'object') return JSON.stringify(value)
  if (Array.isArray(value)) return '[' + value.map(canonicalize).join(',') + ']'
  const o = value as Record<string, unknown>
  return '{' + Object.keys(o).filter((k) => o[k] !== undefined).sort().map((k) => JSON.stringify(k) + ':' + canonicalize(o[k])).join(',') + '}'
}

const pem = () => (process.env.RECORD_SIGNING_PRIVATE_KEY ?? '').replace(/\\n/g, '\n').trim()
export const signingConfigured = () => pem().includes('PRIVATE KEY')

export function publicKeyPem(): string | null {
  if (!signingConfigured()) return null
  return createPublicKey(createPrivateKey(pem())).export({ type: 'spki', format: 'pem' }).toString()
}

export function keyIdOf(publicPem: string): string {
  const der = createPublicKey(publicPem).export({ type: 'spki', format: 'der' })
  return createHash('sha256').update(der).digest('hex').slice(0, 16)
}

export function signRecord(record: unknown): { signature: string; keyId: string } | null {
  const pub = publicKeyPem()
  if (!pub) return null
  const signature = sign(null, Buffer.from(canonicalize(record), 'utf8'), createPrivateKey(pem())).toString('base64')
  return { signature, keyId: keyIdOf(pub) }
}

export function verifyRecordSignature(publicPemText: string, record: unknown, signatureB64: string): boolean {
  try {
    return verify(null, Buffer.from(canonicalize(record), 'utf8'), createPublicKey(publicPemText), Buffer.from(signatureB64, 'base64'))
  } catch {
    return false
  }
}
