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
      html: `<div dir="rtl" style="font-family:Tahoma,sans-serif;line-height:1.9">
        <p>تمت دعوتك من ${esc(claimantName)} إلى جلسات وساطة إلكترونية على منصة حياة (النزاع ${esc(disputeNumber)}).</p>
        <p>الوساطة اختيارية وسرّية. يمكنك الاطلاع على الدعوة وقبولها من الرابط:</p>
        <p><a href="${esc(link)}">${esc(link)}</a></p><p>صلاحية الرابط 7 أيام.</p></div>`,
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
      html: `<div dir="rtl" style="font-family:Tahoma,sans-serif;line-height:1.9">
        <p>احتفظ بهذه الرسالة خارج المنصة. تُستخدم لاكتشاف إعادة كتابة السجل لاحقًا.</p>
        <p>رقم آخر حدث: <b dir="ltr">${head.seq}</b></p>
        <p>البصمة: <code dir="ltr">${head.row_hash}</code></p>
        <p>وقت الحدث: ${head.at}</p></div>`,
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
        html: `<div dir="rtl" style="font-family:Tahoma,sans-serif;line-height:1.9">${htmlBody}</div>`,
      }),
    })
    return res.ok
  } catch {
    return false
  }
}
