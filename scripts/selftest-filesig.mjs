// Unit test for lib/filesig.ts.   npm run test:filesig   (needs Node 22+: it imports the .ts file directly)
import { bytesMatchMime } from '../lib/filesig.ts'

let failed = 0
const check = (cond, msg) => { if (!cond) { failed++; console.error('FAIL:', msg) } }
const B = (...parts) => Buffer.concat(parts.map((p) => (typeof p === 'string' ? Buffer.from(p, 'latin1') : Buffer.from(p))))

const PDF = B('%PDF-1.7\n1 0 obj\n')
const PNG = B([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a], 'rest')
const JPG = B([0xff, 0xd8, 0xff, 0xe0], 'rest')
const WEBP = B('RIFF', [1, 2, 3, 4], 'WEBPVP8 ')
const DOCX = B([0x50, 0x4b, 0x03, 0x04], '....[Content_Types].xml....word/document.xml')
const XLSX = B([0x50, 0x4b, 0x03, 0x04], '....[Content_Types].xml....xl/workbook.xml')
const OLE = B([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1], 'doc')
const TXT = Buffer.from('نص عربي عادي\nسطر ثانٍ', 'utf8')
const EXE = B([0x4d, 0x5a], 'This program cannot be run in DOS mode')
const ZIP_PLAIN = B([0x50, 0x4b, 0x03, 0x04], 'payload.txt')

const M = {
  pdf: 'application/pdf', png: 'image/png', jpg: 'image/jpeg', webp: 'image/webp', txt: 'text/plain',
  doc: 'application/msword', xls: 'application/vnd.ms-excel',
  docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
}

check(bytesMatchMime(PDF, M.pdf), 'real PDF accepted')
check(bytesMatchMime(PNG, M.png), 'real PNG accepted')
check(bytesMatchMime(JPG, M.jpg), 'real JPEG accepted')
check(bytesMatchMime(WEBP, M.webp), 'real WebP accepted')
check(bytesMatchMime(DOCX, M.docx), 'OOXML word accepted')
check(bytesMatchMime(XLSX, M.xlsx), 'OOXML excel accepted')
check(bytesMatchMime(OLE, M.doc) && bytesMatchMime(OLE, M.xls), 'legacy office accepted')
check(bytesMatchMime(TXT, M.txt), 'Arabic text accepted')

check(!bytesMatchMime(EXE, M.pdf), 'exe declared as PDF rejected')
check(!bytesMatchMime(EXE, M.png), 'exe declared as PNG rejected')
check(!bytesMatchMime(EXE, M.txt), 'exe declared as text rejected')
check(!bytesMatchMime(EXE, M.docx), 'exe declared as docx rejected')
check(!bytesMatchMime(ZIP_PLAIN, M.docx), 'plain zip declared as docx rejected')
check(!bytesMatchMime(DOCX, M.xlsx), 'word file declared as excel rejected')
check(!bytesMatchMime(PDF, M.txt), 'PDF declared as text rejected')
check(!bytesMatchMime(B([0, 1, 2, 3, 4, 5]), M.txt), 'binary declared as text rejected')
check(!bytesMatchMime(Buffer.alloc(0), M.txt), 'empty text rejected')
check(!bytesMatchMime(PDF, 'application/x-msdownload'), 'unknown type rejected')

if (failed) { console.error(`${failed} check(s) failed`); process.exit(1) }
console.log('filesig self-test: all checks passed')
