// Unit test for lib/scan.ts (the optional malware-scanner decision logic).   npm run test:scan   (Node 22+)
import { scanVerdict } from '../lib/scan.ts'

let failed = 0
const check = (cond, msg) => { if (!cond) { failed++; console.error('FAIL:', msg) } }
const bytes = new Uint8Array([1, 2, 3])
const reply = (ok, status, body) => async () => ({ ok, status, json: async () => body })
const boom = async () => { throw new Error('network down') }
const badJson = async () => ({ ok: true, status: 200, json: async () => { throw new SyntaxError('not json') } })
const URL_ = 'https://scan.internal/check'

// --- no scanner configured
check((await scanVerdict(bytes, 'a.pdf', {}, boom)) === null, 'no URL, not required: file passes (documented fail-open)')
check((await scanVerdict(bytes, 'a.pdf', { MALWARE_SCAN_REQUIRED: 'true' }, boom)) !== null, 'no URL, REQUIRED=true: upload rejected (the bug that was fixed)')
check((await scanVerdict(bytes, 'a.pdf', { MALWARE_SCAN_REQUIRED: 'yes' }, boom)) === null, 'only the exact value "true" makes it required')
// --- scanner answers
check((await scanVerdict(bytes, 'a.pdf', { MALWARE_SCAN_URL: URL_ }, reply(true, 200, { clean: true }))) === null, 'clean: passes')
check((await scanVerdict(bytes, 'a.pdf', { MALWARE_SCAN_URL: URL_ }, reply(true, 200, { clean: false }))) !== null, 'infected: rejected even when not required')
check((await scanVerdict(bytes, 'a.pdf', { MALWARE_SCAN_URL: URL_ }, reply(true, 200, {}))) !== null, 'answer without clean=true: rejected')
check((await scanVerdict(bytes, 'a.pdf', { MALWARE_SCAN_URL: URL_ }, reply(true, 200, { clean: 'true' }))) !== null, 'clean as a string is not accepted')
check((await scanVerdict(bytes, 'a.pdf', { MALWARE_SCAN_URL: URL_ }, reply(true, 200, null))) !== null, 'null body: rejected, no crash')
// --- scanner outage / garbage
for (const [name, f] of [['network error', boom], ['HTTP 500', reply(false, 500, {})], ['malformed JSON', badJson]]) {
  check((await scanVerdict(bytes, 'a.pdf', { MALWARE_SCAN_URL: URL_ }, f)) === null, `${name}, not required: passes unscanned (documented fail-open)`)
  check((await scanVerdict(bytes, 'a.pdf', { MALWARE_SCAN_URL: URL_, MALWARE_SCAN_REQUIRED: 'true' }, f)) !== null, `${name}, REQUIRED=true: rejected (fail-closed)`)
}
// --- what is sent
let seen
await scanVerdict(bytes, 'عقد.pdf', { MALWARE_SCAN_URL: URL_, MALWARE_SCAN_TOKEN: 'tok' }, async (u, init) => { seen = { u, init }; return { ok: true, status: 200, json: async () => ({ clean: true }) } })
check(seen?.u === URL_ && seen.init.method === 'POST' && seen.init.headers.Authorization === 'Bearer tok', 'POSTs to the URL with the bearer token')
check(seen?.init.headers['X-File-Name'] === encodeURIComponent('عقد.pdf'), 'file name is URL-encoded in the header')

if (failed) { console.error(`${failed} check(s) failed`); process.exit(1) }
console.log('scan self-test: all checks passed')
