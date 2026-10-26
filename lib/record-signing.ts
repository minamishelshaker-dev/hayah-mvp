import { createAdminClient } from '@/lib/supabase/admin'
import { signRecord, signingConfigured } from '@/lib/signing'

// Signs a freshly issued record and attaches the signature. Best-effort: an unsigned record is still a valid
// platform-issued record (verifiable on /verify); the readiness page warns when signing is not configured.
export async function signIssuedRecord(exportId: string): Promise<void> {
  try {
    if (!signingConfigured() || !process.env.SUPABASE_SERVICE_ROLE_KEY) return
    const admin = createAdminClient()
    const { data } = await admin.from('record_exports').select('record').eq('id', exportId).maybeSingle()
    if (!data) return
    const signed = signRecord(data.record)
    if (!signed) return
    await admin.rpc('attach_record_signature', { p_export: exportId, p_signature: signed.signature, p_key_id: signed.keyId })
  } catch {
    /* leave unsigned */
  }
}

// Same idea for the arbitration instruments (the agreement and the award): the DATABASE froze the canonical record when the last
// signature landed (signed_record); here the server signs it once with the platform key and attaches the signature.
// Returns false when it could not (no key, or a failure). The signing actions refuse to run without a key, and the panels offer a retry.
export async function signArbInstrument(kind: 'agreement' | 'award', arbId: string): Promise<boolean> {
  try {
    if (!signingConfigured() || !process.env.SUPABASE_SERVICE_ROLE_KEY) return false
    const admin = createAdminClient()
    const table = kind === 'agreement' ? 'arb_agreements' : 'arb_awards'
    const { data } = await admin.from(table).select('signed_record, platform_signature').eq('arbitration_id', arbId).maybeSingle()
    if (!data?.signed_record) return false
    if (data.platform_signature) return true
    const signed = signRecord(data.signed_record)
    if (!signed) return false
    const { error } = await admin.rpc('attach_arb_signature', { p_kind: kind, p_arb: arbId, p_signature: signed.signature, p_key_id: signed.keyId })
    return !error
  } catch {
    return false
  }
}
