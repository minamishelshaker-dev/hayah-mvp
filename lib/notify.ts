import { createAdminClient } from '@/lib/supabase/admin'
import { esc, sendMail } from '@/lib/email'

export type NotifyEvent =
  | 'respondent_accepted' | 'mediator_proposed' | 'proposal_approved' | 'mediator_accepted' | 'mediator_declined'
  | 'session_scheduled' | 'settlement_opened' | 'settlement_reopened' | 'settlement_signed' | 'dispute_ended' | 'mediator_withdrew'

// Deliberately generic: an e-mail never carries the dispute's content, only that something needs attention.
const MESSAGES: Record<NotifyEvent, string> = {
  respondent_accepted: 'قبل الطرف الثاني دعوة الوساطة.',
  mediator_proposed: 'اقترح الطرف الآخر وسيطًا ويحتاج اقتراحه إلى موافقتك.',
  proposal_approved: 'وافق الطرفان على اقتراحك وسيطًا للملف، ويحتاج تعيينك إلى قبولك المهمة.',
  mediator_accepted: 'قبل الوسيط المهمة وبدأت الوساطة.',
  mediator_declined: 'لم يُعتمد الوسيط المقترح. يمكن اقتراح وسيط آخر.',
  session_scheduled: 'حُدِّد موعد جلسة جديدة.',
  settlement_opened: 'فُتح اتفاق التسوية للتوقيع.',
  settlement_reopened: 'أعاد الوسيط فتح مسودة الاتفاق للتعديل قبل التوقيع.',
  settlement_signed: 'اكتمل توقيع اتفاق التسوية من الطرفين.',
  dispute_ended: 'انتهى الملف. اطّلع على نتيجته في المنصة.',
  mediator_withdrew: 'انسحب الوسيط من الملف ويلزم اختيار وسيط آخر.',
}

type Role = 'claimant' | 'respondent' | 'mediator'
const ALL: Role[] = ['claimant', 'respondent', 'mediator']

// Best-effort and silent: a notification problem must never fail the action that triggered it.
export async function notifyDispute(
  disputeId: string,
  event: NotifyEvent,
  opts: { roles?: Role[]; except?: string; mediatorOfAssignment?: string } = {}
): Promise<void> {
  try {
    if (!process.env.RESEND_API_KEY || !process.env.SUPABASE_SERVICE_ROLE_KEY) return
    const admin = createAdminClient()
    const { data: d } = await admin
      .from('disputes').select('dispute_number, claimant_id, respondent_id, mediator_id').eq('id', disputeId).maybeSingle()
    if (!d) return
    const byRole: Record<Role, string | null> = { claimant: d.claimant_id, respondent: d.respondent_id, mediator: d.mediator_id }
    const ids = new Set<string>((opts.roles ?? ALL).map((r) => byRole[r]).filter((x): x is string => !!x))
    if (opts.mediatorOfAssignment) {
      const { data: a } = await admin.from('mediator_assignments').select('mediator_id').eq('id', opts.mediatorOfAssignment).maybeSingle()
      if (a?.mediator_id) ids.add(a.mediator_id)
    }
    if (opts.except) ids.delete(opts.except)
    if (!ids.size) return
    const { data: people } = await admin.from('profiles').select('email').in('id', [...ids])
    const base = process.env.NEXT_PUBLIC_APP_URL ?? 'http://localhost:3000'
    const html = `<p>${esc(MESSAGES[event])}</p><p>الملف: <b dir="ltr">${esc(d.dispute_number)}</b></p>
      <p><a href="${esc(`${base}/disputes/${disputeId}`)}">افتح الملف في المنصة</a></p>
      <p style="color:#666;font-size:12px">لا تتضمن هذه الرسالة تفاصيل النزاع حفاظًا على سريته.</p>`
    await Promise.allSettled((people ?? []).map((p) => sendMail(p.email, `تحديث على الملف ${d.dispute_number}`, html)))
  } catch {
    /* ignore */
  }
}

// After a signature: tell everyone only if it completed the settlement.
export async function notifyIfSettlementSigned(disputeId: string): Promise<void> {
  try {
    if (!process.env.SUPABASE_SERVICE_ROLE_KEY) return
    const { data } = await createAdminClient().from('settlements').select('status').eq('dispute_id', disputeId).maybeSingle()
    if (data?.status === 'signed') await notifyDispute(disputeId, 'settlement_signed')
  } catch {
    /* ignore */
  }
}

export async function notifyUserEmail(userId: string, subject: string, htmlBody: string): Promise<void> {
  try {
    if (!process.env.RESEND_API_KEY || !process.env.SUPABASE_SERVICE_ROLE_KEY) return
    const { data } = await createAdminClient().from('profiles').select('email').eq('id', userId).maybeSingle()
    if (data?.email) await sendMail(data.email, subject, htmlBody)
  } catch {
    /* ignore */
  }
}

export type ArbNotifyEvent =
  | 'escalation_proposed' | 'escalation_answered' | 'agreement_confirmed' | 'arbitrator_proposed' | 'arbitrator_approved'
  | 'arbitrator_seated' | 'arbitrator_declined' | 'step_set' | 'statement_submitted' | 'hearing_scheduled'
  | 'proceedings_closed' | 'award_issued' | 'arbitration_ended' | 'arbitrator_withdrew'
  | 'agreement_opened' | 'agreement_signed'

const ARB_MESSAGES: Record<ArbNotifyEvent, string> = {
  escalation_proposed: 'طُلب تصعيد النزاع إلى التحكيم ويحتاج ردّك.',
  escalation_answered: 'ردّ الطرف الآخر على طلب التحكيم.',
  agreement_confirmed: 'أكّد الطرف الآخر ملف اتفاق التحكيم الموقَّع ويحتاج تأكيدك.',
  arbitrator_proposed: 'اقتُرح محكّم ويحتاج اقتراحه إلى موافقتك.',
  arbitrator_approved: 'وافق الطرفان على اقتراحك محكّمًا، ويحتاج تعيينك إلى قبولك المهمة وتقديم إقرار الاستقلال.',
  arbitrator_seated: 'قبل المحكّم المهمة وبدأت إجراءات التحكيم.',
  arbitrator_declined: 'لم يُعتمد المحكّم المقترح. يمكن اقتراح محكّم آخر.',
  step_set: 'حُدِّد موعد إجرائي جديد في ملف التحكيم.',
  statement_submitted: 'قُدِّمت مذكرة جديدة في ملف التحكيم.',
  hearing_scheduled: 'حُدِّد موعد جلسة تحكيم.',
  proceedings_closed: 'أُقفلت إجراءات التحكيم وبدأت المداولة.',
  award_issued: 'سُجِّل صدور حكم التحكيم. اطّلع عليه في المنصة.',
  arbitration_ended: 'انتهى ملف التحكيم. اطّلع على نتيجته في المنصة.',
  arbitrator_withdrew: 'انسحب المحكّم من الملف ويلزم اختيار محكّم آخر.',
  agreement_opened: 'فُتح نص اتفاق التحكيم للتوقيع على المنصة ويحتاج قراءتك وتوقيعك.',
  agreement_signed: 'وقّع الطرف الآخر اتفاق التحكيم على المنصة. إن لم توقّع بعد فاطّلع عليه ووقّع.',
}

export async function notifyArbitration(
  arbId: string,
  event: ArbNotifyEvent,
  opts: { roles?: ('claimant' | 'respondent' | 'arbitrator')[]; except?: string; arbitratorOfAssignment?: string } = {}
): Promise<void> {
  try {
    if (!process.env.RESEND_API_KEY || !process.env.SUPABASE_SERVICE_ROLE_KEY) return
    const admin = createAdminClient()
    const { data: a } = await admin.from('arbitrations').select('arb_number, claimant_id, respondent_id, arbitrator_id').eq('id', arbId).maybeSingle()
    if (!a) return
    const byRole = { claimant: a.claimant_id, respondent: a.respondent_id, arbitrator: a.arbitrator_id } as Record<string, string | null>
    const ids = new Set<string>((opts.roles ?? ['claimant', 'respondent', 'arbitrator']).map((r) => byRole[r]).filter((x): x is string => !!x))
    if (opts.arbitratorOfAssignment) {
      const { data: s } = await admin.from('arb_assignments').select('arbitrator_id').eq('id', opts.arbitratorOfAssignment).maybeSingle()
      if (s?.arbitrator_id) ids.add(s.arbitrator_id)
    }
    if (opts.except) ids.delete(opts.except)
    if (!ids.size) return
    const { data: people } = await admin.from('profiles').select('email').in('id', [...ids])
    const base = process.env.NEXT_PUBLIC_APP_URL ?? 'http://localhost:3000'
    const html = `<p>${esc(ARB_MESSAGES[event])}</p><p>ملف التحكيم: <b dir="ltr">${esc(a.arb_number)}</b></p>
      <p><a href="${esc(`${base}/arbitrations/${arbId}`)}">افتح الملف في المنصة</a></p>
      <p style="color:#666;font-size:12px">لا تتضمن هذه الرسالة تفاصيل النزاع حفاظًا على سريته.</p>`
    await Promise.allSettled((people ?? []).map((p) => sendMail(p.email, `تحديث على ملف التحكيم ${a.arb_number}`, html)))
  } catch {
    /* ignore */
  }
}
