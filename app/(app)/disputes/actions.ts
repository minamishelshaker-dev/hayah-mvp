'use server'

import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'
import { headers } from 'next/headers'
import { z } from 'zod'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'
import { sha256Hex } from '@/lib/hash'
import { createRoom, dailyEnabled } from '@/lib/daily'
import { sendInvitationEmail } from '@/lib/email'
import { currentActor } from '@/lib/actor'
import { notifyDispute, notifyIfSettlementSigned } from '@/lib/notify'
import { signIssuedRecord } from '@/lib/record-signing'
import { clientIp, rateLimited } from '@/lib/ratelimit'
import { ALLOWED_MIME } from '@/lib/constants'
import { passwordIsValid } from '@/lib/reauth'
import { checkUpload, discardObject } from '@/lib/upload-guard'
import type { ActionResult } from '@/lib/types'

// MVP market segment (a business rule, kept out of the database on purpose).
const MIN_VALUE = 50_000
const MAX_VALUE = 500_000
const MAX_FILE_BYTES = 10 * 1024 * 1024

const disputeSchema = z.object({
  title: z.string().trim().min(5, 'عنوان النزاع قصير جدًا').max(200),
  description: z.string().trim().min(50, 'وصف النزاع يجب ألا يقل عن 50 حرفًا').max(10000),
  dispute_type: z.enum(['commercial', 'civil', 'labor', 'other']),
  dispute_value_egp: z.coerce
    .number()
    .min(MIN_VALUE, `قيمة النزاع يجب ألا تقل عن ${MIN_VALUE.toLocaleString('ar-EG')} جنيه`)
    .max(MAX_VALUE, `قيمة النزاع يجب ألا تتجاوز ${MAX_VALUE.toLocaleString('ar-EG')} جنيه في هذه النسخة`),
  respondent_email: z.string().trim().email('البريد الإلكتروني للطرف الثاني غير صالح'),
  respondent_phone: z.string().trim().optional(),
})

export async function createDispute(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  const parsed = disputeSchema.safeParse(Object.fromEntries(fd))
  if (!parsed.success) return { error: parsed.error.issues[0].message }
  const v = parsed.data

  const supabase = await createClient()
  const { data, error } = await supabase.rpc('create_dispute', {
    p_title: v.title,
    p_description: v.description,
    p_type: v.dispute_type,
    p_value: v.dispute_value_egp,
    p_email: v.respondent_email,
    p_phone: v.respondent_phone ?? '',
  })
  if (error) return { error: error.message }

  const { id, dispute_number, token } = data as { id: string; dispute_number: string; token: string }
  const { data: { user } } = await supabase.auth.getUser()
  const { data: me } = await supabase.from('profiles').select('full_name').eq('id', user?.id ?? '').maybeSingle()
  const base = process.env.NEXT_PUBLIC_APP_URL ?? 'http://localhost:3000'
  try {
    await sendInvitationEmail(v.respondent_email, me?.full_name ?? 'أحد الأطراف', dispute_number, `${base}/invite/${token}`)
  } catch {
    // The invitation link is also shown on the dispute page, so a mail failure is not fatal.
  }
  redirect(`/disputes/${id}`)
}

export async function acceptInvitation(token: string, _fd?: FormData): Promise<ActionResult> {
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('accept_invitation', { p_token: token })
  if (error) return { error: error.message }
  await notifyDispute(data as string, 'respondent_accepted', { roles: ['claimant'] })
  redirect(`/disputes/${data}`)
}

export async function acceptAgreement(disputeId: string, documentId: string, fd: FormData): Promise<ActionResult> {
  if (fd.get('agree') !== 'on') return { error: 'أكّد قراءتك لاتفاقية الوساطة وموافقتك عليها' }
  const actor = await currentActor()
  if (!actor) return { error: 'غير مصرح' }
  const h = await headers()
  // Written by the server: the IP and browser stored next to the consent are what the SERVER observed.
  const { error } = await createAdminClient().rpc('accept_legal_srv', {
    p_actor: actor.id, p_aal: actor.aal, p_document: documentId, p_dispute: disputeId,
    p_ip: await clientIp(), p_ua: h.get('user-agent'),
  })
  if (error) return { error: error.message }
  revalidatePath(`/disputes/${disputeId}`)
  return { message: 'تم تسجيل قبولك.' }
}

export async function proposeMediator(disputeId: string, mediatorId: string, _fd?: FormData): Promise<ActionResult> {
  const { error } = await (await createClient()).rpc('propose_mediator', { p_dispute: disputeId, p_mediator: mediatorId })
  if (error) return { error: error.message }
  await notifyDispute(disputeId, 'mediator_proposed', { roles: ['claimant', 'respondent'], except: (await currentActor())?.id })
  revalidatePath(`/disputes/${disputeId}`)
  return { message: 'تم اقتراح الوسيط. بانتظار موافقة الطرف الآخر.' }
}

export async function partyRespond(disputeId: string, assignmentId: string, approve: boolean, _fd?: FormData): Promise<ActionResult> {
  const { error } = await (await createClient()).rpc('party_respond_mediator', { p_assignment: assignmentId, p_approve: approve })
  if (error) return { error: error.message }
  if (approve) await notifyDispute(disputeId, 'proposal_approved', { roles: [], mediatorOfAssignment: assignmentId })
  else await notifyDispute(disputeId, 'mediator_declined', { roles: ['claimant', 'respondent'], except: (await currentActor())?.id })
  revalidatePath(`/disputes/${disputeId}`)
  return { message: approve ? 'تمت الموافقة. بانتظار قبول الوسيط.' : 'تم رفض الاقتراح.' }
}

export async function mediatorRespond(disputeId: string, assignmentId: string, accept: boolean, _fd?: FormData): Promise<ActionResult> {
  const { error } = await (await createClient()).rpc('mediator_respond', { p_assignment: assignmentId, p_accept: accept })
  if (error) return { error: error.message }
  await notifyDispute(disputeId, accept ? 'mediator_accepted' : 'mediator_declined', { roles: ['claimant', 'respondent'] })
  revalidatePath(`/disputes/${disputeId}`)
  return { message: accept ? 'قبلت المهمة. الوساطة جارية الآن.' : 'تم رفض المهمة.' }
}

export async function scheduleSession(disputeId: string, fd: FormData): Promise<ActionResult> {
  const at = new Date(String(fd.get('scheduled_at') ?? ''))
  const minutes = Number(fd.get('minutes') ?? 60)
  if (Number.isNaN(at.getTime())) return { error: 'موعد الجلسة غير صالح' }

  const supabase = await createClient()
  const { data: sessionId, error } = await supabase.rpc('schedule_session', {
    p_dispute: disputeId,
    p_at: at.toISOString(),
    p_minutes: minutes,
  })
  if (error) return { error: error.message }

  let note = ''
  if (dailyEnabled() && process.env.SUPABASE_SERVICE_ROLE_KEY) {
    try {
      const ttl = Math.max(3600, Math.floor((at.getTime() - Date.now()) / 1000) + minutes * 60 + 7200)
      const room = await createRoom(`hayah-${sessionId}`, ttl)
      const { error: linkError } = await createAdminClient()
        .from('sessions')
        .update({ daily_room_name: room.name, daily_room_url: room.url })
        .eq('id', sessionId as string)
      if (linkError) throw linkError
    } catch {
      note = ' (تعذّر إنشاء غرفة الفيديو، ستعمل الجلسة في وضع العرض.)'
    }
  }
  await notifyDispute(disputeId, 'session_scheduled', { roles: ['claimant', 'respondent'] })
  revalidatePath(`/disputes/${disputeId}`)
  return { message: 'تمت جدولة الجلسة.' + note }
}

export async function saveSettlement(disputeId: string, fd: FormData): Promise<ActionResult> {
  const content = String(fd.get('content') ?? '')
  const { error } = await (await createClient()).rpc('save_settlement', { p_dispute: disputeId, p_content: content })
  if (error) return { error: error.message }
  revalidatePath(`/disputes/${disputeId}`)
  return { message: 'تم حفظ المسودة.' }
}

export async function submitSettlement(disputeId: string, _fd?: FormData): Promise<ActionResult> {
  const { error } = await (await createClient()).rpc('submit_settlement', { p_dispute: disputeId })
  if (error) return { error: error.message }
  await notifyDispute(disputeId, 'settlement_opened', { roles: ['claimant', 'respondent'] })
  revalidatePath(`/disputes/${disputeId}`)
  return { message: 'تم فتح الاتفاق للتوقيع. لم يعد النص قابلًا للتعديل.' }
}

export async function signSettlement(disputeId: string, fd: FormData): Promise<ActionResult> {
  if (fd.get('agree') !== 'on') return { error: 'أكّد قراءتك للاتفاق وموافقتك عليه' }
  const password = String(fd.get('password') ?? '')
  if (!password) return { error: 'أدخل كلمة المرور لتأكيد التوقيع' }
  const expected = String(fd.get('expected_hash') ?? '')
  if (!expected) return { error: 'حدّث الصفحة ثم أعد المحاولة' }

  const actor = await currentActor()
  if (!actor?.email) return { error: 'غير مصرح' }
  if (await rateLimited('sign-password', 5, 600, actor.id, true)) return { error: 'محاولات كثيرة أو تعذّر التحقق من المعدل الآن. انتظر بضع دقائق ثم أعد المحاولة.' }

  if (!(await passwordIsValid(actor.email, password))) return { error: 'كلمة المرور غير صحيحة' }

  // The database accepts a signature only from the server, so this password step cannot be skipped
  // and the IP / browser stored with the signature are the ones the server observed.
  // The signature is bound to the text hash the signer was shown: if the mediator edited the text after the page was rendered, it is refused.
  const h = await headers()
  const { error } = await createAdminClient().rpc('sign_settlement_bound_srv', {
    p_actor: actor.id, p_aal: actor.aal, p_dispute: disputeId, p_expected_hash: expected, p_ip: await clientIp(), p_ua: h.get('user-agent'),
  })
  if (error) return { error: error.message }
  await notifyIfSettlementSigned(disputeId)
  revalidatePath(`/disputes/${disputeId}`)
  return { message: 'تم تسجيل توقيعك.' }
}

export async function registerDocument(input: {
  disputeId: string
  path: string
  fileName: string
  mimeType: string
  size: number
  docType: string
  clientHash: string
}): Promise<ActionResult> {
  const actor = await currentActor()
  if (!actor) return { error: 'غير مصرح' }
  if (await rateLimited('upload', 60, 3600, actor.id)) return { error: 'عدد كبير من الملفات خلال ساعة. حاول لاحقًا.' }
  if (!input.path.startsWith(`${input.disputeId}/`)) return { error: 'مسار الملف غير صالح' }
  if (!ALLOWED_MIME.includes(input.mimeType)) return { error: 'نوع الملف غير مسموح. المسموح: PDF والصور وWord وExcel والنص.' }

  // The server computes the hash itself from what is actually stored.
  const supabase = await createClient()
  const { data: blob, error: dlError } = await supabase.storage.from('documents').download(input.path)
  if (dlError || !blob) return { error: 'تعذّرت قراءة الملف المرفوع' }
  const buffer = Buffer.from(await blob.arrayBuffer())
  if (buffer.length > MAX_FILE_BYTES) return { error: 'حجم الملف يتجاوز 10 ميجابايت' }
  const hash = sha256Hex(buffer)
  if (hash !== input.clientHash) return { error: 'بصمة الملف المخزَّن لا تطابق الملف الأصلي. أعد الرفع.' }
  const rejected = await checkUpload(buffer, input.mimeType, input.fileName)
  if (rejected) { await discardObject(input.path); return { error: rejected } }

  // Only the server can create the document row; the database checks the file really exists in storage.
  const { error } = await createAdminClient().rpc('register_document_srv', {
    p_actor: actor.id, p_aal: actor.aal, p_dispute: input.disputeId, p_path: input.path,
    p_file_name: input.fileName, p_mime: input.mimeType, p_size: buffer.length, p_hash: hash, p_type: input.docType,
  })
  if (error) return { error: error.message }
  revalidatePath(`/disputes/${input.disputeId}`)
  return { message: `تم رفع المستند وتوثيقه. البصمة: ${hash.slice(0, 16)}…` }
}

export async function verifyDocument(docId: string): Promise<ActionResult> {
  const supabase = await createClient()
  const { data: doc } = await supabase.from('documents').select('file_path, sha256_hash').eq('id', docId).maybeSingle()
  if (!doc) return { error: 'المستند غير موجود' }
  const { data: blob, error } = await supabase.storage.from('documents').download(doc.file_path)
  if (error || !blob) return { error: 'تعذّرت قراءة الملف من التخزين' }
  const actual = sha256Hex(Buffer.from(await blob.arrayBuffer()))
  return actual === doc.sha256_hash
    ? { message: 'الملف سليم: البصمة مطابقة لما سُجّل عند الرفع.' }
    : { error: 'تحذير: محتوى الملف اختلف عن النسخة المسجّلة.' }
}

export async function getDocumentUrl(docId: string): Promise<{ url?: string; error?: string }> {
  const supabase = await createClient()
  const { data: doc } = await supabase.from('documents').select('file_path, file_name').eq('id', docId).maybeSingle()
  if (!doc) return { error: 'المستند غير موجود' }
  const { data, error } = await supabase.storage.from('documents').createSignedUrl(doc.file_path, 60, { download: doc.file_name })
  if (error || !data) return { error: 'تعذّر إنشاء رابط التنزيل' }
  return { url: data.signedUrl }
}

export async function issueRecord(disputeId: string, _fd?: FormData): Promise<ActionResult> {
  const { data, error } = await (await createClient()).rpc('issue_dispute_record', { p_dispute: disputeId })
  if (error) return { error: error.message }
  await signIssuedRecord(data as string)
  redirect(`/disputes/${disputeId}/record/${data}`)
}

export async function declineInvitation(token: string, fd: FormData): Promise<ActionResult> {
  const { data, error } = await (await createClient()).rpc('decline_invitation', {
    p_token: token, p_reason: String(fd.get('reason') ?? '') || null,
  })
  if (error) return { error: error.message }
  await notifyDispute(data as string, 'dispute_ended', { roles: ['claimant'] })
  redirect('/dashboard')
}

export async function withdrawDispute(disputeId: string, fd: FormData): Promise<ActionResult> {
  const { error } = await (await createClient()).rpc('withdraw_dispute', {
    p_dispute: disputeId, p_reason: String(fd.get('reason') ?? '') || null,
  })
  if (error) return { error: error.message }
  await notifyDispute(disputeId, 'dispute_ended', { except: (await currentActor())?.id })
  revalidatePath(`/disputes/${disputeId}`)
  return { message: 'تم إنهاء الملف وتسجيل النتيجة.' }
}

export async function mediatorWithdraw(disputeId: string, fd: FormData): Promise<ActionResult> {
  const { error } = await (await createClient()).rpc('mediator_withdraw', {
    p_dispute: disputeId, p_reason: String(fd.get('reason') ?? '') || null,
  })
  if (error) return { error: error.message }
  await notifyDispute(disputeId, 'mediator_withdrew', { roles: ['claimant', 'respondent'] })
  revalidatePath(`/disputes/${disputeId}`)
  redirect('/dashboard')
}

export async function closeDispute(disputeId: string, outcome: string, fd: FormData): Promise<ActionResult> {
  const { error } = await (await createClient()).rpc('close_dispute', {
    p_dispute: disputeId, p_outcome: outcome, p_reason: String(fd.get('reason') ?? '') || null,
  })
  if (error) return { error: error.message }
  await notifyDispute(disputeId, 'dispute_ended', { except: (await currentActor())?.id })
  revalidatePath(`/disputes/${disputeId}`)
  return { message: 'تم إغلاق الملف وتسجيل النتيجة.' }
}

export async function resendInvitation(disputeId: string, fd: FormData): Promise<ActionResult> {
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('resend_invitation', {
    p_dispute: disputeId, p_email: String(fd.get('email') ?? '').trim() || null,
  })
  if (error) return { error: error.message }
  const { token, email } = data as { token: string; email: string }
  const { data: gate } = await supabase.rpc('dispute_gate_info', { p_dispute: disputeId })
  const { data: { user } } = await supabase.auth.getUser()
  const { data: me } = await supabase.from('profiles').select('full_name').eq('id', user?.id ?? '').maybeSingle()
  const base = process.env.NEXT_PUBLIC_APP_URL ?? 'http://localhost:3000'
  let sent = false
  try {
    sent = await sendInvitationEmail(email, me?.full_name ?? 'أحد الأطراف', gate?.dispute_number ?? '', `${base}/invite/${token}`)
  } catch { /* the link is shown on the page anyway */ }
  revalidatePath(`/disputes/${disputeId}`)
  return { message: sent ? `أُرسل رابط جديد إلى ${email}.` : 'صدر رابط جديد. انسخه من أعلى الصفحة وأرسله للطرف الثاني.' }
}

export async function reopenSettlement(disputeId: string, fd: FormData): Promise<ActionResult> {
  const { error } = await (await createClient()).rpc('reopen_settlement', {
    p_dispute: disputeId, p_reason: String(fd.get('reason') ?? '') || null,
  })
  if (error) return { error: error.message }
  await notifyDispute(disputeId, 'settlement_reopened', { roles: ['claimant', 'respondent'] })
  revalidatePath(`/disputes/${disputeId}`)
  return { message: 'أُعيد فتح المسودة للتعديل.' }
}
