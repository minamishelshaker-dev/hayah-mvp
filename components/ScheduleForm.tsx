'use client'

import FormAction from '@/components/FormAction'
import type { ActionResult } from '@/lib/types'

export default function ScheduleForm({ action }: { action: (fd: FormData) => Promise<ActionResult | void> }) {
  return (
    <FormAction
      action={action}
      submitLabel="جدولة الجلسة"
      className="flex flex-col gap-3 sm:flex-row sm:items-end"
      // The browser knows the user's timezone; the server stores an exact UTC instant.
      transform={(fd) => {
        const local = String(fd.get('local') ?? '')
        if (local) fd.set('scheduled_at', new Date(local).toISOString())
      }}
    >
      <div className="flex-1">
        <label className="label" htmlFor="local">موعد الجلسة</label>
        <input id="local" name="local" type="datetime-local" required className="input" />
      </div>
      <div>
        <label className="label" htmlFor="minutes">المدة (دقيقة)</label>
        <select id="minutes" name="minutes" className="input" defaultValue="60">
          <option value="30">30</option>
          <option value="60">60</option>
          <option value="90">90</option>
          <option value="120">120</option>
        </select>
      </div>
    </FormAction>
  )
}
