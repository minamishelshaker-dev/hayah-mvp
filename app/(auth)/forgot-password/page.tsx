'use client'

import Link from 'next/link'
import { useActionState } from 'react'
import { requestPasswordReset } from '../actions'
import SubmitButton from '@/components/SubmitButton'
import AuthShell from '@/components/AuthShell'

export default function ForgotPasswordPage() {
  const [state, formAction] = useActionState(requestPasswordReset, {})
  return (
    <AuthShell eyebrow="استعادة الوصول" title="استعادة كلمة المرور" description="سنساعدك على استعادة الوصول إلى حسابك باستخدام بريدك الإلكتروني المسجّل.">
      <form action={formAction} className="auth-form space-y-4">
        <div className="auth-form-heading">
          <h2>استعادة حسابك</h2>
          <p>أدخل البريد الإلكتروني المرتبط بحسابك.</p>
        </div>
        <div>
          <label className="label" htmlFor="email">البريد الإلكتروني المسجّل</label>
          <input id="email" name="email" type="email" required autoComplete="email" dir="ltr" className="input auth-input" placeholder="name@example.com" />
        </div>
        {state.error && <p role="alert" className="auth-alert auth-alert-error">{state.error}</p>}
        {state.message && <p role="status" className="auth-alert auth-alert-success">{state.message}</p>}
        <SubmitButton label="إرسال رابط الاستعادة" className="btn btn-primary auth-submit w-full" />
        <p className="auth-switch"><Link className="auth-text-link" href="/login">العودة إلى تسجيل الدخول</Link></p>
      </form>
    </AuthShell>
  )
}
