import Link from 'next/link'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import FormAction from '@/components/FormAction'
import { acceptPlatformTerms } from './actions'
import { safeNext } from '@/lib/utils'
import PageFrame from '@/components/PageFrame'

type Doc = { id: string; kind: string; version: number; title: string; body: string; is_placeholder: boolean }

export default async function ConsentPage(props: { searchParams: Promise<{ next?: string }> }) {
  const searchParams = await props.searchParams
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')
  const next = safeNext(searchParams.next)

  const { data: accepted } = await supabase.rpc('has_platform_consent')
  if (accepted) redirect(next)

  const { data: kinds } = await supabase.from('legal_kinds').select('kind, position').eq('scope', 'registration').order('position')
  const order = (kinds ?? []).map((k) => k.kind as string)
  const { data } = await supabase
    .from('legal_documents').select('id, kind, version, title, body, is_placeholder')
    .eq('is_current', true).in('kind', order)
  const docs = ((data ?? []) as Doc[]).sort((a, b) => order.indexOf(a.kind) - order.indexOf(b.kind))

  return (
    <PageFrame homeHref="/dashboard" homeLabel="العودة إلى المنصة">
      <div className="mx-auto max-w-3xl py-2">
        <h1 className="mb-1 text-2xl">قبل المتابعة</h1>
        <p className="hint mb-3">اقرأ كل وثيقة ثم أكّد موافقتك عليها وحدها. يُسجَّل قبولك بنسخة الوثيقة ووقتها.</p>
        <p className="mb-5 rounded-md border border-gold bg-gold-100/30 p-3 text-sm leading-7">
          هذه الوثائق تخص استخدام المنصة فقط. <b>موافقتك عليها لا تعني الموافقة على وساطة أو تحكيم</b>: لكل إجراء اتفاق مستقل تُطلب موافقتك عليه عند فتح الملف المعني، وليس هنا.
          يمكنك الاطلاع على كل الوثائق في أي وقت من <Link href="/legal" className="auth-text-link">صفحة الوثائق القانونية</Link>.
        </p>
        <FormAction action={acceptPlatformTerms.bind(null, next)} submitLabel="أوافق وأتابع" variant="gold" className="space-y-4">
          {docs.map((d) => (
            <section key={d.id} className="panel space-y-2">
              <h2 className="text-lg">{d.title} <span className="hint">— النسخة {d.version.toLocaleString('ar-EG')}</span></h2>
              {d.is_placeholder && (
                <p role="alert" className="rounded bg-red-50 p-2 text-sm font-semibold text-red-800">
                  هذا نص مؤقت للتجربة التقنية فقط، ولا يجوز استخدام المنصة في حالة حقيقية قبل استبداله بالنص المعتمد.
                </p>
              )}
              <div className="max-h-60 overflow-auto whitespace-pre-wrap rounded-md border border-navy-100 bg-navy-50 p-3 leading-8">{d.body}</div>
              <label className="flex items-start gap-2 text-sm">
                <input type="checkbox" name={`agree_${d.kind}`} required className="mt-1.5" />
                <span>قرأتُ «{d.title}» وأوافق عليها.</span>
              </label>
            </section>
          ))}
        </FormAction>
      </div>
    </PageFrame>
  )
}
