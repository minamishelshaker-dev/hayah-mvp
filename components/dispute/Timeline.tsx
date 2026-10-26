import { describeEvent, formatDate } from '@/lib/labels'
import type { TimelineEntry } from '@/lib/types'

export default function Timeline({ logs }: { logs: TimelineEntry[] }) {
  return (
    <section className="panel">
      <h2 className="text-lg">السجل الزمني الموثّق</h2>
      <p className="hint mb-3">يُكتب تلقائيًا في قاعدة البيانات عند كل إجراء، ولا يمكن تعديله أو حذفه. الرمز الظاهر هو ختم السطر ضمن سلسلة البصمات. لا يعرض لك هذا السجل عناوين الاتصال أو متصفحات الأطراف الآخرين.</p>
      <ol className="space-y-3 border-s-2 border-gold ps-4">
        {logs.map((l) => (
          <li key={l.seq}>
            <p className="font-semibold">{describeEvent(l)}</p>
            <p className="hint">
              {l.actor_name} — {formatDate(l.created_at)}{' '}
              <span dir="ltr" className="font-mono text-xs">#{l.seq} {l.row_hash?.slice(0, 8)}</span>
            </p>
          </li>
        ))}
      </ol>
    </section>
  )
}
