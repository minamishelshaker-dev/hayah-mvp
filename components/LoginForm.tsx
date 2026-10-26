'use client'

import Link from 'next/link'
import { useActionState } from 'react'
import { login } from '@/app/(auth)/actions'
import SubmitButton from '@/components/SubmitButton'

export default function LoginForm({ next }: { next: string }) {
  const [state, formAction] = useActionState(login, {})
  return (
    <main className="mx-auto flex min-h-screen max-w-md flex-col justify-center px-4">
      <Link href="/" className="mb-6 text-2xl font-extrabold">حياة<span className="text-gold">.</span></Link>
      <form action={formAction} className="panel space-y-4">
        <h1 className="text-xl">تسجيل الدخول</h1>
        <input type="hidden" name="next" value={next} />
        <div>
          <label className="label" htmlFor="email">البريد الإلكتروني</label>
          <input id="email" name="email" type="email" required autoComplete="email" dir="ltr" className="input" />
        </div>
        <div>
          <label className="label" htmlFor="password">كلمة المرور</label>
          <input id="password" name="password" type="password" required autoComplete="current-password" dir="ltr" className="input" />
        </div>
        {state.error && <p role="alert" className="text-sm font-semibold text-red-700">{state.error}</p>}
        <SubmitButton label="دخول" />
        <p className="hint"><Link className="font-semibold text-gold-700 underline" href="/forgot-password">نسيت كلمة المرور؟</Link></p>
        <p className="hint">
          ليس لديك حساب؟{' '}
          <Link className="font-semibold text-gold-700 underline" href={next ? `/register?next=${encodeURIComponent(next)}` : '/register'}>أنشئ حسابًا</Link>
        </p>
      </form>
    </main>
  )
}
