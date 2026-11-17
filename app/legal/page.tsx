import Link from 'next/link'
import PageFrame from '@/components/PageFrame'
import { getLegalPublic, SCOPE_LABEL, SCOPE_ORDER } from '@/lib/legal'

export const metadata = { title: 'الوثائق القانونية' }
export const dynamic = 'force-dynamic'

export default async function LegalIndexPage() {
  const docs = await getLegalPublic()
  return (
    <PageFrame>
      <div className="mx-auto max-w-3xl space-y-6 py-2">
        <div>
          <h1 className="text-2xl">الوثائق القانونية</h1>
          <p className="hint mt-1">هذه هي النصوص السارية. التسجيل في المنصة لا يعني الموافقة على وساطة أو تحكيم: لكل إجراء اتفاق مستقل تُطلب موافقتك عليه عند فتح الملف المعني فقط.</p>
        </div>
        {SCOPE_ORDER.map((scope) => {
          const list = docs.filter((d) => d.scope === scope)
          if (!list.length) return null
          return (
            <section key={scope} className="panel space-y-2">
              <h2 className="text-lg">{SCOPE_LABEL[scope]}</h2>
              <ul className="divide-y divide-navy-100">
                {list.map((d) => (
                  <li key={d.kind} className="flex flex-wrap items-center justify-between gap-2 py-2">
                    <Link href={`/legal/${d.kind}`} className="auth-text-link font-semibold">{d.title}</Link>
                    <span className="hint">النسخة {d.version.toLocaleString('ar-EG')} — {new Date(d.published_at).toLocaleDateString('ar-EG')}</span>
                  </li>
                ))}
              </ul>
            </section>
          )
        })}
      </div>
    </PageFrame>
  )
}
