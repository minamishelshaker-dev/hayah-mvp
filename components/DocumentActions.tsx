'use client'

import { useState, useTransition } from 'react'
import { getDocumentUrl, verifyDocument } from '@/app/(app)/disputes/actions'

export default function DocumentActions({ docId }: { docId: string }) {
  const [pending, start] = useTransition()
  const [result, setResult] = useState<{ error?: string; message?: string } | null>(null)

  return (
    <div className="flex flex-col items-start gap-1">
      <div className="flex gap-2">
        <button
          type="button"
          disabled={pending}
          className="btn btn-ghost !px-3 !py-1 text-xs"
          onClick={() => start(async () => setResult(await verifyDocument(docId)))}
        >
          {pending ? 'جارٍ الفحص…' : 'تحقق من السلامة'}
        </button>
        <button
          type="button"
          disabled={pending}
          className="btn btn-ghost !px-3 !py-1 text-xs"
          onClick={() =>
            start(async () => {
              const r = await getDocumentUrl(docId)
              if (r.url) window.open(r.url, '_blank', 'noopener')
              else setResult({ error: r.error })
            })
          }
        >
          تنزيل
        </button>
      </div>
      {result?.error && <span role="alert" className="text-xs font-semibold text-red-700">{result.error}</span>}
      {result?.message && <span role="status" className="text-xs font-semibold text-emerald-700">{result.message}</span>}
    </div>
  )
}
