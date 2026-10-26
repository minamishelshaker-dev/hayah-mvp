'use client'

import { useState } from 'react'

export default function CopyLink({ link }: { link: string }) {
  const [copied, setCopied] = useState(false)
  return (
    <div className="flex flex-col gap-2 sm:flex-row">
      <input readOnly value={link} dir="ltr" className="input text-xs" onFocus={(e) => e.currentTarget.select()} />
      <button
        type="button"
        className="btn btn-gold shrink-0"
        onClick={async () => {
          await navigator.clipboard.writeText(link)
          setCopied(true)
          setTimeout(() => setCopied(false), 2000)
        }}
      >
        {copied ? 'تم النسخ' : 'نسخ الرابط'}
      </button>
    </div>
  )
}
