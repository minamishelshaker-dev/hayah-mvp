import { createClient as createPlainClient } from '@supabase/supabase-js'

// Re-checks the signer's password with a throw-away client, so the current session cookies are untouched.
// Used before every in-platform signature (settlement, arbitration agreement, award).
export async function passwordIsValid(email: string, password: string): Promise<boolean> {
  const verifier = createPlainClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const { error } = await verifier.auth.signInWithPassword({ email, password })
  return !error
}
