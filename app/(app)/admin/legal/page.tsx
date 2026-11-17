import { createClient } from '@/lib/supabase/server'
import FormAction from '@/components/FormAction'
import { publishLegal } from '../actions'
import { formatDate } from '@/lib/labels'

const NOTE: Record<string, string> = {
  registration: 'وثيقة تُقبل عند التسجيل: تُطلب موافقة كل المستخدمين عليها من جديد فور نشر نسخة جديدة.',
  public: 'سياسة منشورة للجميع: لا تُطلب موافقة، وتظهر النسخة الجديدة فور نشرها في صفحة الوثائق القانونية.',
  dispute: 'تُطبَّق النسخة الجديدة على النزاعات الجديدة؛ من قبِل نسخة سابقة في نزاع قائم لا يُطلب منه القبول من جديد.',
  arbitration: 'تُثبَّت نسخة القواعد لكل ملف تحكيم عند فتحه، فلا يغيّرها نشر نسخة جديدة في ملف قائم.',
}

type Doc = { id: string; kind: string; version: number; title: string; body: string; is_current: boolean; is_placeholder: boolean; created_at: string }

export default async function AdminLegalPage() {
  const { data } = await (await createClient()).from('legal_documents').select('*').order('version', { ascending: false })
  const docs = (data ?? []) as Doc[]
  const { data: kindRows } = await (await createClient()).from('legal_kinds').select('kind, scope, position, short_title').order('position')
  const KINDS = (kindRows ?? []).map((k) => ({ kind: k.kind as string, label: k.short_title as string, note: NOTE[k.scope as string] ?? '' }))

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl">النصوص القانونية</h1>
        <p className="hint">كل نسخة محفوظة بختم SHA-256 ولا تُعدَّل، والنشر ينشئ نسخة جديدة.</p>
      </div>
      {KINDS.map(({ kind, label, note }) => {
        const versions = docs.filter((d) => d.kind === kind)
        const current = versions.find((d) => d.is_current)
        return (
          <section key={kind} className="panel space-y-3">
            <h2 className="text-lg">{label}</h2>
            <p className="hint">{note}</p>
            {current?.is_placeholder && (
              <p role="alert" className="rounded bg-red-50 p-2 text-sm font-semibold text-red-800">النسخة السارية نص مؤقت. انشر النص المعتمد قبل أول حالة حقيقية.</p>
            )}
            {current && (
              <p className="text-sm">
                السارية: النسخة {current.version.toLocaleString('ar-EG')} — {current.title} — نُشرت {formatDate(current.created_at)}
                {versions.length > 1 ? ` — عدد النسخ السابقة: ${(versions.length - 1).toLocaleString('ar-EG')}` : ''}
              </p>
            )}
            <FormAction action={publishLegal.bind(null, kind)} submitLabel="نشر نسخة جديدة" variant="gold" className="space-y-3 border-t border-navy-100 pt-3" confirmText="ستصبح هذه النسخة هي السارية. هل أنت متأكد؟">
              <div>
                <label className="label" htmlFor={`t-${kind}`}>العنوان</label>
                <input id={`t-${kind}`} name="title" required minLength={3} defaultValue={label} className="input" />
              </div>
              <div>
                <label className="label" htmlFor={`b-${kind}`}>النص الكامل</label>
                <textarea id={`b-${kind}`} name="body" required minLength={20} rows={10} className="input leading-8" />
              </div>
            </FormAction>
          </section>
        )
      })}
    </div>
  )
}
