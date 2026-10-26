// Offline verification of a signed record bundle:
//   node scripts/verify-record.mjs hayah-record-XXXX.signed.json public-key.pem
// Needs only the downloaded bundle and the PUBLIC key. No access to the platform or its database.
import { readFileSync } from 'node:fs'
import { createPublicKey, createHash, verify } from 'node:crypto'

// Must match canonicalize() in lib/signing.ts.
function canonicalize(v) {
  if (v === null || typeof v !== 'object') return JSON.stringify(v)
  if (Array.isArray(v)) return '[' + v.map(canonicalize).join(',') + ']'
  return '{' + Object.keys(v).filter((k) => v[k] !== undefined).sort().map((k) => JSON.stringify(k) + ':' + canonicalize(v[k])).join(',') + '}'
}

const [bundlePath, pubPath] = process.argv.slice(2)
if (!bundlePath || !pubPath) { console.error('usage: node scripts/verify-record.mjs <bundle.json> <public-key.pem>'); process.exit(2) }
const bundle = JSON.parse(readFileSync(bundlePath, 'utf8'))
if (!bundle.signature?.value) { console.error('NO SIGNATURE in this file (download "with signature").'); process.exit(2) }
const pub = createPublicKey(readFileSync(pubPath, 'utf8'))
const keyId = createHash('sha256').update(pub.export({ type: 'spki', format: 'der' })).digest('hex').slice(0, 16)
if (bundle.signature.key_id && bundle.signature.key_id !== keyId) {
  console.error(`WRONG KEY: the record was signed with key ${bundle.signature.key_id}, this public key is ${keyId}`); process.exit(1)
}
const ok = verify(null, Buffer.from(canonicalize(bundle.record), 'utf8'), pub, Buffer.from(bundle.signature.value, 'base64'))
console.log(ok ? `VALID: signature matches the record (key ${keyId}).` : 'INVALID: the record was changed or the signature is not genuine.')
process.exit(ok ? 0 : 1)
