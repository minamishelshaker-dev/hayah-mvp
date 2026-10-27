import Link from 'next/link'
import HayahLogo from '@/components/HayahLogo'

export default function PageFrame({ children, homeHref = '/', homeLabel = 'الصفحة الرئيسية' }: {
  children: React.ReactNode
  homeHref?: string
  homeLabel?: string
}) {
  return (
    <div className="public-frame">
      <header className="public-frame-header">
        <div className="public-frame-header-inner">
          <HayahLogo href="/" size="sm" variant="default" className="public-frame-logo" />
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
