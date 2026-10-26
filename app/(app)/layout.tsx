import Link from 'next/link'
import { headers } from 'next/headers'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { requireProfile } from '@/lib/auth'
import { ROLE_LABEL } from '@/lib/labels'

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const profile = await requireProfile()
  const path = (await headers()).get('x-pathname') ?? '/dashboard'
  // Admins and mediators must pass the second step. The database enforces it too; this only sends them to the right page.
  const { data: mfa } = await (await createClient()).rpc('mfa_status')
  if (mfa?.required && !mfa.ok) redirect(`/mfa?next=${encodeURIComponent(path)}`)
  // Nobody uses the platform before accepting the current terms and privacy policy (admins are exempt).
  if (profile.role !== 'admin') {
    const { data: accepted } = await (await createClient()).rpc('has_platform_consent')
    if (!accepted) redirect(`/consent?next=${encodeURIComponent(path)}`)
  }
  return (
    <div className="min-h-screen">
      <header className="border-b border-navy-100 bg-white print:hidden">
        <div className="mx-auto flex max-w-5xl flex-wrap items-center justify-between gap-3 px-4 py-3">
          <div className="flex items-center gap-5">
            <Link href="/dashboard" className="text-xl font-extrabold">حياة<span className="text-gold">.</span></Link>
            <nav className="flex gap-4 text-sm font-semibold">
              <Link href="/dashboard" className="hover:text-gold-700">نزاعاتي</Link>
              {!['mediator', 'arbitrator', 'admin'].includes(profile.role) && (
                <Link href="/disputes/new" className="hover:text-gold-700">نزاع جديد</Link>
              )}
              {profile.role === 'admin' && (
                <>
                  <Link href="/admin" className="hover:text-gold-700">كل النزاعات</Link>
                  <Link href="/admin/users" className="hover:text-gold-700">المستخدمون</Link>
                  <Link href="/admin/audit" className="hover:text-gold-700">سجل التدقيق</Link>
                  <Link href="/admin/metrics" className="hover:text-gold-700">المؤشرات</Link>
                  <Link href="/admin/legal" className="hover:text-gold-700">النصوص القانونية</Link>
                </>
              )}
            </nav>
          </div>
          <div className="flex items-center gap-3 text-sm">
            <span>{profile.full_name}</span>
            <span className="badge bg-gold-100 text-gold-700">{ROLE_LABEL[profile.role]}</span>
            <form action="/auth/signout" method="post">
              <button className="btn btn-ghost !px-3 !py-1">خروج</button>
            </form>
          </div>
        </div>
      </header>
      <main className="mx-auto max-w-5xl px-4 py-8">{children}</main>
    </div>
  )
}
