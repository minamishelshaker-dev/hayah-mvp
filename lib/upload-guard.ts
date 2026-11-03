import { createAdminClient } from '@/lib/supabase/admin'
import { bytesMatchMime } from '@/lib/filesig'
import { scanVerdict, type FetchLike } from '@/lib/scan'

// Everything the server checks about an uploaded file BEFORE it becomes evidence.
// 1) the bytes must match the declared type (lib/filesig.ts);
// 2) optionally an external scanner (e.g. a ClamAV wrapper or a vendor API behind one URL) must say the file is clean.
//    See lib/scan.ts for the exact fail-open / fail-closed rules (MALWARE_SCAN_REQUIRED).
//    PRIVACY: the scanner receives the raw case documents. Use a self-hosted scanner or a processor you have a data-processing
//    agreement with; do not point this at a public consumer scanning site.
// Returns an Arabic error message, or null when the file may proceed.
export async function checkUpload(buf: Buffer, mime: string, fileName: string): Promise<string | null> {
  if (!bytesMatchMime(buf, mime)) return 'محتوى الملف لا يطابق نوعه المعلن. ارفع ملفًا سليمًا من الأنواع المسموحة.'
  return scanVerdict(new Uint8Array(buf), fileName, {
    MALWARE_SCAN_URL: process.env.MALWARE_SCAN_URL,
    MALWARE_SCAN_TOKEN: process.env.MALWARE_SCAN_TOKEN,
    MALWARE_SCAN_REQUIRED: process.env.MALWARE_SCAN_REQUIRED,
  }, fetch as unknown as FetchLike)
}

// A rejected upload is already in storage; remove it so unvetted bytes do not linger. Best effort.
export async function discardObject(path: string): Promise<void> {
  try {
    if (!process.env.SUPABASE_SERVICE_ROLE_KEY) return
    await createAdminClient().storage.from('documents').remove([path])
  } catch {
    /* ignore */
  }
}
