'use server'

import { createClient } from '@/lib/supabase/server'
import { formatDate } from '@/lib/labels'
import { rateLimited } from '@/lib/ratelimit'
import { keyIdOf, publicKeyPem, verifyRecordSignature } from '@/lib/signing'
import type { ActionResult } from '@/lib/types'

export async function verifyRecord(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  if (await rateLimited('verify', 20, 600)) return { error: 'طلبات كثيرة. حاول بعد قليل.' }
  const hash = String(fd.get('hash') ?? '').trim()
  const file = fd.get('file') as File | null
  let record: unknown = null
  let signature: { value?: string; key_id?: string } | null = null

  if (file && file.size > 0) {
    if (file.size > 1_500_000) return { error: 'حجم الملف كبير جدًا' }
    try {
      const parsed = JSON.parse(await file.text())
      // Either the record itself, or a bundle { record, signature }.
      if (parsed && typeof parsed === 'object' && 'record' in parsed && 'signature' in parsed) {
        record = parsed.record
        signature = parsed.signature
      } else {
        record = parsed
      }
    } catch {
      return { error: 'الملف ليس بصيغة JSON صالحة' }
    }
  }
  if (!hash && !record) return { error: 'أدخل بصمة المحضر أو ارفع ملف JSON الخاص به' }

  const { data, error } = await (await createClient()).rpc('verify_record', { p_hash: hash || null, p_record: record })
  if (error) return { error: 'تعذّر التحقق الآن. حاول لاحقًا.' }
  const r = data as { found: boolean; issued_at?: string; dispute_number?: string; signed?: boolean; signing_key_id?: string }
  if (!r.found) return { error: 'لم يُعثر على محضر مطابق. إما أنه لم يصدر عن المنصة، أو جرى تعديل محتواه بعد صدوره.' }

  let sigNote = r.signed ? ` المحضر موقَّع رقميًا لدى المنصة (مفتاح ${r.signing_key_id}).` : ' المحضر غير موقَّع رقميًا.'
  if (signature?.value && record) {
    const pub = publicKeyPem()
    if (!pub) sigNote += ' تعذّر فحص التوقيع المرفق هنا لأن مفتاح التوقيع غير مضبوط على الخادم؛ استخدم scripts/verify-record.mjs بالمفتاح العام.'
    else if (signature.key_id && signature.key_id !== keyIdOf(pub)) sigNote += ' التوقيع المرفق بمفتاح مختلف عن المفتاح الحالي؛ افحصه بالمفتاح العام القديم عبر scripts/verify-record.mjs.'
    else sigNote += verifyRecordSignature(pub, record, signature.value) ? ' التوقيع الرقمي المرفق صحيح.' : ' تحذير: التوقيع الرقمي المرفق لا يطابق المحضر.'
  }
  return {
    message: `المحضر صادر عن المنصة بتاريخ ${formatDate(r.issued_at!)} للنزاع ${r.dispute_number}.${sigNote} هذا يثبت صدوره وسلامة محتواه كما صدر، ولا يثبت صحة وقائع النزاع نفسها.`,
  }
}
