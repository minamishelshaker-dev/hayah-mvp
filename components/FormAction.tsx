'use client'

import { useState, useTransition, type ReactNode } from 'react'
import type { ActionResult } from '@/lib/types'

// One form wrapper for every server action: shows pending state and the server's error/success text.
export default function FormAction({
  action,
  submitLabel,
  variant = 'primary',
  children,
  className,
  confirmText,
  transform,
  resetOnSuccess = true,
}: {
  action: (fd: FormData) => Promise<ActionResult | void>
  submitLabel: string
  variant?: 'primary' | 'gold' | 'ghost' | 'danger'
  children?: ReactNode
  className?: string
  confirmText?: string
  transform?: (fd: FormData) => void
  resetOnSuccess?: boolean
}) {
  const [pending, start] = useTransition()
  const [result, setResult] = useState<ActionResult | null>(null)

  return (
    <form
      className={className}
      onSubmit={(e) => {
        e.preventDefault()
        if (confirmText && !window.confirm(confirmText)) return
        const form = e.currentTarget
        const fd = new FormData(form)
        transform?.(fd)
        start(async () => {
          const r = (await action(fd)) ?? {}
          setResult(r)
          if (!r.error && resetOnSuccess) form.reset()
        })
      }}
    >
      {children}
      <button type="submit" disabled={pending} className={`btn btn-${variant}`}>
        {pending ? 'جارٍ التنفيذ…' : submitLabel}
      </button>
      {result?.error && <p role="alert" className="mt-2 text-sm font-semibold text-red-700">{result.error}</p>}
      {result?.message && <p role="status" className="mt-2 text-sm font-semibold text-emerald-700">{result.message}</p>}
    </form>
  )
}
