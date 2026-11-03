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

// Optional: sends the invitation email through Resend's REST API when RESEND_API_KEY is set.
export async function sendInvitationEmail(to: string, claimantName: string, disputeNumber: string, link: string) {
  const key = process.env.RESEND_API_KEY
  if (!key) return false
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      from: process.env.RESEND_FROM ?? 'Hayah <onboarding@resend.dev>',
      to,
      subject: `دعوة إلى وساطة — ${disputeNumber}`,
      html: brandEmail(`
        <p>تمت دعوتك من ${esc(claimantName)} إلى جلسات وساطة إلكترونية على منصة حياة (النزاع ${esc(disputeNumber)}).</p>
        <p>الوساطة اختيارية وسرّية. يمكنك الاطلاع على الدعوة وقبولها من الرابط:</p>
        <p><a href="${esc(link)}">${esc(link)}</a></p><p>صلاحية الرابط 7 أيام.</p>`),
    }),
  })
  return res.ok
}

// Daily anchor: the hash of the newest audit row, mailed outside the database.
export async function sendAnchorEmail(to: string, head: { seq: number; row_hash: string; at: string }) {
  const key = process.env.RESEND_API_KEY
  if (!key) return false
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      from: process.env.RESEND_FROM ?? 'Hayah <onboarding@resend.dev>',
      to,
      subject: `نقطة تحقق سجل حياة — الحدث ${head.seq}`,
      html: brandEmail(`
        <p>احتفظ بهذه الرسالة خارج المنصة. تُستخدم لاكتشاف إعادة كتابة السجل لاحقًا.</p>
        <p>رقم آخر حدث: <b dir="ltr">${head.seq}</b></p>
        <p>البصمة: <code dir="ltr">${head.row_hash}</code></p>
        <p>وقت الحدث: ${head.at}</p>`),
    }),
  })
  return res.ok
}

// Generic RTL mail. Best-effort: returns false (never throws) when Resend is not configured.
export async function sendMail(to: string, subject: string, htmlBody: string): Promise<boolean> {
  const key = process.env.RESEND_API_KEY
  if (!key) return false
  try {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from: process.env.RESEND_FROM ?? 'Hayah <onboarding@resend.dev>',
        to,
        subject,
        html: brandEmail(`${htmlBody}`),
      }),
    })
    return res.ok
  } catch {
    return false
  }
}
