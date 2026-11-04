// A minimal SMTP client over implicit TLS (port 465), with no dependencies, so the platform can send mail through ANY SMTP account
// (Gmail with an app password, Brevo, Resend's SMTP, a company mailbox) without owning a verified sending domain.
// Keep this file free of framework imports and TypeScript-only runtime syntax: scripts/selftest-smtp.mjs imports it directly.
import tls from 'node:tls'
import { randomUUID } from 'node:crypto'

export interface SmtpConfig { host: string; port: number; user: string; pass: string; rejectUnauthorized?: boolean }
export interface SmtpMessage { from: string; to: string; subject: string; html: string }
interface Resp { code: number; text: string }

const CRLF = '\r\n'
const hasLineBreak = (s: string) => /[\r\n]/.test(s)
const b64 = (s: string) => Buffer.from(s, 'utf8').toString('base64')
// RFC 2047: non-ASCII header text must be encoded, otherwise Arabic subjects arrive as garbage.
const encodeWord = (s: string) => (/^[\x20-\x7e]*$/.test(s) ? s : `=?UTF-8?B?${b64(s)}?=`)
const bareAddress = (s: string) => (s.match(/<([^<>]+)>/)?.[1] ?? s).trim()
function formatFrom(from: string): string {
  const m = from.match(/^(.*)<([^<>]+)>\s*$/)
  if (!m) return from.trim()
  const name = m[1].trim().replace(/^"|"$/g, '')
  return name ? `${encodeWord(name)} <${m[2].trim()}>` : m[2].trim()
}

// Readable plain-text twin of the HTML body. Mail with only an HTML part scores worse with spam filters, and some clients show only text.
export function htmlToText(html: string): string {
  return html
    .replace(/<(script|style)[\s\S]*?<\/\1>/gi, '')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/(p|div|tr|h[1-6]|li)>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&amp;/g, '&')
    .replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n').trim()
}

const b64Lines = (s: string) => (b64(s).match(/.{1,76}/g) ?? []).join(CRLF)

export function buildMessage(m: SmtpMessage, messageIdDomain: string): string {
  const boundary = `=_hayah_${randomUUID()}`
  return [
    `From: ${formatFrom(m.from)}`,
    `To: ${bareAddress(m.to)}`,
    `Subject: ${encodeWord(m.subject)}`,
    `Date: ${new Date().toUTCString()}`,
    `Message-ID: <${randomUUID()}@${messageIdDomain}>`,
    'MIME-Version: 1.0',
    `Content-Type: multipart/alternative; boundary="${boundary}"`,
    '',
    `--${boundary}`,
    'Content-Type: text/plain; charset=UTF-8',
    'Content-Transfer-Encoding: base64',
    '',
    b64Lines(htmlToText(m.html)),
    `--${boundary}`,
    'Content-Type: text/html; charset=UTF-8',
    'Content-Transfer-Encoding: base64',
    '',
    b64Lines(m.html),
    `--${boundary}--`,
    '',
  ].join(CRLF)
}

export async function smtpSend(cfg: SmtpConfig, msg: SmtpMessage): Promise<void> {
  for (const v of [msg.from, msg.to, msg.subject]) if (hasLineBreak(v)) throw new Error('SMTP: line break in a header value')
  const fromAddr = bareAddress(msg.from)
  const toAddr = bareAddress(msg.to)
  if (!/^[^\s<>@]+@[^\s<>@]+$/.test(fromAddr) || !/^[^\s<>@]+@[^\s<>@]+$/.test(toAddr)) throw new Error('SMTP: invalid address')

  const socket = tls.connect({ host: cfg.host, port: cfg.port, servername: cfg.host, rejectUnauthorized: cfg.rejectUnauthorized !== false })
  socket.setEncoding('utf8')
  socket.setTimeout(20_000, () => socket.destroy(new Error('SMTP: timeout')))

  let buf = ''
  let failure: Error | null = null
  let waiter: { resolve: (r: Resp) => void; reject: (e: Error) => void } | null = null

  const parse = (): Resp | null => {
    const lines = buf.split(CRLF)
    for (let i = 0; i < lines.length - 1; i++) {
      if (/^\d{3}( |$)/.test(lines[i])) {
        const text = lines.slice(0, i + 1).join('\n')
        buf = lines.slice(i + 1).join(CRLF)
        return { code: Number(lines[i].slice(0, 3)), text }
      }
    }
    return null
  }
  const settle = () => {
    if (!waiter) return
    if (failure) { const w = waiter; waiter = null; w.reject(failure); return }
    const r = parse()
    if (r) { const w = waiter; waiter = null; w.resolve(r) }
  }
  socket.on('data', (d: string) => { buf += d; settle() })
  socket.on('error', (e: Error) => { failure = e; settle() })
  socket.on('close', () => { if (!failure) failure = new Error('SMTP: connection closed'); settle() })

  const next = () => new Promise<Resp>((resolve, reject) => {
    const r = parse()
    if (r) return resolve(r)
    if (failure) return reject(failure)
    waiter = { resolve, reject }
  })
  const send = async (line: string, ok: number[]) => {
    socket.write(line + CRLF)
    const r = await next()
    if (!ok.includes(r.code)) throw new Error(`SMTP ${r.code}: ${r.text.replace(/\s+/g, ' ').slice(0, 200)}`)
    return r
  }

  try {
    const hello = await next()
    if (hello.code !== 220) throw new Error(`SMTP ${hello.code}: ${hello.text.slice(0, 200)}`)
    await send('EHLO hayah.local', [250])
    await send(`AUTH PLAIN ${b64(`\u0000${cfg.user}\u0000${cfg.pass}`)}`, [235])
    await send(`MAIL FROM:<${fromAddr}>`, [250])
    await send(`RCPT TO:<${toAddr}>`, [250, 251])
    await send('DATA', [354])
    socket.write(buildMessage(msg, fromAddr.split('@')[1] ?? 'hayah.local') + CRLF + '.' + CRLF)
    const done = await next()
    if (done.code !== 250) throw new Error(`SMTP ${done.code}: ${done.text.replace(/\s+/g, ' ').slice(0, 200)}`)
    socket.write('QUIT' + CRLF)
  } finally {
    socket.end()
  }
}
