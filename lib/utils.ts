// Only allow redirects to paths inside this app.
export const safeNext = (next: unknown, fallback = '/dashboard') => {
  const n = typeof next === 'string' ? next : ''
  return n.startsWith('/') && !n.startsWith('//') ? n : fallback
}

export function formatDuration(secs: number | null | undefined): string {
  if (secs == null) return '—'
  if (secs < 90) return 'أقل من دقيقتين'
  if (secs < 5400) return `${Math.round(secs / 60).toLocaleString('ar-EG')} دقيقة`
  if (secs < 172800) return `${(secs / 3600).toFixed(1)} ساعة`
  return `${(secs / 86400).toFixed(1)} يوم`
}
