import { createClient } from '@/lib/supabase/server'

export type LegalScope = 'registration' | 'public' | 'dispute' | 'arbitration'
export type LegalDoc = {
  kind: string; scope: LegalScope; position: number; short_title: string
  title: string; version: number; published_at: string; body_hash: string; body: string
}

export const SCOPE_LABEL: Record<LegalScope, string> = {
  registration: 'وثائق استخدام المنصة (تُقبل عند التسجيل)',
  public: 'السياسات المنشورة',
  dispute: 'اتفاقيات الوساطة (تُقبل داخل كل ملف)',
  arbitration: 'قواعد التحكيم (تُقبل داخل كل ملف)',
}
export const SCOPE_ORDER: LegalScope[] = ['registration', 'public', 'dispute', 'arbitration']

// Current published texts, readable without signing in.
export async function getLegalPublic(): Promise<LegalDoc[]> {
  const { data } = await (await createClient()).rpc('legal_public')
  return (data ?? []) as LegalDoc[]
}
