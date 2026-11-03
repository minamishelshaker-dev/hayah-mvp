'use client'

import Link from 'next/link'
import { useState } from 'react'
import { useActionState } from 'react'
import { register } from '@/app/(auth)/actions'
import SubmitButton from '@/components/SubmitButton'
import AuthShell from '@/components/AuthShell'

export default function RegisterForm({ next }: { next: string }) {
  const [state, formAction] = useActionState(register, {})
  const [role, setRole] = useState('party')
  return (
    <AuthShell eyebrow="ابدأ رحلتك" title="إنشاء حساب جديد" description="أنشئ حسابك للوصول إلى خدمات إدارة وتسوية النزاعات الرقمية.">
      <form action={formAction} className="auth-form auth-form-register space-y-3">
        <div className="auth-form-heading">
          <h2>بيانات الحساب</h2>
          <p>أكمل البيانات التالية للبدء.</p>
        </div>
        <input type="hidden" name="next" value={next} />
        <div>
          <label className="label" htmlFor="full_name">الاسم الكامل</label>
          <input id="full_name" name="full_name" required autoComplete="name" className="input auth-input" placeholder="اكتب اسمك الكامل" />
        </div>
        <div>
          <label className="label" htmlFor="email">البريد الإلكتروني</label>
          <input id="email" name="email" type="email" required autoComplete="email" dir="ltr" className="input auth-input" placeholder="name@example.com" />
        </div>
        <div>
          <label className="label" htmlFor="phone">رقم الهاتف <span className="auth-optional">(اختياري)</span></label>
          <input id="phone" name="phone" type="tel" autoComplete="tel" dir="ltr" className="input auth-input" placeholder="+20" />
        </div>
        <div>
          <label className="label" htmlFor="password">كلمة المرور <span className="auth-optional">(8 أحرف على الأقل)</span></label>
          <input id="password" name="password" type="password" required minLength={8} autoComplete="new-password" dir="ltr" className="input auth-input" placeholder="أنشئ كلمة مرور" />
        </div>
        <div>
          <label className="label" htmlFor="requested_role">نوع الحساب</label>
          <select id="requested_role" name="requested_role" value={role} onChange={(e) => setRole(e.target.value)} className="input auth-input">
            <option value="party">طرف في نزاع</option>
            <option value="lawyer">محامٍ</option>
            <option value="mediator">وسيط</option>
            <option value="arbitrator">محكّم</option>
          </select>
          {(role === 'mediator' || role === 'arbitrator') && <p className="hint mt-1">{role === 'mediator' ? 'حساب الوسيط' : 'حساب المحكّم'} يُفعَّل بعد مراجعة المدير والتحقق من الهوية.</p>}
        </div>
        {role === 'lawyer' && (
          <div>
            <label className="label" htmlFor="bar_number">رقم القيد بالنقابة</label>
            <input id="bar_number" name="bar_number" required className="input auth-input" />
          </div>
        )}
        {state.error && <p role="alert" className="auth-alert auth-alert-error">{state.error}</p>}
        {state.message && <p role="status" className="auth-alert auth-alert-success">{state.message}</p>}
        <SubmitButton label="إنشاء الحساب" className="btn btn-primary auth-submit w-full" />
        <p className="auth-switch">لديك حساب بالفعل؟ <Link className="auth-text-link" href={next ? `/login?next=${encodeURIComponent(next)}` : '/login'}>سجّل الدخول</Link></p>
      </form>
    </AuthShell>
  )
}
