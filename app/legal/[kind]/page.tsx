import Link from 'next/link'
import { notFound } from 'next/navigation'
import PageFrame from '@/components/PageFrame'
import PrintButton from '@/components/PrintButton'
import { getLegalPublic } from '@/lib/legal'

export const dynamic = 'force-dynamic'

export default async function LegalDocPage(props: { params: Promise<{ kind: string }> }) {
  const { kind } = await props.params
  const doc = (await getLegalPublic()).find((d) => d.kind === kind)
  if (!doc) notFound()
  return (
    <PageFrame homeHref="/legal" homeLabel="كل الوثائق">
      <article className="mx-auto max-w-3xl space-y-4 py-2">
        <div className="flex flex-wrap items-start justify-between gap-2">
          <div>
            <h1 className="text-2xl">{doc.title}</h1>
            <p className="hint">النسخة {doc.version.toLocaleString('ar-EG')} — نُشرت {new Date(doc.published_at).toLocaleDateString('ar-EG')}</p>
          </div>
          <PrintButton />
        </div>
        <div className="whitespace-pre-wrap rounded-md border border-navy-100 bg-white p-5 leading-9">{doc.body}</div>
        <p className="hint" dir="ltr">SHA-256: {doc.body_hash}</p>
        <p className="hint"><Link href="/legal" className="auth-text-link">العودة إلى كل الوثائق</Link></p>
      </article>
    </PageFrame>
  )
}
