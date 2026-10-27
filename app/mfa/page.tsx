import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { safeNext } from '@/lib/utils'
import MfaEnroll from '@/components/MfaEnroll'
import MfaVerify from '@/components/MfaVerify'
import PageFrame from '@/components/PageFrame'

export default async function MfaPage(props: { searchParams: Promise<{ next?: string }> }) {
  const { next } = await props.searchParams
  const target = safeNext(next)
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: aal } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel()
  if (aal?.currentLevel === 'aal2') redirect(target)

  const { data: factors } = await supabase.auth.mfa.listFactors()
  const verified = factors?.totp?.[0]

  return (
    <PageFrame homeHref="/dashboard" homeLabel="العودة إلى المنصة">
      <div className="mx-auto max-w-lg py-8">
        {verified ? <MfaVerify factorId={verified.id} next={target} /> : <MfaEnroll next={target} />}
        <form action="/auth/signout" method="post" className="mt-4 text-center">
          <button className="hint underline">تسجيل الخروج</button>
        </form>
      </div>
    </PageFrame>
  )
}
