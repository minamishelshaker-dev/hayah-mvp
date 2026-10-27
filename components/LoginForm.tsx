'use client'

import Link from 'next/link'
import { useActionState } from 'react'
import { login } from '@/app/(auth)/actions'
import SubmitButton from '@/components/SubmitButton'
import AuthShell from '@/components/AuthShell'

export default function LoginForm({ next }: { next: string }) {
  const [state, formAction] = useActionState(login, {})
  return (
    <AuthShell eyebrow="مرحبًا بعودتك" title="تسجيل الدخول" description="ادخل إلى حسابك لمتابعة النزاعات والخطوات المرتبطة بها.">
      <form action={formAction} className="auth-form space-y-4">
        <div className="auth-form-heading">
          <h2>أهلًا بك من جديد</h2>
          <p>أدخل بيانات حسابك للمتابعة.</p>
        </div>
        <input type="hidden" name="next" value={next} />
        <div>
          <label className="label" htmlFor="email">البريد الإلكتروني</label>
          <input id="email" name="email" type="email" required autoComplete="email" dir="ltr" className="input auth-input" placeholder="name@example.com" />
        </div>
        <div>
          <label className="label" htmlFor="password">كلمة المرور</label>
          <input id="password" name="password" type="password" required autoComplete="current-password" dir="ltr" className="input auth-input" placeholder="أدخل كلمة المرور" />
        </div>
        {state.error && <p role="alert" className="auth-alert auth-alert-error">{state.error}</p>}
        <div className="auth-forgot-row">
          <Link className="auth-text-link" href="/forgot-password">نسيت كلمة المرور؟</Link>
        </div>
        <SubmitButton label="تسجيل الدخول" className="btn btn-primary auth-submit w-full" />
        <p className="auth-switch">ليس لديك حساب؟ <Link className="auth-text-link" href={next ? `/register?next=${encodeURIComponent(next)}` : '/register'}>أنشئ حسابًا جديدًا</Link></p>
      </form>
    </AuthShell>
  )
}
