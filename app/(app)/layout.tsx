import Link from 'next/link'
import HayahLogo from '@/components/HayahLogo'
import { headers } from 'next/headers'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { requireProfile } from '@/lib/auth'
import { ROLE_LABEL } from '@/lib/labels'

function NavLink({ href, currentPath, children }: { href: string; currentPath: string; children: React.ReactNode }) {
  const active = href === '/dashboard'
    ? currentPath === href
    : currentPath === href || currentPath.startsWith(href + '/')
  return <Link href={href} className="app-nav-link" aria-current={active ? 'page' : undefined}>{children}</Link>
}

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const profile = await requireProfile()
  const path = (await headers()).get('x-pathname') ?? '/dashboard'
  const { data: mfa } = await (await createClient()).rpc('mfa_status')
  if (mfa?.required && !mfa.ok) redirect(`/mfa?next=${encodeURIComponent(path)}`)
  if (profile.role !== 'admin') {
    const { data: accepted } = await (await createClient()).rpc('has_platform_consent')
    if (!accepted) redirect(`/consent?next=${encodeURIComponent(path)}`)
  }

  return (
    <div className="app-shell">
      <header className="app-header print:hidden">
        <div className="app-header-inner">
          <HayahLogo href="/dashboard" size="sm" variant="default" className="app-header-logo" />
          <nav className="app-nav" aria-label="التنقل الرئيسي">
            <NavLink href="/dashboard" currentPath={path}>لوحة التحكم</NavLink>
            {!['mediator', 'arbitrator', 'admin'].includes(profile.role) && (
              <NavLink href="/disputes/new" currentPath={path}>تسجيل نزاع</NavLink>
            )}
            {profile.role !== 'admin' && (
              <NavLink href="/sessions" currentPath={path}>الجلسات</NavLink>
            )}
            {profile.role === 'admin' && (
              <>
                <NavLink href="/admin" currentPath={path}>كل النزاعات</NavLink>
                <NavLink href="/admin/users" currentPath={path}>المستخدمون</NavLink>
                <NavLink href="/admin/audit" currentPath={path}>سجل التدقيق</NavLink>
                <NavLink href="/admin/metrics" currentPath={path}>المؤشرات</NavLink>
                <NavLink href="/admin/legal" currentPath={path}>النصوص القانونية</NavLink>
              </>
            )}
          </nav>
          <div className="app-user">
            <span className="app-user-name">{profile.full_name}</span>
            <span className="badge bg-gold-100 text-gold-700">{ROLE_LABEL[profile.role]}</span>
            <form action="/auth/signout" method="post">
              <button className="btn btn-ghost !px-3 !py-1">خروج</button>
            </form>
          </div>
        </div>
      </header>
      <main className="app-main">{children}</main>
      <footer className="app-footer print:hidden">
        <div className="app-footer-inner">
          <span>حياة — حلول رقمية لتسوية المنازعات</span>
          <span>خصوصيتك وبياناتك محل اهتمامنا</span>
        </div>
      </footer>
    </div>
  )
}
