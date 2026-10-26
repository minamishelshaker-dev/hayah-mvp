// Decision logic for the OPTIONAL external malware scanner, kept free of framework imports so scripts/selftest-scan.mjs can test it.
// MALWARE_SCAN_URL      where the raw file is POSTed; the answer must be {"clean": true|false}
// MALWARE_SCAN_REQUIRED "true" = fail CLOSED: a missing, unreachable, slow or malformed scanner rejects the upload.
//                       anything else = fail OPEN: only an explicit {"clean": false} rejects; outages let the file through unscanned.
// Returns an Arabic error message, or null when the file may proceed.
export interface ScanEnv { MALWARE_SCAN_URL?: string; MALWARE_SCAN_TOKEN?: string; MALWARE_SCAN_REQUIRED?: string }
export type FetchLike = (
  url: string,
  init: { method: string; headers: Record<string, string>; body: Uint8Array; signal?: AbortSignal }
) => Promise<{ ok: boolean; status: number; json(): Promise<unknown> }>

export async function scanVerdict(bytes: Uint8Array, fileName: string, env: ScanEnv, doFetch: FetchLike): Promise<string | null> {
  const required = env.MALWARE_SCAN_REQUIRED === 'true'
  const url = env.MALWARE_SCAN_URL
  if (!url) return required ? 'فحص الملفات إلزامي لكن خدمة الفحص غير مضبوطة على الخادم، فلا يمكن قبول الرفع الآن.' : null
  try {
    const res = await doFetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/octet-stream',
        Authorization: `Bearer ${env.MALWARE_SCAN_TOKEN ?? ''}`,
        'X-File-Name': encodeURIComponent(fileName.slice(0, 200)),
      },
      body: bytes,
      signal: AbortSignal.timeout(20_000),
    })
    if (!res.ok) throw new Error(`scanner status ${res.status}`)
    const verdict = (await res.json()) as { clean?: unknown }
    return verdict && verdict.clean === true ? null : 'رُفض الملف: لم يجتز فحص البرمجيات الخبيثة.'
  } catch {
    return required ? 'تعذّر فحص الملف الآن. حاول لاحقًا.' : null
  }
}
