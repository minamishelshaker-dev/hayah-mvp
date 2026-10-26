import Link from 'next/link'
import { notFound } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { requireProfile } from '@/lib/auth'
import { STATUS_LABEL, STATUS_TONE, TYPE_LABEL, formatDate, formatEgp } from '@/lib/labels'
import Timeline from '@/components/dispute/Timeline'
import AgreementGate from '@/components/dispute/AgreementGate'
import Lifecycle, { EndedBanner, EndedNotice } from '@/components/dispute/Lifecycle'
import EscalationPanel from '@/components/dispute/EscalationPanel'
import {
  DocumentsPanel, InvitationPanel, MediatorPanel, SessionsPanel, SettlementPanel,
  nm, type MediatorOption, type Names,
} from '@/components/dispute/Panels'
import type { Assignment, Dispute, DocumentRow, SessionRow, Settlement, Signature, TimelineEntry } from '@/lib/types'

const STEPS = ['الدعوة', 'اختيار الوسيط', 'الجلسات', 'صياغة الاتفاق', 'التوقيع']
const STEP_INDEX: Record<string, number> = {
  invited: 0, accepted: 1, mediator_selection: 1, active: 2, settlement_draft: 3, signed: 4, closed: 4, cancelled: 0,
}

export default async function DisputePage(props: { params: Promise<{ id: string }> }) {
  const params = await props.params
  const profile = await requireProfile()
  const supabase = await createClient()

  // Before the agreement is accepted the database lets a member see only the file number and the agreement text.
  const { data: gate } = await supabase.rpc('dispute_gate_info', { p_dispute: params.id })
  if (!gate) notFound()
  if (!gate.accepted) {
    if (['closed', 'cancelled'].includes(gate.status)) return <EndedNotice number={gate.dispute_number} outcome={gate.outcome} />
    return <AgreementGate disputeId={params.id} disputeNumber={gate.dispute_number} doc={gate.doc} role={gate.role} status={gate.status} assignmentId={gate.assignment_id} />
  }

  const { data: row } = await supabase.from('disputes').select('*').eq('id', params.id).maybeSingle()
  if (!row) notFound()
  const d = row as Dispute
  // The admin can read every file; each look is written to the audit log (and shows in the parties' timeline).
  if (profile.role === 'admin') await supabase.rpc('log_admin_view', { p_kind: 'dispute', p_case: d.id })

  const isClaimant = profile.id === d.claimant_id
  const isRespondent = profile.id === d.respondent_id
  const isParty = isClaimant || isRespondent
  const isMediator = profile.id === d.mediator_id

  // Who accepted the agreement (no IP / browser): a whitelisted view, not the raw consent rows.
  const { data: consentRows } = await supabase.rpc('dispute_consents', { p_dispute: d.id })
  const agreed = new Set(((consentRows ?? []) as { user_id: string }[]).map((c) => c.user_id))

  const [docsQ, assignQ, sessionsQ, settlementQ, sigsQ, logsQ, inviteQ] = await Promise.all([
    supabase.from('documents').select('*').eq('dispute_id', d.id).order('created_at'),
    supabase.from('mediator_assignments').select('*').eq('dispute_id', d.id).order('created_at', { ascending: false }),
    supabase.from('sessions').select('*').eq('dispute_id', d.id).order('session_number'),
    supabase.from('settlements').select('*').eq('dispute_id', d.id).maybeSingle(),
    supabase.rpc('dispute_signatures', { p_dispute: d.id }),
    supabase.rpc('dispute_timeline', { p_dispute: d.id }),
    supabase.from('invitations').select('invited_email, token, status, expires_at').eq('dispute_id', d.id).eq('status', 'pending').maybeSingle(),
  ])
  const docs = (docsQ.data ?? []) as DocumentRow[]
  const assignments = (assignQ.data ?? []) as Assignment[]
  const sessions = (sessionsQ.data ?? []) as SessionRow[]
  const settlement = (settlementQ.data ?? null) as Settlement | null
  const signatures = (sigsQ.data ?? []) as Signature[]
  const logs = (logsQ.data ?? []) as TimelineEntry[]

  // Display names for everyone who appears on this page.
  const ids = new Set<string>([d.claimant_id])
  ;[d.respondent_id, d.mediator_id].forEach((x) => x && ids.add(x))
  docs.forEach((x) => ids.add(x.uploaded_by))
  assignments.forEach((a) => { ids.add(a.mediator_id); ids.add(a.proposed_by) })
  // Names only (the database never returns e-mail or phone of other people).
  const { data: people } = await supabase.rpc('profile_names', { p_ids: [...ids] })
  const names: Names = (people ?? {}) as Names

  // Mediator directory, only while a mediator can still be proposed.
  let mediators: MediatorOption[] = []
  if (isParty && ['accepted', 'mediator_selection'].includes(d.status)) {
    const { data: m } = await supabase.rpc('mediator_directory')
    mediators = ((m ?? []) as { id: string; name: string; bio: string | null; specializations: string[] | null; years_experience: number | null }[])
      .map((x) => ({ id: x.id, name: x.name, bio: x.bio, specializations: x.specializations ?? [], years_experience: x.years_experience }))
  }

  const { data: linkedData } = await supabase.rpc('linked_arbitrations', { p_dispute: d.id })
  const linked = (linkedData ?? []) as { id: string; arb_number: string; status: string }[]
  const base = process.env.NEXT_PUBLIC_APP_URL ?? 'http://localhost:3000'
  const step = STEP_INDEX[d.status] ?? 0
  const ended = ['closed', 'cancelled'].includes(d.status)

  return (
    <div className="space-y-5">
      <header className="panel space-y-3">
        <div className="flex flex-wrap items-start justify-between gap-2">
          <div>
            <p dir="ltr" className="text-start text-sm font-semibold text-gold-700">{d.dispute_number}</p>
            <h1 className="text-2xl">{d.title}</h1>
          </div>
          <div className="flex items-center gap-2">
            <Link href={`/disputes/${d.id}/record`} className="btn btn-ghost !py-1">المحضر الموثّق</Link>
            <span className={`badge ${STATUS_TONE[d.status]}`}>{STATUS_LABEL[d.status]}</span>
          </div>
        </div>
        <p className="whitespace-pre-wrap">{d.description}</p>
        <p className="hint">
          {TYPE_LABEL[d.dispute_type]} — {formatEgp(d.dispute_value_egp)} — سُجّل في {formatDate(d.created_at)}
        </p>
        <p className="text-sm">
          <span className="font-semibold">مقدّم النزاع:</span> {nm(names, d.claimant_id)}
          {'  '}<span className="font-semibold">الطرف الثاني:</span> {d.respondent_id ? nm(names, d.respondent_id) : 'لم يقبل الدعوة بعد'}
        </p>
        <p className="text-sm">
          <span className="font-semibold">قبول اتفاقية الوساطة:</span>{' '}
          {([['مقدّم النزاع', d.claimant_id], ['الطرف الثاني', d.respondent_id], ['الوسيط', d.mediator_id]] as const)
            .filter(([, id]) => id)
            .map(([label, id]) => `${label} ${agreed.has(id as string) ? '✓' : '…'}`)
            .join('، ')}
        </p>
        <ol className="flex flex-wrap gap-x-5 gap-y-1 border-t border-navy-100 pt-3 text-sm">
          {STEPS.map((s, i) => (
            <li key={s} className={i < step ? 'font-semibold text-gold-700' : i === step ? 'font-bold' : 'text-navy-500'}>
              {(i + 1).toLocaleString('ar-EG')}. {s}{i < step ? ' ✓' : ''}
            </li>
          ))}
        </ol>
      </header>

      <EndedBanner dispute={d} />

      {d.status === 'invited' && isClaimant && inviteQ.data && (
        <InvitationPanel disputeId={d.id} email={inviteQ.data.invited_email} expiresAt={inviteQ.data.expires_at} link={`${base}/invite/${inviteQ.data.token}`} />
      )}

      {d.status !== 'invited' && (
        <MediatorPanel dispute={d} assignments={assignments} mediators={mediators} names={names} viewerId={profile.id} isParty={isParty} />
      )}

      {d.mediator_id && (
        <SessionsPanel dispute={d} sessions={sessions} canJoin={isParty || isMediator} isMediator={isMediator} />
      )}

      <DocumentsPanel docs={docs} names={names} canUpload={(isParty || isMediator) && !ended} disputeId={d.id} />

      {d.mediator_id && (
        <SettlementPanel dispute={d} settlement={settlement} signatures={signatures} names={names} viewerId={profile.id} isMediator={isMediator} />
      )}

      <EscalationPanel dispute={d} isParty={isParty} linked={linked} />

      <Lifecycle dispute={d} isParty={isParty} isMediator={isMediator} isAdmin={profile.role === 'admin'} settlementLocked={!!settlement && settlement.status !== 'draft'} />

      <Timeline logs={logs} />
    </div>
  )
}
