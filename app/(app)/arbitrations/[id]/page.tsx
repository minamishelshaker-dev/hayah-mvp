import { notFound } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { requireProfile } from '@/lib/auth'
import Timeline from '@/components/dispute/Timeline'
import { arbAgreementTemplate } from '@/lib/arb-agreement-template'
import {
  AgreementPanel, ArbDocumentsPanel, ArbGate, ArbHeader, ArbLifecycle, AwardPanel, EndedNotice,
  ProcedurePanel, ProposedPanel, SelectionPanel, type Neutral,
} from '@/components/arbitration/Panels'
import type { ArbAgreement, ArbAssignment, ArbAward, ArbDocument, ArbHearing, ArbStep, ArbSubmission, Arbitration, TimelineEntry } from '@/lib/types'

export default async function ArbitrationPage(props: { params: Promise<{ id: string }> }) {
  const params = await props.params
  const profile = await requireProfile()
  const supabase = await createClient()

  // Before the rules are accepted the database shows a member only the file number and the rules text.
  const { data: gate } = await supabase.rpc('arb_gate_info', { p_arb: params.id })
  if (!gate) notFound()
  if (!gate.accepted) {
    if (['closed', 'cancelled'].includes(gate.status)) return <EndedNotice number={gate.number} outcome={gate.outcome} />
    return <ArbGate arbId={params.id} number={gate.number} doc={gate.doc} role={gate.role} status={gate.status} assignmentId={gate.assignment_id} />
  }

  const { data: row } = await supabase.from('arbitrations').select('*').eq('id', params.id).maybeSingle()
  if (!row) notFound()
  const arb = row as Arbitration
  // The admin can read every file; each look is written to the audit log (and shows in the parties' timeline).
  if (profile.role === 'admin') await supabase.rpc('log_admin_view', { p_kind: 'arbitration', p_case: arb.id })
  const isClaimant = profile.id === arb.claimant_id
  const isRespondent = profile.id === arb.respondent_id
  const isParty = isClaimant || isRespondent
  const isArbitrator = profile.id === arb.arbitrator_id

  const [assignQ, docsQ, stepsQ, subsQ, hearQ, awardQ, confQ, rulesQ, tlQ, agrQ, signersQ] = await Promise.all([
    supabase.from('arb_assignments').select('*').eq('arbitration_id', arb.id).order('created_at', { ascending: false }),
    supabase.from('arb_documents').select('*').eq('arbitration_id', arb.id).order('created_at'),
    supabase.from('arb_steps').select('*').eq('arbitration_id', arb.id).order('seq'),
    supabase.from('arb_submissions').select('*').eq('arbitration_id', arb.id).order('submitted_at'),
    supabase.from('arb_hearings').select('*').eq('arbitration_id', arb.id).order('number'),
    supabase.from('arb_awards').select('*').eq('arbitration_id', arb.id).maybeSingle(),
    supabase.rpc('arb_confirmations', { p_arb: arb.id }),
    supabase.rpc('arb_rules_status', { p_arb: arb.id }),
    supabase.rpc('arb_timeline', { p_arb: arb.id }),
    supabase.from('arb_agreements').select('*').eq('arbitration_id', arb.id).maybeSingle(),
    supabase.rpc('arb_agreement_signers', { p_arb: arb.id }),
  ])
  const assignments = (assignQ.data ?? []) as ArbAssignment[]
  const docs = (docsQ.data ?? []) as ArbDocument[]
  const steps = (stepsQ.data ?? []) as ArbStep[]
  const submissions = (subsQ.data ?? []) as ArbSubmission[]
  const hearings = (hearQ.data ?? []) as ArbHearing[]
  const award = (awardQ.data ?? null) as ArbAward | null
  const confirmations = (confQ.data ?? []) as { user_id: string; document_id: string; confirmed_at: string }[]
  const rulesAccepted = ((rulesQ.data ?? []) as { user_id: string }[]).map((r) => r.user_id)
  const timeline = (tlQ.data ?? []) as TimelineEntry[]
  const agreement = (agrQ.data ?? null) as ArbAgreement | null
  const signers = (signersQ.data ?? []) as { user_id: string; signed_at: string }[]

  const ids = new Set<string>([arb.claimant_id, arb.respondent_id])
  if (arb.arbitrator_id) ids.add(arb.arbitrator_id)
  assignments.forEach((a) => { ids.add(a.arbitrator_id); ids.add(a.proposed_by) })
  docs.forEach((d) => ids.add(d.uploaded_by))
  submissions.forEach((s) => ids.add(s.submitted_by))
  confirmations.forEach((c) => ids.add(c.user_id))
  signers.forEach((x) => ids.add(x.user_id))
  const { data: people } = await supabase.rpc('profile_names', { p_ids: [...ids] })
  const names = (people ?? {}) as Record<string, string>

  let directory: Neutral[] = []
  if (isParty && arb.status === 'selection') {
    const { data: m } = await supabase.rpc('arbitrator_directory')
    directory = ((m ?? []) as { id: string; name: string; bio: string | null; specializations: string[] | null; years_experience: number | null }[])
      .map((x) => ({ id: x.id, name: x.name, bio: x.bio, specializations: x.specializations ?? [], years_experience: x.years_experience }))
  }
  const beyondAgreement = ['selection', 'active', 'deliberation', 'closed'].includes(arb.status)
  const template = arbAgreementTemplate({
    arbNumber: arb.arb_number, claimant: names[arb.claimant_id] ?? '[اسم الطرف الأول]',
    respondent: names[arb.respondent_id] ?? '[اسم الطرف الثاني]', valueEgp: arb.dispute_value_egp,
  })

  return (
    <div className="space-y-5">
      <ArbHeader arb={arb} names={names} rulesAccepted={rulesAccepted} />

      {arb.status === 'proposed' && <ProposedPanel arb={arb} isRespondent={isRespondent} />}
      {(arb.status === 'agreement' || (beyondAgreement && (agreement?.status === 'signed' || docs.some((d) => d.doc_type === 'arbitration_agreement')))) && (
        <AgreementPanel arb={arb} docs={docs} confirmations={confirmations} names={names} viewerId={profile.id} isParty={isParty && arb.status === 'agreement'}
          agreement={agreement} signers={signers} template={template} />
      )}
      {arb.status === 'selection' && (
        <SelectionPanel arb={arb} assignments={assignments} directory={directory} names={names} viewerId={profile.id} isParty={isParty} />
      )}
      {['active', 'deliberation', 'closed'].includes(arb.status) && arb.arbitrator_id && (
        <ProcedurePanel arb={arb} steps={steps} submissions={submissions} docs={docs} hearings={hearings} names={names}
          viewerId={profile.id} isArbitrator={isArbitrator} isParty={isParty} />
      )}
      <AwardPanel arb={arb} award={award} docs={docs} isArbitrator={isArbitrator} />
      <ArbDocumentsPanel docs={docs} names={names} />
      <ArbLifecycle arb={arb} isParty={isParty} isArbitrator={isArbitrator} />
      <Timeline logs={timeline} />
    </div>
  )
}
