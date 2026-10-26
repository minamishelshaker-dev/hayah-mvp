'use client'

import { useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { registerArbDocument } from '@/app/(app)/arbitrations/actions'
import { ALLOWED_MIME, FILE_ACCEPT } from '@/lib/constants'

const MAX_BYTES = 10 * 1024 * 1024

async function sha256Browser(file: File): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', await file.arrayBuffer())
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, '0')).join('')
}

// Same flow as case documents: browser -> private storage, then the SERVER re-hashes and writes the evidence row.
export default function UploadArbDocument({ arbId, docType, label }: { arbId: string; docType: string; label: string }) {
  const [busy, setBusy] = useState(false)
  const [msg, setMsg] = useState<{ error?: string; ok?: string } | null>(null)

  async function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    const form = e.currentTarget
    const file = new FormData(form).get('file') as File | null
    if (!file || file.size === 0) return setMsg({ error: 'اختر ملفًا أولًا' })
    if (file.size > MAX_BYTES) return setMsg({ error: 'حجم الملف يتجاوز 10 ميجابايت' })
    if (!ALLOWED_MIME.includes(file.type)) return setMsg({ error: 'نوع الملف غير مسموح. المسموح: PDF والصور وWord وExcel والنص.' })
    setBusy(true)
    setMsg(null)
    try {
      const clientHash = await sha256Browser(file)
      const path = `${arbId}/${crypto.randomUUID()}`
      const { error: upErr } = await createClient().storage.from('documents').upload(path, file, { contentType: file.type, upsert: false })
      if (upErr) throw new Error('فشل رفع الملف: ' + upErr.message)
      const res = await registerArbDocument({ arbId, path, fileName: file.name, mimeType: file.type, size: file.size, docType, clientHash })
      if (res.error) throw new Error(res.error)
      setMsg({ ok: res.message })
      form.reset()
    } catch (err) {
      setMsg({ error: err instanceof Error ? err.message : 'حدث خطأ غير متوقع' })
    } finally {
      setBusy(false)
    }
  }

  return (
    <form onSubmit={onSubmit} className="mt-3 flex flex-col gap-3 border-t border-navy-100 pt-3 sm:flex-row sm:items-end">
      <div className="flex-1">
        <label className="label" htmlFor={`file-${docType}`}>{label} (حتى 10 م.ب)</label>
        <input id={`file-${docType}`} name="file" type="file" required accept={FILE_ACCEPT} className="input" />
      </div>
      <button type="submit" disabled={busy} className="btn btn-primary">{busy ? 'جارٍ الرفع والتوثيق…' : 'رفع وتوثيق'}</button>
      {msg?.error && <p role="alert" className="text-sm font-semibold text-red-700 sm:basis-full">{msg.error}</p>}
      {msg?.ok && <p role="status" className="text-sm font-semibold text-emerald-700 sm:basis-full">{msg.ok}</p>}
    </form>
  )
}
