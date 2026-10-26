import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { safeNext } from '@/lib/utils'

// Email-confirmation landing: exchanges the one-time code for a session.
export async function GET(request: Request) {
  const { searchParams, origin } = new URL(request.url)
  const code = searchParams.get('code')
  const next = safeNext(searchParams.get('next'))
  if (code) {
    const { error } = await (await createClient()).auth.exchangeCodeForSession(code)
    if (!error) return NextResponse.redirect(`${origin}${next}`)
  }
  // Usually: the link was opened in a different browser than the one used to register. The account is confirmed; just sign in.
  return NextResponse.redirect(`${origin}/login?next=${encodeURIComponent(next)}`)
}
