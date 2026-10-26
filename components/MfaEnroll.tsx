'use client'

import { useEffect, useRef, useState } from 'react'
import { createClient } from '@/lib/supabase/client'

export default function MfaEnroll({ next }: { next: string }) {
  const [factor, setFactor] = useState<{ id: string; qr: string; secret: string } | null>(null)
  const [code, setCode] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const started = useRef(false)

  useEffect(() => {
    if (started.current) return
    started.current = true
    ;(async () => {
      const supabase = createClient()
      // Abandoned, never-verified attempts would otherwise pile up.
      const { data: list } = await supabase.auth.mfa.listFactors()
      for (const f of list?.all ?? []) {
        if (f.status === 'unverified') await supabase.auth.mfa.unenroll({ factorId: f.id })
      }
      const { data, error: eErr } = await supabase.auth.mfa.enroll({ factorType: 'totp', friendlyName: `Hayah-${Date.now()}` })
      if (eErr || !data) return setError('تعذّر بدء التسجيل. تأكد أن TOTP مفعّل في إعدادات المصادقة في Supabase.')
      setFactor({ id: data.id, qr: data.totp.qr_code, secret: data.totp.secret })
    })()
  }, [])

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    if (!factor) return
    setBusy(true)
    setError('')
    const supabase = createClient()
    const { data: challenge, error: cErr } = await supabase.auth.mfa.challenge({ factorId: factor.id })
    if (cErr || !challenge) {
      setError('تعذّر بدء التحقق. حاول مرة أخرى.')
      return setBusy(false)
    }
    const { error: vErr } = await supabase.auth.mfa.verify({ factorId: factor.id, challengeId: challenge.id, code: code.trim() })
    if (vErr) {
      setError('الرمز غير صحيح. تأكد من الوقت على هاتفك وأدخل الرمز الحالي.')
      return setBusy(false)
    }
    window.location.assign(next)
  }

  return (
    <div className="panel space-y-4">
      <h1 className="text-xl">تفعيل التحقق بخطوتين</h1>
      <p className="hint">هذا الحساب يملك صلاحيات حساسة، فلا يُستخدم إلا بعد تفعيل التحقق بخطوتين. ثبّت تطبيق مصادقة (مثل Google Authenticator أو Microsoft Authenticator أو Authy) ثم:</p>
      <ol className="list-inside list-decimal space-y-1 text-sm">
        <li>امسح الرمز أدناه من التطبيق، أو أدخل المفتاح يدويًا.</li>
        <li>أدخل الرمز المكوّن من 6 أرقام الذي يعرضه التطبيق.</li>
      </ol>
      {!factor && !error && <p className="hint">جارٍ تجهيز الرمز…</p>}
      {factor && (
        <>
          <div className="flex flex-wrap items-center gap-4">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={factor.qr} alt="رمز QR لتسجيل تطبيق المصادقة" width={176} height={176} className="rounded border border-navy-100 bg-white p-1" />
            <div className="min-w-0">
              <p className="hint">المفتاح اليدوي:</p>
              <p dir="ltr" className="break-all text-start font-mono text-sm">{factor.secret}</p>
              <p className="hint mt-2">لا تشارك هذا المفتاح مع أحد، واحتفظ به في مكان آمن لاستعادة الحساب عند فقدان الهاتف.</p>
            </div>
          </div>
          <form onSubmit={submit} className="space-y-3 border-t border-navy-100 pt-4">
            <label className="label" htmlFor="code">رمز التحقق</label>
            <input id="code" inputMode="numeric" autoComplete="one-time-code" pattern="[0-9]{6}" maxLength={6} required dir="ltr"
              value={code} onChange={(e) => setCode(e.target.value)} className="input max-w-[10rem] text-center text-lg tracking-widest" />
            <div><button type="submit" disabled={busy} className="btn btn-gold">{busy ? 'جارٍ التحقق…' : 'تفعيل'}</button></div>
          </form>
        </>
      )}
      {error && <p role="alert" className="text-sm font-semibold text-red-700">{error}</p>}
    </div>
  )
}
