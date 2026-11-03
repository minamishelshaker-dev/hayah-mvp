import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import FormAction from '@/components/FormAction'
import { acceptPlatformTerms } from './actions'
import { safeNext } from '@/lib/utils'

type Doc = { id: string; kind: string; version: number; title: string; body: string; is_placeholder: boolean }

export default async function ConsentPage(props: { searchParams: Promise<{ next?: string }> }) {
  const searchParams = await props.searchParams
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')
  const next = safeNext(searchParams.next)

  const { data: accepted } = await supabase.rpc('has_platform_consent')
  if (accepted) redirect(next)

  const { data } = await supabase
    .from('legal_documents').select('id, kind, version, title, body, is_placeholder')
    .eq('is_current', true).in('kind', ['terms', 'privacy']).order('kind', { ascending: false })
  const docs = (data ?? []) as Doc[]

  return (
    <main className="mx-auto max-w-2xl px-4 py-10">
      <h1 className="mb-1 text-2xl">قبل المتابعة</h1>
      <p className="hint mb-5">اقرأ الوثيقتين التاليتين ثم أكّد موافقتك. يُسجَّل قبولك بنسخة الوثيقة ووقتها.</p>
      <div className="space-y-4">
        {docs.map((d) => (
          <section key={d.id} className="panel">
            <h2 className="text-lg">{d.title} <span className="hint">— النسخة {d.version.toLocaleString('ar-EG')}</span></h2>
            {d.is_placeholder && (
              <p role="alert" className="my-2 rounded bg-red-50 p-2 text-sm font-semibold text-red-800">
                هذا نص مؤقت للتجربة التقنية فقط، ولا يجوز استخدام المنصة في حالة حقيقية قبل استبداله بالنص المعتمد.
              </p>
            )}
            <div className="mt-2 max-h-72 overflow-auto whitespace-pre-wrap rounded-md border border-navy-100 bg-navy-50 p-3 leading-8">{d.body}</div>
          </section>
        ))}
        <FormAction action={acceptPlatformTerms.bind(null, next)} submitLabel="أوافق وأتابع" variant="gold" className="panel space-y-3">
          <label className="flex items-start gap-2 text-sm">
            <input type="checkbox" name="agree" className="mt-1.5" />
            <span>قرأت شروط استخدام المنصة وسياسة الخصوصية وأوافق عليهما.</span>
          </label>
        </FormAction>
      </div>
    </main>
  )
}
