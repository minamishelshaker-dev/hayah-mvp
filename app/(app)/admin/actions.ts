'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'
import { notifyUserEmail } from '@/lib/notify'
import type { ActionResult } from '@/lib/types'

export async function updateUser(userId: string, fd: FormData): Promise<ActionResult> {
  const role = String(fd.get('role'))
  const kyc = String(fd.get('kyc_status'))
  if (!['party', 'lawyer', 'mediator', 'arbitrator', 'admin'].includes(role) || !['pending', 'verified', 'rejected'].includes(kyc)) {
    return { error: 'قيمة غير صالحة' }
  }
  // RLS + the protect_profile trigger make this succeed for admins only.
  const { data, error } = await (await createClient())
    .from('profiles').update({ role, kyc_status: kyc }).eq('id', userId).select('id')
  if (error) return { error: error.message }
  if (!data?.length) return { error: 'غير مصرح' }
  revalidatePath('/admin/users')
  return { message: 'تم الحفظ' }
}

export async function verifyAuditChain(_fd?: FormData): Promise<ActionResult> {
  const { data, error } = await (await createClient()).rpc('verify_audit_chain')
  if (error) return { error: error.message }
  const r = data as { ok: boolean; total: number; bad_seq?: number }
  return r.ok
    ? { message: `السلسلة سليمة: تم فحص ${r.total.toLocaleString('ar-EG')} سجلًا ولم يُكتشف أي تعديل.` }
    : { error: `تحذير: اختلّت السلسلة عند السجل رقم ${r.bad_seq}.` }
}

export async function publishLegal(kind: string, fd: FormData): Promise<ActionResult> {
  if (!['terms', 'privacy', 'mediation_agreement', 'arbitration_rules'].includes(kind)) return { error: 'نوع غير صالح' }
  const { data, error } = await (await createClient()).rpc('publish_legal_document', {
    p_kind: kind,
    p_title: String(fd.get('title') ?? ''),
    p_body: String(fd.get('body') ?? ''),
    p_placeholder: false,
  })
  if (error) return { error: error.message }
  revalidatePath('/admin/legal')
  return { message: `تم نشر النسخة ${data} وأصبحت هي السارية.` }
}

export async function checkAuditAnchor(fd: FormData): Promise<ActionResult> {
  const seq = Number(fd.get('seq'))
  const hash = String(fd.get('hash') ?? '').trim()
  if (!Number.isInteger(seq) || seq < 1 || !/^[0-9a-fA-F]{64}$/.test(hash)) return { error: 'أدخل رقم الحدث وبصمة من 64 خانة' }
  const { data, error } = await (await createClient()).rpc('check_audit_anchor', { p_seq: seq, p_hash: hash })
  if (error) return { error: error.message }
  const r = data as { ok: boolean; reason: string }
  if (r.ok) return { message: 'النقطة مطابقة: السجل عند هذا الحدث كما كان وقت أخذ النقطة.' }
  return {
    error: r.reason === 'missing' ? 'لا يوجد حدث بهذا الرقم.'
      : r.reason === 'row_altered' ? 'تحذير: محتوى هذا السجل تغيّر بعد إنشائه.'
      : 'تحذير: بصمة السجل الحالية تختلف عن النقطة المحفوظة خارج قاعدة البيانات. قد يكون السجل أُعيدت كتابته.',
  }
}

export async function resetMfa(userId: string, _fd?: FormData): Promise<ActionResult> {
  const supabase = await createClient()
  const { data: isAdmin } = await supabase.rpc('is_admin')
  if (!isAdmin) return { error: 'غير مصرح' }
  // Written to the audit log BEFORE the factor is removed, so the action can never go unrecorded.
  const { error: logError } = await supabase.rpc('record_admin_event', { p_event: 'mfa_reset', p_target: userId })
  if (logError) return { error: 'تعذّر تسجيل الإجراء، فلم يُنفَّذ: ' + logError.message }
  const admin = createAdminClient()
  const { data, error } = await admin.auth.admin.mfa.listFactors({ userId })
  if (error) return { error: 'تعذّرت قراءة عوامل التحقق (سُجّلت المحاولة).' }
  for (const f of data?.factors ?? []) {
    const { error: delError } = await admin.auth.admin.mfa.deleteFactor({ id: f.id, userId })
    if (delError) return { error: 'تعذّر حذف أحد العوامل (سُجّلت المحاولة).' }
  }
  // The owner is told, so a reset he did not ask for is noticed.
  await notifyUserEmail(userId, 'أُعيد تعيين التحقق بخطوتين لحسابك في حياة', '<p>أعاد مدير المنصة تعيين التحقق بخطوتين لحسابك، وسيُطلب منك تسجيله من جديد عند دخولك التالي.</p><p><b>إن لم تكن تتوقع ذلك فتواصل مع الإدارة فورًا</b> وغيّر كلمة مرورك.</p>')
  revalidatePath('/admin/users')
  return { message: 'أُعيد تعيين المصادقة الثنائية. سيُطلب من الحساب تسجيلها من جديد عند دخوله التالي.' }
}
