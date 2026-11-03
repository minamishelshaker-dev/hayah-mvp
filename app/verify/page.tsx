'use client'

import Link from 'next/link'
import { useActionState } from 'react'
import { verifyRecord } from './actions'
import SubmitButton from '@/components/SubmitButton'

export default function VerifyPage() {
  const [state, formAction] = useActionState(verifyRecord, {})
  return (
    <main className="mx-auto flex min-h-screen max-w-xl flex-col justify-center px-4 py-10">
      <Link href="/" className="mb-6 text-2xl font-extrabold">حياة<span className="text-gold">.</span></Link>
      <form action={formAction} className="panel space-y-4">
        <div>
          <h1 className="text-xl">التحقق من محضر موثّق</h1>
          <p className="hint">لا يتطلب حسابًا، ولا يكشف إلا رقم النزاع وتاريخ الإصدار. استخدم إحدى الطريقتين:</p>
        </div>
        <div>
          <label className="label" htmlFor="hash">بصمة المحضر (SHA-256)</label>
          <input id="hash" name="hash" dir="ltr" className="input font-mono text-xs" placeholder="64 خانة" />
        </div>
        <div>
          <label className="label" htmlFor="file">أو ملف JSON الصادر عن المنصة</label>
          <input id="file" name="file" type="file" accept="application/json,.json" className="input" />
          <p className="hint mt-1">أي تعديل في محتوى الملف، ولو حرفًا واحدًا، يجعل التحقق يفشل.</p>
        </div>
        {state.error && <p role="alert" className="text-sm font-semibold text-red-700">{state.error}</p>}
        {state.message && <p role="status" className="text-sm font-semibold text-emerald-700">{state.message}</p>}
        <SubmitButton label="تحقق" />
      </form>
    </main>
  )
}
