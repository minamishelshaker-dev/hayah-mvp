'use client'

import { useActionState } from 'react'
import { createDispute } from '@/app/(app)/disputes/actions'
import SubmitButton from '@/components/SubmitButton'
import ValueFields from '@/components/dispute/ValueFields'
import type { RateLite } from '@/lib/fees'

export default function NewDisputeForm({ rates }: { rates: (RateLite & { rate_date?: string })[] }) {
  const [state, formAction] = useActionState(createDispute, {})
  return (
    <form action={formAction} className="panel mx-auto max-w-2xl space-y-4">
      <div>
        <h1 className="text-xl">تسجيل نزاع جديد</h1>
        <p className="hint">الوساطة اختيارية وسرّية، ولا تبدأ إلا بقبول الطرف الثاني.</p>
      </div>
      <div>
        <label className="label" htmlFor="title">عنوان النزاع</label>
        <input id="title" name="title" required minLength={5} className="input" />
      </div>
      <div>
        <label className="label" htmlFor="description">وصف النزاع (50 حرفًا على الأقل)</label>
        <textarea id="description" name="description" required minLength={50} rows={6} className="input" />
      </div>
      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <label className="label" htmlFor="dispute_type">نوع النزاع</label>
          <select id="dispute_type" name="dispute_type" className="input" defaultValue="commercial">
            <option value="commercial">تجاري</option>
            <option value="civil">مدني</option>
            <option value="labor">عمالي</option>
            <option value="other">أخرى</option>
          </select>
        </div>
      </div>
      <ValueFields rates={rates} />
      <fieldset className="space-y-4 rounded-md border border-navy-100 p-4">
        <legend className="px-2 text-sm font-semibold">بيانات الطرف الثاني</legend>
        <div>
          <label className="label" htmlFor="respondent_email">البريد الإلكتروني</label>
          <input id="respondent_email" name="respondent_email" type="email" required dir="ltr" className="input" />
          <p className="hint mt-1">يجب أن يسجّل الطرف الثاني بهذا البريد نفسه ليتمكن من قبول الدعوة.</p>
        </div>
        <div>
          <label className="label" htmlFor="respondent_phone">الهاتف (اختياري)</label>
          <input id="respondent_phone" name="respondent_phone" type="tel" dir="ltr" className="input" />
        </div>
      </fieldset>
      {state.error && <p role="alert" className="text-sm font-semibold text-red-700">{state.error}</p>}
      <SubmitButton label="تسجيل النزاع وإرسال الدعوة" className="btn btn-primary" />
    </form>
  )
}
