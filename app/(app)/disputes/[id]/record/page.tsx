import Link from 'next/link'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { requireProfile } from '@/lib/auth'
import FormAction from '@/components/FormAction'
import { issueRecord } from '../../actions'
import { formatDate } from '@/lib/labels'

export default async function RecordsPage(props: { params: Promise<{ id: string }> }) {
  const params = await props.params
  const profile = await requireProfile()
  const supabase = await createClient()
  const { data: d } = await supabase.from('disputes').select('id, dispute_number, title').eq('id', params.id).maybeSingle()
  if (!d) redirect(`/disputes/${params.id}`)


  const { data: exports } = await supabase
    .from('record_exports').select('id, record_hash, created_at').eq('dispute_id', d.id).order('created_at', { ascending: false })

  return (
    <div className="mx-auto max-w-2xl space-y-5">
      <div>
        <Link href={`/disputes/${d.id}`} className="hint underline">← العودة إلى الملف</Link>
        <h1 className="mt-2 text-2xl">المحضر الموثّق</h1>
        <p className="hint"><span dir="ltr">{d.dispute_number}</span> — {d.title}</p>
      </div>

      <section className="panel space-y-3">
        <p>
          يلتقط المحضر لقطة ثابتة من ملف النزاع وقت الإصدار: الأطراف، وقبول الاتفاقيات، والمستندات وبصماتها، والجلسات، ونص الاتفاق والتوقيعات، والسجل الزمني، ونتيجة فحص سلامة السجل.
          تُبنى اللقطة داخل قاعدة البيانات، وتُحفظ ولا تُعدَّل، ويمكن لأي جهة التحقق من صدورها عن المنصة من صفحة التحقق.
        </p>
        <FormAction action={issueRecord.bind(null, d.id)} submitLabel="إصدار محضر جديد" variant="gold" />
      </section>

      <section className="panel">
        <h2 className="mb-2 text-lg">المحاضر التي أصدرتها</h2>
        {(exports ?? []).length === 0 && <p className="hint">لم تُصدر أي محضر بعد.</p>}
        <ul className="divide-y divide-navy-100">
          {(exports ?? []).map((e) => (
            <li key={e.id} className="flex flex-wrap items-center justify-between gap-2 py-2">
              <span>
                {formatDate(e.created_at)} <span dir="ltr" className="font-mono text-xs text-navy-500">{e.record_hash.slice(0, 16)}</span>
              </span>
              <Link href={`/disputes/${d.id}/record/${e.id}`} className="btn btn-ghost !py-1">فتح</Link>
            </li>
          ))}
        </ul>
      </section>
    </div>
  )
}
