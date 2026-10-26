'use server'

import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'
import { headers } from 'next/headers'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'
import { currentActor } from '@/lib/actor'
import { clientIp, rateLimited } from '@/lib/ratelimit'
import { sha256Hex } from '@/lib/hash'
import { createRoom, dailyEnabled } from '@/lib/daily'
import { notifyArbitration } from '@/lib/notify'
import { ALLOWED_MIME } from '@/lib/constants'
import { passwordIsValid } from '@/lib/reauth'
import { signingConfigured } from '@/lib/signing'
import { signArbInstrument } from '@/lib/record-signing'
import { checkUpload, discardObject } from '@/lib/upload-guard'
import type { ActionResult } from '@/lib/types'

const MAX_FILE_BYTES = 10 * 1024 * 1024
const text = (fd: FormData, k: string) => String(fd.get(k) ?? '')
const reasonOf = (fd: FormData) => text(fd, 'reason') || null

// ------------------------------------------------------------------ escalation from a mediation file
export async function proposeEscalation(disputeId: string, fd: FormData): Promise<ActionResult> {
  const value = Number(text(fd, 'value'))
  const { data, error } = await (await createClient()).rpc('propose_escalation', {
    p_dispute: disputeId, p_title: text(fd, 'title'), p_summary: text(fd, 'summary'),
    p_value: Number.isFinite(value) ? value : 0, p_prior_clause: fd.get('prior_clause') === 'on',
  })
  if (error) return { error: error.message }
  await notifyArbitration(data as string, 'escalation_proposed', { roles: ['respondent'] })
  redirect(`/arbitrations/${data}`)
}

export async function acceptArbRules(arbId: string, documentId: string, fd: FormData): Promise<ActionResult> {
  if (fd.get('agree') !== 'on') return { error: 'أكّد قراءتك لقواعد التحكيم وموافقتك عليها' }
  const actor = await currentActor()
  if (!actor) return { error: 'غير مصرح' }
  const { error } = await createAdminClient().rpc('accept_arb_rules_srv', {
    p_actor: actor.id, p_aal: actor.aal, p_document: documentId, p_arb: arbId,
    p_ip: await clientIp(), p_ua: (await headers()).get('user-agent'),
  })
  if (error) return { error: error.message }
  revalidatePath(`/arbitrations/${arbId}`)
  return { message: 'تم تسجيل قبولك.' }
}

export async function respondEscalation(arbId: string, accept: boolean, fd: FormData): Promise<ActionResult> {
  const { error } = await (await createClient()).rpc('respond_escalation', { p_arb: arbId, p_accept: accept, p_reason: reasonOf(fd) })
  if (error) return { error: error.message }
  await notifyArbitration(arbId, 'escalation_answered', { roles: ['claimant'] })
  revalidatePath(`/arbitrations/${arbId}`)
  return { message: accept ? 'وافقت على التحكيم. الخطوة التالية اتفاق التحكيم الموقَّع.' : 'تم رفض طلب التحكيم.' }
}

export async function withdrawArbitration(arbId: string, fd: FormData): Promise<ActionResult> {
  const { error } = await (await createClient()).rpc('withdraw_arbitration', { p_arb: arbId, p_reason: reasonOf(fd) })
  if (error) return { error: error.message }
  await notifyArbitration(arbId, 'arbitration_ended', { except: (await currentActor())?.id })
  revalidatePath(`/arbitrations/${arbId}`)
  return { message: 'تم إنهاء الملف وتسجيل النتيجة.' }
}

// ------------------------------------------------------------------ documents (the server writes the evidence row)
export async function registerArbDocument(input: {
  arbId: string; path: string; fileName: string; mimeType: string; size: number; docType: string; clientHash: string
}): Promise<ActionResult> {
  const actor = await currentActor()
  if (!actor) return { error: 'غير مصرح' }
  if (await rateLimited('upload', 60, 3600, actor.id)) return { error: 'عدد كبير من الملفات خلال ساعة. حاول لاحقًا.' }
  if (!input.path.startsWith(`${input.arbId}/`)) return { error: 'مسار الملف غير صالح' }
  if (!ALLOWED_MIME.includes(input.mimeType)) return { error: 'نوع الملف غير مسموح. المسموح: PDF والصور وWord وExcel والنص.' }

  const supabase = await createClient()
  const { data: blob, error: dlError } = await supabase.storage.from('documents').download(input.path)
  if (dlError || !blob) return { error: 'تعذّرت قراءة الملف المرفوع' }
  const buffer = Buffer.from(await blob.arrayBuffer())
  if (buffer.length > MAX_FILE_BYTES) return { error: 'حجم الملف يتجاوز 10 ميجابايت' }
  const hash = sha256Hash(buffer)
  if (hash !== input.clientHash) return { error: 'بصمة الملف المخزَّن لا تطابق الملف الأصلي. أعد الرفع.' }
  const rejected = await checkUpload(buffer, input.mimeType, input.fileName)
  if (rejected) { await discardObject(input.path); return { error: rejected } }

  const { error } = await createAdminClient().rpc('register_arb_document_srv', {
    p_actor: actor.id, p_aal: actor.aal, p_arb: input.arbId, p_path: input.path, p_file_name: input.fileName,
    p_mime: input.mimeType, p_size: buffer.length, p_hash: hash, p_type: input.docType,
  })
  if (error) return { error: error.message }
  revalidatePath(`/arbitrations/${input.arbId}`)
  return { message: `تم رفع المستند وتوثيقه. البصمة: ${hash.slice(0, 16)}…` }
}
const sha256Hash = (b: Buffer) => sha256Hex(b)

export async function verifyArbDocument(docId: string): Promise<ActionResult> {
  const supabase = await createClient()
  const { data: doc } = await supabase.from('arb_documents').select('file_path, sha256_hash').eq('id', docId).maybeSingle()
  if (!doc) return { error: 'المستند غير موجود' }
  const { data: blob, error } = await supabase.storage.from('documents').download(doc.file_path)
  if (error || !blob) return { error: 'تعذّرت قراءة الملف من التخزين' }
  return sha256Hash(Buffer.from(await blob.arrayBuffer())) === doc.sha256_hash
    ? { message: 'الملف سليم: البصمة مطابقة لما سُجّل عند الرفع.' }
    : { error: 'تحذير: محتوى الملف اختلف عن النسخة المسجّلة.' }
}

export async function getArbDocumentUrl(docId: string): Promise<{ url?: string; error?: string }> {
  const supabase = await createClient()
  const { data: doc } = await supabase.from('arb_documents').select('file_path, file_name').eq('id', docId).maybeSingle()
  if (!doc) return { error: 'المستند غير موجود' }
  const { data, error } = await supabase.storage.from('documents').createSignedUrl(doc.file_path, 60, { download: doc.file_name })
  if (error || !data) return { error: 'تعذّر إنشاء رابط التنزيل' }
  return { url: data.signedUrl }
}

export async function confirmArbAgreement(arbId: string, docId: string, _fd?: FormData): Promise<ActionResult> {
  const actor = await currentActor()
  if (!actor) return { error: 'غير مصرح' }
  const { error } = await createAdminClient().rpc('confirm_arb_agreement_srv', {
    p_actor: actor.id, p_aal: actor.aal, p_arb: arbId, p_doc: docId,
    p_ip: await clientIp(), p_ua: (await headers()).get('user-agent'),
  })
  if (error) return { error: error.message }
  await notifyArbitration(arbId, 'agreement_confirmed', { roles: ['claimant', 'respondent'], except: actor.id })
  revalidatePath(`/arbitrations/${arbId}`)
  return { message: 'تم تسجيل تأكيدك.' }
}


// ------------------------------------------------------------------ the arbitration agreement, drafted and signed on the platform
export async function saveArbAgreement(arbId: string, fd: FormData): Promise<ActionResult> {
  const { error } = await (await createClient()).rpc('save_arb_agreement', { p_arb: arbId, p_text: text(fd, 'body') })
  if (error) return { error: error.message }
  revalidatePath(`/arbitrations/${arbId}`)
  return { message: 'تم حفظ مسودة الاتفاق.' }
}

export async function openArbAgreement(arbId: string, _fd?: FormData): Promise<ActionResult> {
  const { error } = await (await createClient()).rpc('open_arb_agreement', { p_arb: arbId })
  if (error) return { error: error.message }
  await notifyArbitration(arbId, 'agreement_opened', { roles: ['claimant', 'respondent'], except: (await currentActor())?.id })
  revalidatePath(`/arbitrations/${arbId}`)
  return { message: 'فُتح الاتفاق للتوقيع. لم يعد النص قابلًا للتعديل ما لم تُعد فتحه قبل أي توقيع.' }
}

export async function reopenArbAgreement(arbId: string, _fd?: FormData): Promise<ActionResult> {
  const { error } = await (await createClient()).rpc('reopen_arb_agreement', { p_arb: arbId })
  if (error) return { error: error.message }
  revalidatePath(`/arbitrations/${arbId}`)
  return { message: 'أُعيد فتح النص للتعديل.' }
}

// Signing = the signer's password re-checked here + the exact text hash, time, assurance level and the IP/browser the SERVER saw.
// The database accepts the signature only from this server function, so the password step cannot be skipped from the browser.
export async function signArbAgreement(arbId: string, fd: FormData): Promise<ActionResult> {
  if (fd.get('agree') !== 'on') return { error: 'أكّد قراءتك لنص الاتفاق وموافقتك عليه' }
  const password = text(fd, 'password')
  if (!password) return { error: 'أدخل كلمة المرور لتأكيد التوقيع' }
  const expected = text(fd, 'expected_hash')
  if (!expected) return { error: 'حدّث الصفحة ثم أعد المحاولة' }
  if (!signingConfigured()) return { error: 'مفتاح توقيع المنصة غير مضبوط على الخادم، فلا يمكن توقيع الاتفاق عليها الآن. تواصل مع الإدارة أو استخدم مسار الملف الموقَّع.' }

  const actor = await currentActor()
  if (!actor?.email) return { error: 'غير مصرح' }
  if (await rateLimited('sign-password', 5, 600, actor.id, true)) return { error: 'محاولات كثيرة أو تعذّر التحقق من المعدل الآن. انتظر بضع دقائق ثم أعد المحاولة.' }
  if (!(await passwordIsValid(actor.email, password))) return { error: 'كلمة المرور غير صحيحة' }

  const { error } = await createAdminClient().rpc('sign_arb_agreement_srv', {
    p_actor: actor.id, p_aal: actor.aal, p_arb: arbId, p_expected_hash: expected, p_ip: await clientIp(), p_ua: (await headers()).get('user-agent'),
  })
  if (error) return { error: error.message }
  await signArbInstrument('agreement', arbId) // no-op until the second signature freezes the record
  await notifyArbitration(arbId, 'agreement_signed', { roles: ['claimant', 'respondent'], except: actor.id })
  revalidatePath(`/arbitrations/${arbId}`)
  return { message: 'تم تسجيل توقيعك.' }
}

// ------------------------------------------------------------------ the arbitrator
export async function proposeArbitrator(arbId: string, arbitratorId: string, _fd?: FormData): Promise<ActionResult> {
  const { error } = await (await createClient()).rpc('propose_arbitrator', { p_arb: arbId, p_arbitrator: arbitratorId })
  if (error) return { error: error.message }
  await notifyArbitration(arbId, 'arbitrator_proposed', { roles: ['claimant', 'respondent'], except: (await currentActor())?.id })
  revalidatePath(`/arbitrations/${arbId}`)
  return { message: 'تم اقتراح المحكّم. بانتظار موافقة الطرف الآخر.' }
}

export async function partyRespondArbitrator(arbId: string, assignmentId: string, approve: boolean, _fd?: FormData): Promise<ActionResult> {
  const { error } = await (await createClient()).rpc('party_respond_arbitrator', { p_assignment: assignmentId, p_approve: approve })
  if (error) return { error: error.message }
  if (approve) await notifyArbitration(arbId, 'arbitrator_approved', { roles: [], arbitratorOfAssignment: assignmentId })
  else await notifyArbitration(arbId, 'arbitrator_declined', { roles: ['claimant', 'respondent'], except: (await currentActor())?.id })
  revalidatePath(`/arbitrations/${arbId}`)
  return { message: approve ? 'تمت الموافقة. بانتظار قبول المحكّم.' : 'تم رفض الاقتراح.' }
}

export async function arbitratorRespond(arbId: string, assignmentId: string, accept: boolean, fd: FormData): Promise<ActionResult> {
  const { error } = await (await createClient()).rpc('arbitrator_respond', {
    p_assignment: assignmentId, p_accept: accept, p_disclosure: text(fd, 'disclosure') || null,
  })
  if (error) return { error: error.message }
  await notifyArbitration(arbId, accept ? 'arbitrator_seated' : 'arbitrator_declined', { roles: ['claimant', 'respondent'] })
  revalidatePath(`/arbitrations/${arbId}`)
  return { message: accept ? 'قبلت المهمة وسُجّل إقرارك. بدأت الإجراءات.' : 'تم الاعتذار عن المهمة.' }
}

export async function arbitratorWithdraw(arbId: string, fd: FormData): Promise<ActionResult> {
  const { error } = await (await createClient()).rpc('arbitrator_withdraw', { p_arb: arbId, p_reason: reasonOf(fd) })
  if (error) return { error: error.message }
  await notifyArbitration(arbId, 'arbitrator_withdrew', { roles: ['claimant', 'respondent'] })
  redirect('/dashboard')
}

// ------------------------------------------------------------------ procedure
export async function setStep(arbId: string, fd: FormData): Promise<ActionResult> {
  const due = new Date(text(fd, 'due_at'))
  if (Number.isNaN(due.getTime())) return { error: 'الموعد غير صالح' }
  const { error } = await (await createClient()).rpc('set_arb_step', {
    p_arb: arbId, p_kind: text(fd, 'kind'), p_party: text(fd, 'party'), p_due_at: due.toISOString(), p_note: text(fd, 'note') || null,
  })
  if (error) return { error: error.message }
  await notifyArbitration(arbId, 'step_set', { roles: ['claimant', 'respondent'] })
  revalidatePath(`/arbitrations/${arbId}`)
  return { message: 'تم تحديد الموعد.' }
}

export async function extendStep(arbId: string, stepId: string, fd: FormData): Promise<ActionResult> {
  const due = new Date(text(fd, 'due_at'))
  if (Number.isNaN(due.getTime())) return { error: 'الموعد غير صالح' }
  const { error } = await (await createClient()).rpc('extend_arb_step', { p_step: stepId, p_due_at: due.toISOString() })
  if (error) return { error: error.message }
  revalidatePath(`/arbitrations/${arbId}`)
  return { message: 'تم التمديد.' }
}

export async function submitStatement(arbId: string, stepId: string, fd: FormData): Promise<ActionResult> {
  const docs = fd.getAll('documents').map(String).filter(Boolean)
  const { error } = await (await createClient()).rpc('submit_arb_statement', { p_step: stepId, p_body: text(fd, 'body'), p_document_ids: docs })
  if (error) return { error: error.message }
  await notifyArbitration(arbId, 'statement_submitted', { except: (await currentActor())?.id })
  revalidatePath(`/arbitrations/${arbId}`)
  return { message: 'تم تقديم المذكرة وتسجيل وقتها.' }
}

export async function scheduleHearing(arbId: string, fd: FormData): Promise<ActionResult> {
  const at = new Date(text(fd, 'scheduled_at'))
  const minutes = Number(text(fd, 'minutes') || 120)
  if (Number.isNaN(at.getTime())) return { error: 'موعد الجلسة غير صالح' }
  const { data: id, error } = await (await createClient()).rpc('schedule_arb_hearing', { p_arb: arbId, p_at: at.toISOString(), p_minutes: minutes })
  if (error) return { error: error.message }

  let note = ''
  if (dailyEnabled() && process.env.SUPABASE_SERVICE_ROLE_KEY) {
    try {
      const ttl = Math.max(3600, Math.floor((at.getTime() - Date.now()) / 1000) + minutes * 60 + 7200)
      const room = await createRoom(`hayah-arb-${id}`, ttl)
      const { error: linkError } = await createAdminClient().from('arb_hearings')
        .update({ daily_room_name: room.name, daily_room_url: room.url }).eq('id', id as string)
      if (linkError) throw linkError
    } catch {
      note = ' (تعذّر إنشاء غرفة الفيديو، ستعمل الجلسة في وضع العرض.)'
    }
  }
  await notifyArbitration(arbId, 'hearing_scheduled', { roles: ['claimant', 'respondent'] })
  revalidatePath(`/arbitrations/${arbId}`)
  return { message: 'تمت جدولة الجلسة.' + note }
}

export async function closeProceedings(arbId: string, _fd?: FormData): Promise<ActionResult> {
  const { error } = await (await createClient()).rpc('close_proceedings', { p_arb: arbId })
  if (error) return { error: error.message }
  await notifyArbitration(arbId, 'proceedings_closed', { roles: ['claimant', 'respondent'] })
  revalidatePath(`/arbitrations/${arbId}`)
  return { message: 'أُقفلت الإجراءات. يمكنك الآن صياغة مسودة الحكم.' }
}

// ------------------------------------------------------------------ the award
export async function saveAwardDraft(arbId: string, fd: FormData): Promise<ActionResult> {
  const { error } = await (await createClient()).rpc('save_award_draft', { p_arb: arbId, p_text: text(fd, 'draft') })
  if (error) return { error: error.message }
  revalidatePath(`/arbitrations/${arbId}`)
  return { message: 'تم حفظ المسودة. لا يراها غيرك.' }
}

export async function issueAward(arbId: string, fd: FormData): Promise<ActionResult> {
  const { error } = await (await createClient()).rpc('issue_award', {
    p_arb: arbId, p_signed_doc: text(fd, 'signed_doc'), p_award_date: text(fd, 'award_date'),
  })
  if (error) return { error: error.message }
  await notifyArbitration(arbId, 'award_issued', { roles: ['claimant', 'respondent'] })
  revalidatePath(`/arbitrations/${arbId}`)
  return { message: 'سُجّل صدور الحكم وأُغلق الملف.' }
}

// The arbitrator signs the award on the platform: password re-check + second factor (aal2) + the exact text hash. The database
// freezes the canonical record, then the platform key signs it. NOT an ITIDA-licensed signature: the paper route above stays available.
export async function signAward(arbId: string, fd: FormData): Promise<ActionResult> {
  if (fd.get('agree') !== 'on') return { error: 'أكّد أن النص المعروض هو حكمك وأنك توقّعه' }
  const password = text(fd, 'password')
  if (!password) return { error: 'أدخل كلمة المرور لتأكيد التوقيع' }
  const expected = text(fd, 'expected_hash')
  if (!expected) return { error: 'حدّث الصفحة ثم أعد المحاولة' }
  if (!signingConfigured()) return { error: 'مفتاح توقيع المنصة غير مضبوط على الخادم، فلا يمكن توقيع الحكم عليها الآن.' }

  const actor = await currentActor()
  if (!actor?.email) return { error: 'غير مصرح' }
  if (await rateLimited('sign-password', 5, 600, actor.id, true)) return { error: 'محاولات كثيرة أو تعذّر التحقق من المعدل الآن. انتظر بضع دقائق ثم أعد المحاولة.' }
  if (!(await passwordIsValid(actor.email, password))) return { error: 'كلمة المرور غير صحيحة' }

  const { error } = await createAdminClient().rpc('sign_award_srv', {
    p_actor: actor.id, p_aal: actor.aal, p_arb: arbId, p_expected_hash: expected, p_award_date: text(fd, 'award_date'),
    p_ip: await clientIp(), p_ua: (await headers()).get('user-agent'),
  })
  if (error) return { error: error.message }
  const attested = await signArbInstrument('award', arbId)
  await notifyArbitration(arbId, 'award_issued', { roles: ['claimant', 'respondent'] })
  revalidatePath(`/arbitrations/${arbId}`)
  return { message: attested ? 'وُقّع الحكم ورُسِّخ وأُغلق الملف.' : 'وُقّع الحكم وأُغلق الملف، لكن تعذّر ختم المنصة عليه. أعد المحاولة من زر «ختم المنصة».' }
}

// Re-attach the platform signature to a signed agreement/award that lacks it (the key was missing or the call failed).
export async function retryArbAttestation(arbId: string, kind: 'agreement' | 'award', _fd?: FormData): Promise<ActionResult> {
  const actor = await currentActor()
  if (!actor) return { error: 'غير مصرح' }
  // RLS decides whether this person may see the instrument at all.
  const { data } = await (await createClient()).from(kind === 'agreement' ? 'arb_agreements' : 'arb_awards').select('id').eq('arbitration_id', arbId).maybeSingle()
  if (!data) return { error: 'غير موجود' }
  if (!signingConfigured()) return { error: 'مفتاح توقيع المنصة غير مضبوط على الخادم' }
  const ok = await signArbInstrument(kind, arbId)
  revalidatePath(`/arbitrations/${arbId}`)
  return ok ? { message: 'ثُبّت ختم المنصة.' } : { error: 'تعذّر ختم المنصة. حاول لاحقًا.' }
}

export async function terminateArbitration(arbId: string, fd: FormData): Promise<ActionResult> {
  const { error } = await (await createClient()).rpc('terminate_arbitration', { p_arb: arbId, p_reason: reasonOf(fd) })
  if (error) return { error: error.message }
  await notifyArbitration(arbId, 'arbitration_ended', { except: (await currentActor())?.id })
  revalidatePath(`/arbitrations/${arbId}`)
  return { message: 'أُنهيت الإجراءات وسُجّلت النتيجة.' }
}
