import Link from 'next/link'

export default function PageFrame({ children, homeHref = '/', homeLabel = 'الصفحة الرئيسية' }: {
  children: React.ReactNode
  homeHref?: string
  homeLabel?: string
}) {
  return (
    <div className="public-frame">
      <header className="public-frame-header">
        <div className="public-frame-header-inner">
          <Link href="/" className="public-frame-brand" aria-label="حياة — الصفحة الرئيسية">
            <span className="public-frame-brand-mark" aria-hidden="true">ح</span>
            <span><span className="public-frame-brand-name">حياة<span className="public-frame-brand-dot">.</span></span><span className="public-frame-brand-caption">حلول رقمية لتسوية المنازعات</span></span>
          </Link>
          <Link href={homeHref} className="public-frame-home">{homeLabel} <span aria-hidden="true">←</span></Link>
        </div>
      </header>
      <main className="public-frame-main">{children}</main>
      <footer className="public-frame-footer">
        <span>حياة — حلول رقمية لتسوية المنازعات</span>
        <span>خصوصيتك وبياناتك محل اهتمامنا</span>
      </footer>
    </div>
  )
}
