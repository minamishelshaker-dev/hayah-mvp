import { headers } from 'next/headers'
import { createAdminClient } from '@/lib/supabase/admin'

export async function clientIp(): Promise<string | null> {
  const h = await headers()
  return h.get('x-forwarded-for')?.split(',')[0]?.trim() || h.get('x-real-ip') || null
}

// TRUE = the caller is over the limit. Counters live in the database, so they are shared by all serverless instances.
// By default it fails OPEN if the limiter itself is unavailable (availability over blocking); the readiness page checks the service key.
// Pass failClosed = true where a broken limiter would remove the only brake on guessing (the password re-check before a signature):
// then "limiter unavailable" is treated as "over the limit" and the action is refused until it recovers.
export async function rateLimited(scope: string, limit: number, windowSeconds: number, subject?: string, failClosed = false): Promise<boolean> {
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) return failClosed
  const who = subject ?? (await clientIp()) ?? 'unknown'
  try {
    const { data, error } = await createAdminClient().rpc('rate_limit_hit', {
      p_key: `${scope}:${who}`, p_limit: limit, p_window_seconds: windowSeconds,
    })
    if (error) return failClosed
    return data === true
  } catch {
    return failClosed
  }
}
