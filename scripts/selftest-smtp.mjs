// Unit test for lib/smtp.ts against a local mock SMTP server over TLS.   npm run test:smtp   (Node 22+, needs openssl)
import tls from 'node:tls'
import { execFileSync } from 'node:child_process'
import { mkdtempSync, readFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { smtpSend } from '../lib/smtp.ts'

let failed = 0
const check = (cond, msg) => { if (!cond) { failed++; console.error('FAIL:', msg) } }

const dir = mkdtempSync(join(tmpdir(), 'smtp-test-'))
execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', join(dir, 'k.pem'), '-out', join(dir, 'c.pem'), '-days', '1', '-subj', '/CN=localhost'], { stdio: 'ignore' })
const cert = { key: readFileSync(join(dir, 'k.pem')), cert: readFileSync(join(dir, 'c.pem')) }

const sessions = []
const server = tls.createServer(cert, (sock) => {
  const s = { cmds: [], data: '', auth: null }
  sessions.push(s)
  sock.setEncoding('utf8')
  let buf = ''; let inData = false
  sock.write('220 mock ESMTP\r\n')
  sock.on('data', (d) => {
    buf += d
    for (;;) {
      if (inData) {
        const end = buf.indexOf('\r\n.\r\n')
        if (end < 0) return
        s.data = buf.slice(0, end); buf = buf.slice(end + 5); inData = false
        sock.write('250 queued\r\n'); continue
      }
      const i = buf.indexOf('\r\n'); if (i < 0) return
      const line = buf.slice(0, i); buf = buf.slice(i + 2)
      s.cmds.push(line.startsWith('AUTH PLAIN') ? 'AUTH PLAIN <redacted>' : line)
      if (line.startsWith('EHLO')) sock.write('250-mock greets you\r\n250-SIZE 35882577\r\n250 AUTH PLAIN LOGIN\r\n')
      else if (line.startsWith('AUTH PLAIN')) {
        const [, user, pass] = Buffer.from(line.slice(11), 'base64').toString('utf8').split('\u0000')
        s.auth = { user, pass }
        sock.write(user === 'me@gmail.test' && pass === 'app-password' ? '235 2.7.0 Accepted\r\n' : '535-5.7.8 Username and Password not accepted\r\n535 5.7.8 Learn more\r\n')
      }
      else if (line.startsWith('MAIL FROM:')) sock.write('250 ok\r\n')
      else if (line.startsWith('RCPT TO:')) sock.write(line.includes('reject') ? '550 5.1.1 no such user\r\n' : '250 ok\r\n')
      else if (line === 'DATA') { inData = true; sock.write('354 go ahead\r\n') }
      else if (line === 'QUIT') { sock.write('221 bye\r\n'); sock.end() }
      else sock.write('500 what\r\n')
    }
  })
})
await new Promise((r) => server.listen(0, '127.0.0.1', r))
const port = server.address().port
const cfg = { host: '127.0.0.1', port, user: 'me@gmail.test', pass: 'app-password', rejectUnauthorized: false }
const rejects = async (p, re) => { try { await p; return false } catch (e) { return re.test(String(e.message)) } }

// --- success: the invitation goes to the SECOND party, with an Arabic subject and body
const html = '<p>تمت دعوتك إلى وساطة <a href="https://hayah-launch.vercel.app/invite/abc">رابط</a></p>'
await smtpSend(cfg, { from: 'Hayah <me@gmail.test>', to: 'second.party@example.com', subject: 'دعوة إلى وساطة — HAYAH-2026-0005', html })
const s1 = sessions[0]
check(s1.auth?.user === 'me@gmail.test' && s1.auth?.pass === 'app-password', 'authenticates with the SMTP account')
check(s1.cmds.includes('MAIL FROM:<me@gmail.test>'), 'envelope sender is the configured mailbox')
check(s1.cmds.includes('RCPT TO:<second.party@example.com>'), 'envelope recipient is the second party')
const [head, ...rest] = s1.data.split('\r\n\r\n')
const body = Buffer.from(rest.join('').replace(/\s+/g, ''), 'base64').toString('utf8')
check(body === html, 'HTML body round-trips as UTF-8 (Arabic intact)')
check(/^To: second\.party@example\.com$/m.test(head), 'To header is the second party only')
check(!/claimant/i.test(head), 'no other recipient in the headers')
const subj = head.match(/^Subject: =\?UTF-8\?B\?(.+)\?=$/m)
check(subj && Buffer.from(subj[1], 'base64').toString('utf8') === 'دعوة إلى وساطة — HAYAH-2026-0005', 'Arabic subject is RFC 2047 encoded and decodes back')
check(/^From: Hayah <me@gmail\.test>$/m.test(head), 'ASCII display name stays readable')
check(/^Content-Type: text\/html; charset=UTF-8$/m.test(head) && /^MIME-Version: 1\.0$/m.test(head), 'MIME headers present')
check(/^Message-ID: <[0-9a-f-]+@gmail\.test>$/m.test(head) && /^Date: /m.test(head), 'Message-ID and Date present')
await new Promise((r) => setTimeout(r, 100)) // the server logs QUIT a moment after the client returns
check(s1.cmds.at(-1) === 'QUIT', 'session ends with QUIT')
// --- Arabic display name
await smtpSend(cfg, { from: 'حياة <me@gmail.test>', to: 'a@example.com', subject: 'x', html: '<p>x</p>' })
check(/^From: =\?UTF-8\?B\?.+\?= <me@gmail\.test>$/m.test(sessions[1].data.split('\r\n\r\n')[0]), 'Arabic display name is encoded')
// --- failures are reported, not swallowed
check(await rejects(smtpSend({ ...cfg, pass: 'wrong' }, { from: 'me@gmail.test', to: 'a@example.com', subject: 's', html: 'h' }), /SMTP 535/), 'bad credentials -> SMTP 535 error (multi-line reply handled)')
check(await rejects(smtpSend(cfg, { from: 'me@gmail.test', to: 'reject@example.com', subject: 's', html: 'h' }), /SMTP 550/), 'rejected recipient -> SMTP 550 error')
check(await rejects(smtpSend(cfg, { from: 'me@gmail.test', to: 'a@example.com', subject: 'x\r\nBcc: evil@example.com', html: 'h' }), /line break/), 'header injection in the subject is refused')
check(await rejects(smtpSend(cfg, { from: 'me@gmail.test', to: 'a@example.com\r\nRCPT TO:<evil@example.com>', subject: 's', html: 'h' }), /line break/), 'header injection in the recipient is refused')
check(await rejects(smtpSend(cfg, { from: 'me@gmail.test', to: 'not-an-address', subject: 's', html: 'h' }), /invalid address/), 'invalid recipient address is refused')
check(await rejects(smtpSend({ ...cfg, port: 1 }, { from: 'me@gmail.test', to: 'a@example.com', subject: 's', html: 'h' }), /ECONNREFUSED|SMTP/), 'unreachable server -> error, not a hang')
check(await rejects(smtpSend({ ...cfg, rejectUnauthorized: true }, { from: 'me@gmail.test', to: 'a@example.com', subject: 's', html: 'h' }), /self.signed|certificate|SMTP/i), 'untrusted certificate is refused by default')

server.close()
if (failed) { console.error(`${failed} check(s) failed`); process.exit(1) }
console.log('smtp self-test: all checks passed')
