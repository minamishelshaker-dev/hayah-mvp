import { createClient } from '@supabase/supabase-js'

// Service-role client: bypasses RLS. Use ONLY inside server actions/route handlers,
// and only after checking the caller's permission with the user-scoped client.
export const createAdminClient = () =>
  createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY!, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
