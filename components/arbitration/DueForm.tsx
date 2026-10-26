'use client'

import FormAction from '@/components/FormAction'
import type { ActionResult } from '@/lib/types'
import { PARTY_LABEL, STEP_KIND_LABEL } from '@/lib/labels'

// A deadline picked in the user's own timezone is sent as an exact UTC instant.
export default function DueForm({ action, submitLabel, full = false }: {
  action: (fd: FormData) => Promise<ActionResult | void>
  submitLabel: string
  full?: boolean
}) {
  return (
    <FormAction action={action} submitLabel={submitLabel} variant="ghost" className="flex flex-wrap items-end gap-2"
      transform={(fd) => { const v = String(fd.get('local') ?? ''); if (v) fd.set('due_at', new Date(v).toISOString()) }}>
      {full && (
        <>
          <div>
            <label className="label" htmlFor="kind">الخطوة</label>
            <select id="kind" name="kind" className="input" defaultValue="statement_of_claim">
              {Object.entries(STEP_KIND_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
            </select>
          </div>
          <div>
            <label className="label" htmlFor="party">على</label>
            <select id="party" name="party" className="input" defaultValue="claimant">
              {Object.entries(PARTY_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
            </select>
          </div>
        </>
      )}
      <div>
        <label className="label" htmlFor="local">الموعد النهائي</label>
        <input id="local" name="local" type="datetime-local" required className="input" />
      </div>
      {full && (
        <div className="min-w-0 flex-1">
          <label className="label" htmlFor="note">ملاحظة (اختياري)</label>
          <input id="note" name="note" maxLength={500} className="input" />
        </div>
      )}
    </FormAction>
  )
}
