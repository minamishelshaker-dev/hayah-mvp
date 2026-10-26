// Round-trip test of the signing scheme with a throw-away key. Run: npm run test:signing
import { generateKeyPairSync, createPublicKey, createHash, sign, verify } from 'node:crypto'
import assert from 'node:assert/strict'

// Same function as lib/signing.ts and scripts/verify-record.mjs.
function canonicalize(v) {
  if (v === null || typeof v !== 'object') return JSON.stringify(v)
  if (Array.isArray(v)) return '[' + v.map(canonicalize).join(',') + ']'
  return '{' + Object.keys(v).filter((k) => v[k] !== undefined).sort().map((k) => JSON.stringify(k) + ':' + canonicalize(v[k])).join(',') + '}'
}
const { publicKey, privateKey } = generateKeyPairSync('ed25519')
const record = { schema: 'hayah-record/1', data: { dispute: { number: 'HAYAH-2026-0001', value_egp: 120000, title: 'نزاع توريد' }, list: [3, 1, 2] }, z: null }
const sig = sign(null, Buffer.from(canonicalize(record)), privateKey)

// 1. a record re-serialised with different key order / whitespace still verifies (that is what a download is)
const reordered = JSON.parse(JSON.stringify({ z: null, data: { list: [3, 1, 2], dispute: { title: 'نزاع توريد', value_egp: 120000.0, number: 'HAYAH-2026-0001' } }, schema: 'hayah-record/1' }, null, 4))
assert.ok(verify(null, Buffer.from(canonicalize(reordered)), publicKey, sig), 'reordered copy must verify')
// 2. any change is detected
for (const mutate of [(r) => { r.data.dispute.value_egp = 1 }, (r) => { r.data.list.push(4) }, (r) => { r.data.dispute.title += ' ' }, (r) => { r.z = 0 }]) {
  const copy = JSON.parse(JSON.stringify(record)); mutate(copy)
  assert.ok(!verify(null, Buffer.from(canonicalize(copy)), publicKey, sig), 'tampered copy must fail')
}
// 3. a different key does not verify
const other = generateKeyPairSync('ed25519').publicKey
assert.ok(!verify(null, Buffer.from(canonicalize(record)), other, sig), 'another key must fail')
// 4. key id is stable
const id = (pub) => createHash('sha256').update(pub.export({ type: 'spki', format: 'der' })).digest('hex').slice(0, 16)
// 4. the PEM round trip used by the server and by scripts/verify-record.mjs gives the same key id and still verifies
const pem = publicKey.export({ type: 'spki', format: 'pem' }).toString()
assert.equal(id(createPublicKey(pem)), id(publicKey))
assert.ok(verify(null, Buffer.from(canonicalize(record)), createPublicKey(pem), sig), 'PEM-loaded key must verify')
console.log('signing self-test: 9 checks passed')
