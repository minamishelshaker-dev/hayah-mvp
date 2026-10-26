'use client'

import { useFormStatus } from 'react-dom'

export default function SubmitButton({ label, className = 'btn btn-primary w-full' }: { label: string; className?: string }) {
  const { pending } = useFormStatus()
  return (
    <button type="submit" disabled={pending} className={className}>
      {pending ? 'جارٍ التنفيذ…' : label}
    </button>
  )
}
