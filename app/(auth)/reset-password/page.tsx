'use client'

import { useActionState } from 'react'
import { updatePassword } from '../actions'
import SubmitButton from '@/components/SubmitButton'

export default function ResetPasswordPage() {
  const [state, formAction] = useActionState(updatePassword, {})
  return (
    <main className="mx-auto flex min-h-screen max-w-md flex-col justify-center px-4">
      <form action={formAction} className="panel space-y-4">
        <h1 className="text-xl">تعيين كلمة مرور جديدة</h1>
        <div>
          <label className="label" htmlFor="password">كلمة المرور الجديدة (8 أحرف على الأقل)</label>
          <input id="password" name="password" type="password" required minLength={8} autoComplete="new-password" dir="ltr" className="input" />
        </div>
        <div>
          <label className="label" htmlFor="confirm">تأكيد كلمة المرور</label>
          <input id="confirm" name="confirm" type="password" required minLength={8} autoComplete="new-password" dir="ltr" className="input" />
        </div>
        {state.error && <p role="alert" className="text-sm font-semibold text-red-700">{state.error}</p>}
        <SubmitButton label="حفظ كلمة المرور" />
      </form>
    </main>
  )
}
