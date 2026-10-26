'use client'

import { useState } from 'react'
import { createClient } from '@/lib/supabase/client'

export default function MfaVerify({ factorId, next }: { factorId: string; next: string }) {
  const [code, setCode] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    setBusy(true)
    setError('')
    const supabase = createClient()
    const { data: challenge, error: cErr } = await supabase.auth.mfa.challenge({ factorId })
    if (cErr || !challenge) {
      setError('تعذّر بدء التحقق. حاول مرة أخرى.')
      return setBusy(false)
    }
    const { error: vErr } = await supabase.auth.mfa.verify({ factorId, challengeId: challenge.id, code: code.trim() })
    if (vErr) {
      setError('الرمز غير صحيح أو انتهت صلاحيته. أدخل الرمز الحالي من التطبيق.')
      return setBusy(false)
    }
    window.location.assign(next) // full reload so the server sees the upgraded session
  }

  return (
    <form onSubmit={submit} className="panel space-y-4">
      <h1 className="text-xl">التحقق بخطوتين</h1>
      <p className="hint">أدخل الرمز المكوّن من 6 أرقام الظاهر الآن في تطبيق المصادقة على هاتفك.</p>
      <div>
        <label className="label" htmlFor="code">رمز التحقق</label>
        <input id="code" inputMode="numeric" autoComplete="one-time-code" pattern="[0-9]{6}" maxLength={6} required dir="ltr"
          value={code} onChange={(e) => setCode(e.target.value)} className="input max-w-[10rem] text-center text-lg tracking-widest" />
      </div>
      {error && <p role="alert" className="text-sm font-semibold text-red-700">{error}</p>}
      <button type="submit" disabled={busy} className="btn btn-primary">{busy ? 'جارٍ التحقق…' : 'تحقق'}</button>
    </form>
  )
}
