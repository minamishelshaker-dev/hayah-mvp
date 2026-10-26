import type { AuditLog } from '@/lib/types'

export const STATUS_LABEL: Record<string, string> = {
  invited: 'بانتظار قبول الطرف الثاني',
  accepted: 'قبل الطرف الثاني الوساطة',
  mediator_selection: 'اختيار الوسيط',
  active: 'الوساطة جارية',
  settlement_draft: 'صياغة اتفاق التسوية',
  signed: 'تم توقيع التسوية',
  closed: 'مغلق',
  cancelled: 'ملغي',
}

export const STATUS_TONE: Record<string, string> = {
  invited: 'bg-gold-100 text-gold-700',
  accepted: 'bg-navy-100 text-navy',
  mediator_selection: 'bg-gold-100 text-gold-700',
  active: 'bg-navy text-white',
  settlement_draft: 'bg-navy-500 text-white',
  signed: 'bg-emerald-100 text-emerald-800',
  closed: 'bg-navy-100 text-navy-500',
  cancelled: 'bg-red-100 text-red-800',
}

export const OUTCOME_LABEL: Record<string, string> = {
  settled: 'تسوية موقّعة',
  no_settlement: 'انتهت الوساطة دون تسوية',
  withdrawn: 'سحبه مقدّم النزاع',
  declined: 'رفضه الطرف الثاني',
}

export const ARB_STATUS_LABEL: Record<string, string> = {
  proposed: 'بانتظار موافقة الطرف الآخر على التحكيم',
  agreement: 'اتفاق التحكيم',
  selection: 'اختيار المحكّم',
  active: 'الإجراءات جارية',
  deliberation: 'المداولة وصياغة الحكم',
  closed: 'مغلق',
  cancelled: 'ملغى',
}
export const ARB_STATUS_TONE: Record<string, string> = {
  proposed: 'bg-gold-100 text-gold-700',
  agreement: 'bg-gold-100 text-gold-700',
  selection: 'bg-gold-100 text-gold-700',
  active: 'bg-navy text-white',
  deliberation: 'bg-navy-500 text-white',
  closed: 'bg-emerald-100 text-emerald-800',
  cancelled: 'bg-red-100 text-red-800',
}
export const ARB_OUTCOME_LABEL: Record<string, string> = {
  award_issued: 'صدر حكم التحكيم',
  terminated: 'أنهى المحكّم الإجراءات',
  withdrawn: 'سحبه الطرف الطالب',
  declined: 'رفضه الطرف الآخر',
}
export const STEP_KIND_LABEL: Record<string, string> = {
  statement_of_claim: 'مذكرة الدعوى',
  statement_of_defence: 'مذكرة الدفاع',
  reply: 'مذكرة رد',
  rejoinder: 'مذكرة تعقيب',
  other: 'مذكرة أخرى',
}
export const PARTY_LABEL: Record<string, string> = { claimant: 'مقدّم الطلب', respondent: 'الطرف الآخر' }
export const ARB_DOC_LABEL: Record<string, string> = {
  arbitration_agreement: 'اتفاق التحكيم الموقَّع',
  exhibit: 'مرفق',
  procedural: 'مستند إجرائي',
  award_signed: 'الحكم الموقَّع',
  other: 'أخرى',
}

export const TYPE_LABEL: Record<string, string> = {
  commercial: 'تجاري',
  civil: 'مدني',
  labor: 'عمالي',
  other: 'أخرى',
}

export const ROLE_LABEL: Record<string, string> = {
  party: 'طرف',
  lawyer: 'محامٍ',
  mediator: 'وسيط',
  arbitrator: 'محكّم',
  admin: 'مدير',
}

export const KYC_LABEL: Record<string, string> = {
  pending: 'بانتظار التحقق',
  verified: 'تم التحقق',
  rejected: 'مرفوض',
}

export const DOC_TYPE_LABEL: Record<string, string> = {
  contract: 'عقد',
  evidence: 'دليل',
  correspondence: 'مراسلات',
  other: 'أخرى',
}

export const formatDate = (iso: string) =>
  new Date(iso).toLocaleString('ar-EG', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'Africa/Cairo' })

export const formatEgp = (n: number) =>
  `${Number(n).toLocaleString('ar-EG')} جنيه`

export const formatSize = (bytes: number) =>
  bytes < 1024 * 1024 ? `${Math.max(1, Math.round(bytes / 1024))} ك.ب` : `${(bytes / 1024 / 1024).toFixed(1)} م.ب`

// Turns a raw audit row into a sentence a lawyer can read.
export function describeEvent(log: Pick<AuditLog, 'event_type' | 'new_state' | 'previous_state'>): string {
  const n = log.new_state ?? {}
  const o = log.previous_state ?? {}
  switch (log.event_type) {
    case 'disputes.INSERT':
      return `تسجيل النزاع ${n.dispute_number ?? ''}`
    case 'disputes.UPDATE':
      return n.status !== o.status
        ? `تغيّرت حالة النزاع إلى «${STATUS_LABEL[n.status] ?? n.status}»${n.outcome ? ` — ${OUTCOME_LABEL[n.outcome] ?? n.outcome}` : ''}`
        : 'تحديث بيانات النزاع'
    case 'invitations.INSERT':
      return `إرسال دعوة إلى ${n.invited_email ?? 'الطرف الثاني'}`
    case 'invitations.UPDATE':
      return ({ accepted: 'قبول الدعوة', declined: 'رفض الدعوة', cancelled: 'إلغاء الدعوة', expired: 'انتهاء أو تجديد الدعوة' } as Record<string, string>)[n.status] ?? 'تحديث الدعوة'
    case 'mediator_assignments.INSERT':
      return 'اقتراح وسيط'
    case 'mediator_assignments.UPDATE':
      return ({ approved: 'موافقة الطرف الآخر على الوسيط', accepted: 'قبول الوسيط للمهمة', rejected: 'رفض اقتراح الوسيط', ended: 'انسحاب الوسيط' } as Record<string, string>)[n.status] ?? 'تحديث اقتراح الوسيط'
    case 'documents.INSERT':
      return `رفع مستند «${n.file_name ?? ''}» (SHA-256: ${String(n.sha256_hash ?? '').slice(0, 12)}…)`
    case 'sessions.INSERT':
      return `جدولة الجلسة رقم ${n.session_number}`
    case 'sessions.UPDATE':
      return 'تحديث بيانات الجلسة'
    case 'settlements.INSERT':
      return 'إنشاء مسودة اتفاق التسوية'
    case 'settlements.UPDATE':
      return n.status !== o.status
        ? n.status === 'pending_signatures' ? 'فتح الاتفاق للتوقيع' : n.status === 'signed' ? 'اكتمال توقيع الاتفاق' : n.status === 'draft' ? 'إعادة فتح الاتفاق للتعديل' : 'تحديث الاتفاق'
        : `تعديل مسودة الاتفاق (النسخة ${n.version})`
    case 'settlement_signatures.INSERT':
      return `توقيع إلكتروني من ${n.party_role === 'claimant' ? 'مقدّم النزاع' : 'الطرف الثاني'}`
    case 'arbitrations.INSERT':
      return `فتح ملف التحكيم ${n.arb_number ?? ''}`
    case 'arbitrations.UPDATE':
      return n.status !== o.status
        ? `تغيّرت حالة التحكيم إلى «${ARB_STATUS_LABEL[n.status] ?? n.status}»${n.outcome ? ` — ${ARB_OUTCOME_LABEL[n.outcome] ?? n.outcome}` : ''}`
        : 'تحديث بيانات التحكيم'
    case 'arb_assignments.INSERT':
      return 'اقتراح محكّم'
    case 'arb_assignments.UPDATE':
      return ({ approved: 'موافقة الطرف الآخر على المحكّم', accepted: 'قبول المحكّم المهمة وتقديم إقرار الاستقلال', rejected: 'رفض اقتراح المحكّم', ended: 'انسحاب المحكّم' } as Record<string, string>)[n.status] ?? 'تحديث اقتراح المحكّم'
    case 'arb_documents.INSERT':
      return `رفع «${n.file_name ?? ''}» (${ARB_DOC_LABEL[n.doc_type] ?? ''})`
    case 'arb_agreement_confirmations.INSERT':
      return 'تأكيد اتفاق التحكيم الموقَّع'
    case 'arb_steps.INSERT':
      return `تحديد موعد: ${STEP_KIND_LABEL[n.kind] ?? ''} (${PARTY_LABEL[n.party] ?? ''})`
    case 'arb_steps.UPDATE':
      return 'تمديد موعد'
    case 'arb_submissions.INSERT':
      return `تقديم مذكرة${n.late ? ' بعد الموعد' : ''}`
    case 'arb_hearings.INSERT':
      return `جدولة جلسة التحكيم رقم ${n.number ?? ''}`
    case 'arb_hearings.UPDATE':
      return 'تحديث جلسة التحكيم'
    case 'arb_awards.INSERT':
      return 'بدء صياغة مسودة الحكم'
    case 'arb_awards.UPDATE':
      if (n.status === 'issued' && o.status !== 'issued') return n.signing_mode === 'platform' ? 'توقيع الحكم رقميًا على المنصة وإصداره' : 'إصدار الحكم وتسجيل المسح الموقَّع'
      return n.status === 'issued' ? 'تحديث بيانات الحكم الصادر (توقيع المنصة)' : `تعديل مسودة الحكم (النسخة ${n.version})`
    case 'arb_agreements.INSERT':
      return 'بدء صياغة اتفاق التحكيم على المنصة'
    case 'arb_agreements.UPDATE':
      return n.status !== o.status
        ? n.status === 'open' ? 'فتح اتفاق التحكيم للتوقيع' : n.status === 'signed' ? 'اكتمال توقيع اتفاق التحكيم' : n.status === 'draft' ? 'إعادة فتح اتفاق التحكيم للتعديل' : 'تحديث اتفاق التحكيم'
        : `تحديث اتفاق التحكيم (النسخة ${n.version})`
    case 'arb_agreement_signatures.INSERT':
      return 'توقيع إلكتروني على اتفاق التحكيم'
    case 'arb_awards.DELETE':
      return 'حذف مسودة حكم (انسحاب المحكّم)'
    case 'record_exports.SIGNED':
      return 'توقيع المحضر رقميًا'
    case 'consents.INSERT':
      return 'قبول وثيقة قانونية'
    case 'record_exports.INSERT':
      return 'إصدار محضر موثّق'
    case 'profiles.INSERT':
      return 'إنشاء حساب'
    case 'profiles.UPDATE':
      return `تحديث حساب (الدور: ${ROLE_LABEL[n.role] ?? n.role}، التحقق: ${KYC_LABEL[n.kyc_status] ?? n.kyc_status})`
    case 'app_settings.INSERT':
    case 'app_settings.UPDATE':
      return `تغيير إعداد أمني: ${n.key} = ${n.value}`
    case 'admin.mfa_reset':
      return 'إعادة تعيين المصادقة الثنائية لحساب'
    case 'admin.view_dispute':
    case 'admin.view_arbitration':
      return 'اطّلع مدير المنصة على الملف'
    default:
      if (log.event_type.startsWith('admin.')) return `إجراء إداري: ${log.event_type.slice(6)}`
      return log.event_type
  }
}
