import { smtpSend } from '@/lib/smtp'
import { BRAND } from '@/lib/brand'

const appUrl = () => (process.env.NEXT_PUBLIC_APP_URL ?? 'https://hayah-launch.vercel.app').replace(/\/$/, '')

// Branded RTL mail frame: navy band with the Hayah wordmark, gold rule, body, and the official footer line.
export function brandEmail(inner: string): string {
  return `<div dir="rtl" style="margin:0;padding:0;background:#F8F6F1">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F8F6F1"><tr><td align="center" style="padding:24px 12px">
    <table role="presentation" width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;background:#ffffff;border:1px solid #E6EAF0">
      <tr><td align="center" style="background:#0A1628;padding:0;border-bottom:3px solid #C6922A">
        <img src="${appUrl()}/email-logo.png" width="300" alt="${BRAND.nameEn}" style="display:block;max-width:100%;height:auto;border:0;color:#C6922A;font:700 22px Georgia,serif">
      </td></tr>
      <tr><td style="padding:28px 28px 20px;font-family:Cairo,Tahoma,Arial,sans-serif;font-size:15px;line-height:1.9;color:#0A1628">${inner}</td></tr>
      <tr><td style="padding:14px 28px;border-top:1px solid #E6EAF0;font-family:Cairo,Tahoma,Arial,sans-serif;font-size:12px;color:#3A4C63;text-align:center">${BRAND.footerLine}</td></tr>
    </table>
  </td></tr></table>
</div>`
}

export const esc = (v: string) => v.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c] as string))

// Mail goes out through ONE of two providers, chosen by configuration:
//  1) SMTP  (SMTP_HOST, SMTP_USER, SMTP_PASS, optional SMTP_PORT = 465 and MAIL_FROM). Works with a Gmail account + app password and needs
//     no verified domain, so the platform can write to ANY recipient (the second party included).
//  2) Resend (RESEND_API_KEY, RESEND_FROM). With the default onboarding@resend.dev sender Resend delivers ONLY to the account owner's own
//     address: every other recipient is rejected, which is why invitations never reached the second party. Verify a domain in Resend to fix that.
export type MailResult = { ok: true; via: 'smtp' | 'resend' } | { ok: false; reason: string }

const smtpConfig = () => {
  const { SMTP_HOST: host, SMTP_USER: user, SMTP_PASS: pass } = process.env
  return host && user && pass ? { host, user, pass, port: Number(process.env.SMTP_PORT) || 465 } : null
}
export const mailConfigured = () => Boolean(smtpConfig() || process.env.RESEND_API_KEY)
// True only when host AND user AND password are all set (a lone SMTP_HOST must not count as "configured").
export const smtpConfigured = () => Boolean(smtpConfig())
const fromAddress = () => process.env.MAIL_FROM ?? process.env.RESEND_FROM ?? (smtpConfig() ? `Hayah <${process.env.SMTP_USER}>` : 'Hayah <onboarding@resend.dev>')

// Never throws. Failures are written to the runtime logs (no message content, no secrets) so they can be diagnosed.
async function deliver(to: string, subject: string, html: string): Promise<MailResult> {
  const domain = to.split('@')[1] ?? '?'
  const smtp = smtpConfig()
  if (smtp) {
    try {
      await smtpSend(smtp, { from: fromAddress(), to, subject, html })
      return { ok: true, via: 'smtp' }
    } catch (e) {
      const reason = e instanceof Error ? e.message : 'SMTP error'
      console.error(JSON.stringify({ level: 'error', what: 'mail-send-failed', via: 'smtp', toDomain: domain, reason: reason.slice(0, 200) }))
      return { ok: false, reason }
    }
  }
  const key = process.env.RESEND_API_KEY
  if (!key) return { ok: false, reason: 'no mail provider configured (set SMTP_* or RESEND_API_KEY)' }
  try {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from: fromAddress(), to, subject, html }),
    })
    if (res.ok) return { ok: true, via: 'resend' }
    const detail = (await res.text()).replace(/\s+/g, ' ').slice(0, 200)
    console.error(JSON.stringify({ level: 'error', what: 'mail-send-failed', via: 'resend', status: res.status, toDomain: domain, detail }))
    return { ok: false, reason: `resend ${res.status}: ${detail}` }
  } catch (e) {
    const reason = e instanceof Error ? e.message : 'network error'
    console.error(JSON.stringify({ level: 'error', what: 'mail-send-failed', via: 'resend', toDomain: domain, reason }))
    return { ok: false, reason }
  }
}

const wrap = (inner: string) => brandEmail(inner)

// The invitation goes to the SECOND party's address (`to`), never to the claimant.
export async function sendInvitationEmail(to: string, claimantName: string, disputeNumber: string, link: string): Promise<MailResult> {
  return deliver(
    to,
    `دعوة إلى وساطة — ${disputeNumber}`,
    wrap(`<p>تمت دعوتك من ${esc(claimantName)} إلى جلسات وساطة إلكترونية على منصة حياة (النزاع ${esc(disputeNumber)}).</p>
        <p>الوساطة اختيارية وسرّية. يمكنك الاطلاع على الدعوة وقبولها من الرابط (سجّل الدخول أو أنشئ حسابًا بهذا البريد نفسه):</p>
        <p><a href="${esc(link)}">${esc(link)}</a></p><p>صلاحية الرابط 7 أيام.</p>`)
  )
}

// Daily anchor: the hash of the newest audit row, mailed outside the database.
export async function sendAnchorEmail(to: string, head: { seq: number; row_hash: string; at: string }): Promise<boolean> {
  const r = await deliver(
    to,
    `نقطة تحقق سجل حياة — الحدث ${head.seq}`,
    wrap(`<p>احتفظ بهذه الرسالة خارج المنصة. تُستخدم لاكتشاف إعادة كتابة السجل لاحقًا.</p>
        <p>رقم آخر حدث: <b dir="ltr">${head.seq}</b></p>
        <p>البصمة: <code dir="ltr">${head.row_hash}</code></p>
        <p>وقت الحدث: ${head.at}</p>`)
  )
  return r.ok
}

// Generic RTL mail. Best-effort: returns false (never throws) when no provider is configured or sending fails.
export async function sendMail(to: string, subject: string, htmlBody: string): Promise<boolean> {
  return (await deliver(to, subject, wrap(htmlBody))).ok
}

// What the admin readiness page and the test button report. Never includes secrets.
export function mailDiagnostics() {
  const provider: 'smtp' | 'resend' | 'none' = smtpConfig() ? 'smtp' : process.env.RESEND_API_KEY ? 'resend' : 'none'
  const restricted = provider === 'resend' && (!process.env.RESEND_FROM || process.env.RESEND_FROM.includes('resend.dev'))
  return { provider, from: fromAddress(), restricted }
}

export async function sendTestEmail(to: string): Promise<MailResult> {
  return deliver(to, 'رسالة اختبار — حياة للعدالة الرقمية', wrap('<p>هذه رسالة اختبار من منصة حياة. وصولها يعني أن إعداد البريد يعمل.</p><p>إن وصلتك في البريد المزعج فاعلِّمها «ليست مزعجة» حتى تصل دعوات الأطراف إلى الوارد.</p>'))
}
