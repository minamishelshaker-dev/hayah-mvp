'use client'

import { useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { registerDocument } from '@/app/(app)/disputes/actions'
import { ALLOWED_MIME, FILE_ACCEPT } from '@/lib/constants'

const MAX_BYTES = 10 * 1024 * 1024

async function sha256Browser(file: File): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', await file.arrayBuffer())
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, '0')).join('')
}

// The file goes straight from the browser to Supabase Storage (no serverless body-size limit).
// The server then re-reads it, recomputes SHA-256 and compares it with the browser's hash.
export default function UploadDocument({ disputeId }: { disputeId: string }) {
  const [busy, setBusy] = useState(false)
  const [msg, setMsg] = useState<{ error?: string; ok?: string } | null>(null)

  async function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    const form = e.currentTarget
    const fd = new FormData(form)
    const file = fd.get('file') as File | null
    if (!file || file.size === 0) return setMsg({ error: 'اختر ملفًا أولًا' })
    if (file.size > MAX_BYTES) return setMsg({ error: 'حجم الملف يتجاوز 10 ميجابايت' })
    if (!ALLOWED_MIME.includes(file.type)) return setMsg({ error: 'نوع الملف غير مسموح. المسموح: PDF والصور وWord وExcel والنص.' })

    setBusy(true)
    setMsg(null)
    try {
      const clientHash = await sha256Browser(file)
      const path = `${disputeId}/${crypto.randomUUID()}`
      const supabase = createClient()
      const { error: upErr } = await supabase.storage
        .from('documents')
        .upload(path, file, { contentType: file.type || 'application/octet-stream', upsert: false })
      if (upErr) throw new Error('فشل رفع الملف: ' + upErr.message)

      const res = await registerDocument({
        disputeId,
        path,
        fileName: file.name,
        mimeType: file.type || 'application/octet-stream',
        size: file.size,
        docType: String(fd.get('doc_type') ?? 'other'),
        clientHash,
      })
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
    <form onSubmit={onSubmit} className="mt-4 flex flex-col gap-3 border-t border-navy-100 pt-4 sm:flex-row sm:items-end">
      <div className="flex-1">
        <label className="label" htmlFor="file">ملف جديد (حتى 10 م.ب)</label>
        <input id="file" name="file" type="file" required accept={FILE_ACCEPT} className="input" />
      </div>
      <div>
        <label className="label" htmlFor="doc_type">النوع</label>
        <select id="doc_type" name="doc_type" className="input" defaultValue="evidence">
          <option value="contract">عقد</option>
          <option value="evidence">دليل</option>
          <option value="correspondence">مراسلات</option>
          <option value="other">أخرى</option>
        </select>
      </div>
      <button type="submit" disabled={busy} className="btn btn-primary">{busy ? 'جارٍ الرفع والتوثيق…' : 'رفع وتوثيق'}</button>
      {msg?.error && <p role="alert" className="text-sm font-semibold text-red-700 sm:basis-full">{msg.error}</p>}
      {msg?.ok && <p role="status" className="text-sm font-semibold text-emerald-700 sm:basis-full">{msg.ok}</p>}
    </form>
  )
}
