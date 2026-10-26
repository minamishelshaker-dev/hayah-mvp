import { createClient } from '@/lib/supabase/server'
import FormAction from '@/components/FormAction'
import { publishLegal } from '../actions'
import { formatDate } from '@/lib/labels'

const KINDS = [
  { kind: 'terms', label: 'شروط استخدام المنصة', note: 'تُطلب موافقة كل المستخدمين عليها من جديد فور نشر نسخة جديدة.' },
  { kind: 'privacy', label: 'سياسة الخصوصية', note: 'تُطلب موافقة كل المستخدمين عليها من جديد فور نشر نسخة جديدة.' },
  { kind: 'arbitration_rules', label: 'قواعد استخدام المنصة في التحكيم', note: 'تُثبَّت نسخة القواعد لكل ملف تحكيم عند فتحه، فلا يغيّرها نشر نسخة جديدة في ملف قائم.' },
  { kind: 'mediation_agreement', label: 'اتفاقية الوساطة', note: 'تُطبَّق النسخة الجديدة على النزاعات الجديدة؛ من قبِل نسخة سابقة في نزاع قائم لا يُطلب منه القبول من جديد.' },
]

type Doc = { id: string; kind: string; version: number; title: string; body: string; is_current: boolean; is_placeholder: boolean; created_at: string }

export default async function AdminLegalPage() {
  const { data } = await (await createClient()).from('legal_documents').select('*').order('version', { ascending: false })
  const docs = (data ?? []) as Doc[]

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl">النصوص القانونية</h1>
        <p className="hint">النصوص الحالية مؤقتة حتى تنشر نصوصك المعتمدة. كل نسخة محفوظة بختم SHA-256 ولا تُعدَّل، والنشر ينشئ نسخة جديدة.</p>
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
