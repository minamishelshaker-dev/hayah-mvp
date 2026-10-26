'use client'

import { useEffect } from 'react'

export default function Error({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  useEffect(() => { console.error('ui-error', error.digest ?? '', error.message) }, [error])
  return (
    <div className="panel mx-auto mt-10 max-w-lg space-y-3 text-center" role="alert">
      <h1 className="text-xl">حدث خطأ غير متوقع</h1>
      <p className="hint">لم تُفقد بياناتك. حاول مرة أخرى، وإن تكرر الخطأ فأبلغ الدعم وأرفق الرمز أدناه.</p>
      {error.digest && <p dir="ltr" className="font-mono text-xs text-navy-500">{error.digest}</p>}
      <button type="button" onClick={reset} className="btn btn-primary">إعادة المحاولة</button>
    </div>
  )
}
