'use server'

import { redirect } from 'next/navigation'
import { headers } from 'next/headers'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'
import { currentActor } from '@/lib/actor'
import { clientIp } from '@/lib/ratelimit'
import { safeNext } from '@/lib/utils'
import type { ActionResult } from '@/lib/types'

// Registration documents are accepted ONE BY ONE. None of them is a consent to mediation or arbitration: each procedure has its own agreement.
export async function acceptPlatformTerms(next: string, fd: FormData): Promise<ActionResult> {
  const actor = await currentActor()
  if (!actor) return { error: 'غير مصرح' }
  const supabase = await createClient()
  const { data: kinds } = await supabase.from('legal_kinds').select('kind').eq('scope', 'registration')
  const { data: docs } = await supabase
    .from('legal_documents').select('id, kind, title').eq('is_current', true).in('kind', (kinds ?? []).map((k) => k.kind))
  for (const doc of docs ?? []) {
    if (fd.get(`agree_${doc.kind}`) !== 'on') return { error: `يجب الموافقة على: ${doc.title}` }
  }
  const ua = (await headers()).get('user-agent')
  const ip = await clientIp()
  const admin = createAdminClient()
  for (const doc of docs ?? []) {
    const { error } = await admin.rpc('accept_legal_srv', {
      p_actor: actor.id, p_aal: actor.aal, p_document: doc.id, p_dispute: null, p_ip: ip, p_ua: ua,
    })
    if (error) return { error: error.message }
  }
  redirect(safeNext(next))
}
