import { createClient } from '@/lib/supabase/server'

// The identity the SERVER has verified (getUser asks the auth server; it never trusts client-sent ids).
// Evidence writes (documents, signatures, consents) are made with this actor through service-only functions.
export async function currentActor(): Promise<{ id: string; email: string; aal: 'aal1' | 'aal2' } | null> {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return null
  const { data: aal } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel()
  return { id: user.id, email: user.email ?? '', aal: aal?.currentLevel === 'aal2' ? 'aal2' : 'aal1' }
}
