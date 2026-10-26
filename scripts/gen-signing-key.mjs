// Generates an Ed25519 key pair for signing records.
// Put the PRIVATE value in Vercel as RECORD_SIGNING_PRIVATE_KEY. Publish / keep the PUBLIC key (also served at /api/record-key).
import { generateKeyPairSync, createHash } from 'node:crypto'
const { publicKey, privateKey } = generateKeyPairSync('ed25519')
const pub = publicKey.export({ type: 'spki', format: 'pem' }).toString()
const priv = privateKey.export({ type: 'pkcs8', format: 'pem' }).toString()
const keyId = createHash('sha256').update(publicKey.export({ type: 'spki', format: 'der' })).digest('hex').slice(0, 16)
console.log('KEY ID:', keyId, '\n')
console.log('--- RECORD_SIGNING_PRIVATE_KEY (one line, keep SECRET) ---')
console.log(priv.trim().replace(/\n/g, '\\n'), '\n')
console.log('--- PUBLIC KEY (keep a copy forever) ---')
console.log(pub)
