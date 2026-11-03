'use client'

export default function GlobalError({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <html lang="ar" dir="rtl">
      <body style={{ margin: 0, minHeight: '100vh', background: '#F8F6F1', color: '#0A1628', fontFamily: 'Cairo, Tahoma, sans-serif', textAlign: 'center' }}>
        <div style={{ background: '#fff', borderBottom: '1px solid #E6EAF0', padding: '14px 24px' }}>
          <div style={{ fontFamily: "'Great Vibes','Snell Roundhand','Brush Script MT',cursive", fontSize: 44, lineHeight: 1, color: '#C6922A' }}>Hayah</div>
          <div style={{ fontFamily: 'Helvetica, Arial, sans-serif', fontSize: 8, letterSpacing: 4, textTransform: 'uppercase', color: '#C6922A' }}>Digital Justice</div>
        </div>
        <div style={{ maxWidth: 480, margin: '56px auto', padding: '0 20px' }}>
          <h1 style={{ fontSize: 22 }}>حدث خطأ غير متوقع</h1>
          <p style={{ color: '#3A4C63' }}>حاول مرة أخرى، وإن تكرر الخطأ فأبلغ الدعم وأرفق الرمز أدناه.</p>
          {error.digest && <p dir="ltr" style={{ fontFamily: 'monospace', fontSize: 12 }}>{error.digest}</p>}
          <button type="button" onClick={reset} style={{ background: '#0A1628', color: '#fff', border: 0, borderRadius: 6, padding: '10px 18px', fontWeight: 600, cursor: 'pointer' }}>إعادة المحاولة</button>
        </div>
      </body>
    </html>
  )
}
