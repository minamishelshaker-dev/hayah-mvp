'use client'

export default function GlobalError({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <html lang="ar" dir="rtl">
      <body style={{ fontFamily: 'sans-serif', padding: '3rem', textAlign: 'center' }}>
        <h1>حدث خطأ غير متوقع</h1>
        <p>حاول مرة أخرى، وإن تكرر الخطأ فأبلغ الدعم وأرفق الرمز أدناه.</p>
        {error.digest && <p dir="ltr" style={{ fontFamily: 'monospace' }}>{error.digest}</p>}
        <button type="button" onClick={reset}>إعادة المحاولة</button>
      </body>
    </html>
  )
}
