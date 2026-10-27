import Link from 'next/link'

export default function AuthShell({ children, eyebrow, title, description }: { children: React.ReactNode; eyebrow: string; title: string; description: string }) {
  return (
    <main className="auth-page">
      <div className="auth-glow auth-glow-one" aria-hidden="true" />
      <div className="auth-glow auth-glow-two" aria-hidden="true" />
      <div className="auth-layout">
        <header className="auth-header">
          <Link href="/" className="auth-brand" aria-label="حياة — الصفحة الرئيسية">
            <span className="auth-brand-mark" aria-hidden="true">ح</span>
            <span>حياة<span className="auth-brand-dot">.</span></span>
          </Link>
          <Link href="/" className="auth-home-link">العودة إلى الرئيسية <span aria-hidden="true">←</span></Link>
        </header>
        <div className="auth-content">
          <section className="auth-intro">
            <span className="auth-eyebrow"><span className="auth-eyebrow-dot" /> {eyebrow}</span>
            <h1>{title}</h1>
            <p>{description}</p>
            <div className="auth-promise">
              <span className="auth-promise-icon" aria-hidden="true">✓</span>
              <span>مساحة رقمية منظمة لإدارة خطوات تسوية النزاع بوضوح.</span>
            </div>
          </section>
          <section className="auth-form-card">
            {children}
          </section>
        </div>
        <footer className="auth-footer">
          <span>حياة — حلول رقمية لتسوية المنازعات</span>
          <span>خصوصيتك وبياناتك محل اهتمامنا</span>
        </footer>
      </div>
    </main>
  )
}
