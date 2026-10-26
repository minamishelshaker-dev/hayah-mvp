export type Role = 'party' | 'lawyer' | 'mediator' | 'arbitrator' | 'admin'

export interface Profile {
  id: string
  email: string
  full_name: string
  phone: string | null
  role: Role
  requested_role: Role | null
  bar_number: string | null
  kyc_status: 'pending' | 'verified' | 'rejected'
  created_at: string
}

export interface Dispute {
  id: string
  dispute_number: string
  title: string
  description: string
  dispute_type: 'commercial' | 'civil' | 'labor' | 'other'
  dispute_value_egp: number
  status: string
  created_by: string
  claimant_id: string
  respondent_id: string | null
  mediator_id: string | null
  agreement_document_id: string
  outcome: 'settled' | 'no_settlement' | 'withdrawn' | 'declined' | null
  outcome_reason: string | null
  closed_at: string | null
  created_at: string
}

export interface DocumentRow {
  id: string
  dispute_id: string
  uploaded_by: string
  file_name: string
  file_path: string
  file_size: number
  mime_type: string
  sha256_hash: string
  document_type: string
  created_at: string
}

export interface SessionRow {
  id: string
  dispute_id: string
  session_number: number
  scheduled_at: string
  duration_minutes: number
  daily_room_name: string | null
  daily_room_url: string | null
  status: string
}

export interface Settlement {
  id: string
  dispute_id: string
  content: string
  content_hash: string
  version: number
  status: 'draft' | 'pending_signatures' | 'signed'
}

export interface Signature {
  id: string
  user_id: string
  party_role: 'claimant' | 'respondent'
  content_hash: string
  signed_at: string
}

export interface Assignment {
  id: string
  dispute_id: string
  mediator_id: string
  proposed_by: string
  status: 'proposed' | 'approved' | 'accepted' | 'rejected'
}

export interface AuditLog {
  id: string
  seq: number
  event_type: string
  actor_id: string | null
  dispute_id: string | null
  entity_type: string | null
  previous_state: Record<string, any> | null
  new_state: Record<string, any> | null
  row_hash: string | null
  created_at: string
}

export type ActionResult = { error?: string; message?: string }

export interface RecordEnvelope {
  schema: string
  issued_at: string
  issued_by: { name: string; role: string }
  data: {
    dispute: { number: string; title: string; description: string; type: string; value_egp: number; status: string; created_at: string; outcome?: string | null; outcome_reason?: string | null; closed_at?: string | null }
    parties: { claimant: string | null; respondent: string | null; mediator: string | null }
    consents: { name: string; document: string; kind: string; version: number; document_hash: string; accepted_at: string; ip: string | null }[]
    documents: { file_name: string; type: string; size: number; sha256: string; uploaded_by: string; uploaded_at: string }[]
    sessions: { number: number; scheduled_at: string; duration_minutes: number; status: string }[]
    settlement: null | {
      status: string; version: number; content: string; content_hash: string
      signatures: { name: string; party_role: string; signed_at: string; content_hash: string; ip: string | null }[]
    }
    timeline: { seq: number; event_type: string; at: string; actor: string; state: Record<string, any>; row_hash: string }[]
    chain_check: { checked: number; ok: boolean; first_bad_seq: number | null }
  }
}

// What a member may see of the audit log (whitelisted by public.dispute_timeline; no IP, browser or tokens).
export interface TimelineEntry {
  seq: number
  event_type: string
  created_at: string
  row_hash: string | null
  actor_name: string
  new_state: Record<string, any>
  previous_state: Record<string, any>
}

export interface Arbitration {
  id: string
  arb_number: string
  source_dispute_id: string | null
  title: string
  summary: string
  dispute_value_egp: number
  prior_clause: boolean
  status: 'proposed' | 'agreement' | 'selection' | 'active' | 'deliberation' | 'closed' | 'cancelled'
  claimant_id: string
  respondent_id: string
  arbitrator_id: string | null
  outcome: 'award_issued' | 'terminated' | 'withdrawn' | 'declined' | null
  outcome_reason: string | null
  closed_at: string | null
  created_at: string
}
export interface ArbAssignment { id: string; arbitrator_id: string; proposed_by: string; status: 'proposed' | 'approved' | 'accepted' | 'rejected' | 'ended' }
export interface ArbDocument {
  id: string; arbitration_id: string; uploaded_by: string; file_name: string; file_size: number
  mime_type: string; sha256_hash: string; doc_type: string; created_at: string
}
export interface ArbStep { id: string; seq: number; kind: string; party: 'claimant' | 'respondent'; due_at: string; note: string | null }
export interface ArbSubmission { id: string; step_id: string; submitted_by: string; body: string; document_ids: string[]; late: boolean; submitted_at: string }
export interface ArbHearing { id: string; number: number; scheduled_at: string; duration_minutes: number; status: string }
export interface ArbAward {
  id: string; draft_text: string; draft_hash: string; version: number; status: 'draft' | 'issued'
  signed_document_id: string | null; award_date: string | null; issued_at: string | null
  signing_mode: 'paper' | 'platform' | null; signed_at: string | null; signer_aal: string | null
  platform_signature: string | null; signing_key_id: string | null
}
export interface ArbAgreement {
  id: string; body: string; body_hash: string; version: number; status: 'draft' | 'open' | 'signed'
  opened_at: string | null; signed_at: string | null; platform_signature: string | null; signing_key_id: string | null
}
