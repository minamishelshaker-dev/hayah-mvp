'use client'

import { useEffect, useRef, useState } from 'react'

type Participant = { name: string; role: string }

export default function DailyRoom({ sessionId, participants, tokenUrl }: { sessionId: string; participants: Participant[]; tokenUrl?: string }) {
  const container = useRef<HTMLDivElement>(null)
  const [state, setState] = useState<'loading' | 'demo' | 'live' | 'error'>('loading')
  const [error, setError] = useState('')

  useEffect(() => {
    let cancelled = false
    let frame: { join: (o: object) => unknown; destroy: () => unknown } | null = null

    ;(async () => {
      try {
        const res = await fetch(tokenUrl ?? `/api/sessions/${sessionId}/token`)
        const json = await res.json()
        if (!res.ok) throw new Error(json.error ?? 'تعذّر الانضمام إلى الجلسة')
        if (cancelled) return
        if (json.demo) return setState('demo')
        const { default: DailyIframe } = await import('@daily-co/daily-js')
        if (cancelled || !container.current) return
        frame = DailyIframe.createFrame(container.current, {
          iframeStyle: { width: '100%', height: '100%', border: '0' },
          showLeaveButton: true,
        })
        await frame.join({ url: json.url, token: json.token })
        setState('live')
      } catch (e) {
        if (!cancelled) {
          setError(e instanceof Error ? e.message : 'خطأ غير متوقع')
          setState('error')
        }
      }
    })()

    return () => {
      cancelled = true
      frame?.destroy()
    }
  }, [sessionId, tokenUrl])

  return (
    <div>
      <div ref={container} className={state === 'live' ? 'h-[70vh] overflow-hidden rounded-lg bg-navy' : 'hidden'} />
      {state === 'loading' && <p className="hint">جارٍ تجهيز غرفة الجلسة…</p>}
      {state === 'error' && <p role="alert" className="font-semibold text-red-700">{error}</p>}
      {state === 'demo' && (
        <div className="rounded-lg bg-navy p-6 text-white">
          <p className="mb-4 text-sm text-gold-100">
            وضع العرض: لم يُضبط مفتاح Daily.co في هذه البيئة، فلا يوجد اتصال مرئي حقيقي. أضف DAILY_API_KEY لتفعيل الفيديو.
          </p>
          <div className="grid gap-3 sm:grid-cols-3">
            {participants.map((p) => (
              <div key={p.name + p.role} className="flex aspect-video flex-col items-center justify-center rounded-md bg-navy-700">
                <span className="mb-2 flex h-12 w-12 items-center justify-center rounded-full bg-gold text-lg font-bold">{p.name.slice(0, 1)}</span>
                <span className="text-sm font-semibold">{p.name}</span>
                <span className="text-xs text-navy-100">{p.role}</span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
