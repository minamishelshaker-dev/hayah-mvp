'use client'

import Link from 'next/link'
import { useState } from 'react'
import { useActionState } from 'react'
import { register } from '@/app/(auth)/actions'
import SubmitButton from '@/components/SubmitButton'

export default function RegisterForm({ next }: { next: string }) {
  const [state, formAction] = useActionState(register, {})
  const [role, setRole] = useState('party')
  return (
    <main className="mx-auto flex min-h-screen max-w-md flex-col justify-center px-4 py-10">
      <Link href="/" className="mb-6 text-2xl font-extrabold">حياة<span className="text-gold">.</span></Link>
      <form action={formAction} className="panel space-y-4">
        <h1 className="text-xl">إنشاء حساب</h1>
        <input type="hidden" name="next" value={next} />
        <div>
          <label className="label" htmlFor="full_name">الاسم الكامل</label>
          <input id="full_name" name="full_name" required className="input" />
        </div>
        <div>
          <label className="label" htmlFor="email">البريد الإلكتروني</label>
          <input id="email" name="email" type="email" required autoComplete="email" dir="ltr" className="input" />
        </div>
        <div>
          <label className="label" htmlFor="phone">الهاتف (اختياري)</label>
          <input id="phone" name="phone" type="tel" dir="ltr" className="input" />
        </div>
        <div>
          <label className="label" htmlFor="password">كلمة المرور (8 أحرف على الأقل)</label>
          <input id="password" name="password" type="password" required minLength={8} autoComplete="new-password" dir="ltr" className="input" />
        </div>
        <div>
          <label className="label" htmlFor="requested_role">صفتي</label>
          <select id="requested_role" name="requested_role" value={role} onChange={(e) => setRole(e.target.value)} className="input">
            <option value="party">طرف في نزاع</option>
            <option value="lawyer">محامٍ</option>
            <option value="mediator">وسيط</option>
            <option value="arbitrator">محكّم</option>
          </select>
          {(role === 'mediator' || role === 'arbitrator') && <p className="hint mt-1">حساب {role === 'mediator' ? 'الوسيط' : 'المحكّم'} يُفعَّل بعد مراجعة المدير والتحقق من هويتك.</p>}
        </div>
        {role === 'lawyer' && (
          <div>
            <label className="label" htmlFor="bar_number">رقم القيد بالنقابة</label>
            <input id="bar_number" name="bar_number" required className="input" />
          </div>
        )}
        {state.error && <p role="alert" className="text-sm font-semibold text-red-700">{state.error}</p>}
        {state.message && <p role="status" className="text-sm font-semibold text-emerald-700">{state.message}</p>}
        <SubmitButton label="إنشاء الحساب" />
        <p className="hint">
          لديك حساب؟{' '}
          <Link className="font-semibold text-gold-700 underline" href={next ? `/login?next=${encodeURIComponent(next)}` : '/login'}>سجّل الدخول</Link>
        </p>
      </form>
    </main>
  )
}
