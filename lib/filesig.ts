// Server-side check that the BYTES of an uploaded file match the type the browser declared.
// The browser's Content-Type is just a claim; the storage bucket and the database both trust it. This closes that gap
// for the allowed list (PDF, PNG, JPEG, WebP, OOXML, legacy Office, plain text). It is a signature check, not a malware scan:
// a well-formed PDF can still carry a malicious payload (see lib/upload-guard.ts for the optional external scanner).
// Keep this file free of TypeScript-only runtime syntax (no enums) so scripts/selftest-filesig.mjs can import it directly.

const MIME_DOCX = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
const MIME_XLSX = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'

const startsWith = (b: Uint8Array, sig: number[]) => b.length >= sig.length && sig.every((v, i) => b[i] === v)
const asBuffer = (b: Uint8Array) => Buffer.from(b.buffer, b.byteOffset, b.byteLength)

const EXECUTABLE_OR_CONTAINER_HEADS: number[][] = [
  [0x4d, 0x5a],                    // MZ  (Windows executable)
  [0x7f, 0x45, 0x4c, 0x46],        // ELF
  [0x25, 0x50, 0x44, 0x46, 0x2d],  // %PDF-
  [0x50, 0x4b, 0x03, 0x04],        // PK  (zip / OOXML / jar)
  [0xd0, 0xcf, 0x11, 0xe0],        // OLE2 (legacy Office)
]

function looksLikeText(b: Uint8Array): boolean {
  if (b.length === 0) return false
  if (EXECUTABLE_OR_CONTAINER_HEADS.some((sig) => startsWith(b, sig))) return false
  const n = Math.min(b.length, 8192)
  for (let i = 0; i < n; i++) {
    const c = b[i]
    if (c < 9 || (c > 13 && c < 32)) return false // NUL and other control bytes: not text
  }
  return true
}

function isOoxml(b: Uint8Array, folder: string): boolean {
  if (!startsWith(b, [0x50, 0x4b, 0x03, 0x04])) return false
  const buf = asBuffer(b)
  // zip entry names are stored uncompressed in the local headers, so a plain search is enough for a sanity check
  return buf.includes('[Content_Types].xml', 0, 'latin1') && buf.includes(folder, 0, 'latin1')
}

export function bytesMatchMime(bytes: Uint8Array, mime: string): boolean {
  switch (mime) {
    case 'application/pdf':
      return asBuffer(bytes.subarray(0, 1024)).includes('%PDF-', 0, 'latin1')
    case 'image/png':
      return startsWith(bytes, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
    case 'image/jpeg':
      return startsWith(bytes, [0xff, 0xd8, 0xff])
    case 'image/webp':
      return bytes.length >= 12 && startsWith(bytes, [0x52, 0x49, 0x46, 0x46]) && asBuffer(bytes).toString('latin1', 8, 12) === 'WEBP'
    case MIME_DOCX:
      return isOoxml(bytes, 'word/')
    case MIME_XLSX:
      return isOoxml(bytes, 'xl/')
    case 'application/msword':
    case 'application/vnd.ms-excel':
      return startsWith(bytes, [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1])
    case 'text/plain':
      return looksLikeText(bytes)
    default:
      return false
  }
}
