'use client'

import Link from 'next/link'
import { useActionState } from 'react'
import { requestPasswordReset } from '../actions'
import SubmitButton from '@/components/SubmitButton'

export default function ForgotPasswordPage() {
  const [state, formAction] = useActionState(requestPasswordReset, {})
  return (
    <main className="mx-auto flex min-h-screen max-w-md flex-col justify-center px-4">
      <Link href="/" className="mb-6 text-2xl font-extrabold">حياة<span className="text-gold">.</span></Link>
      <form action={formAction} className="panel space-y-4">
        <h1 className="text-xl">استعادة كلمة المرور</h1>
        <div>
          <label className="label" htmlFor="email">البريد الإلكتروني المسجّل</label>
          <input id="email" name="email" type="email" required autoComplete="email" dir="ltr" className="input" />
        </div>
        {state.error && <p role="alert" className="text-sm font-semibold text-red-700">{state.error}</p>}
        {state.message && <p role="status" className="text-sm font-semibold text-emerald-700">{state.message}</p>}
        <SubmitButton label="أرسل رابط الاستعادة" />
        <p className="hint"><Link className="font-semibold text-gold-700 underline" href="/login">العودة لتسجيل الدخول</Link></p>
      </form>
    </main>
  )
}
