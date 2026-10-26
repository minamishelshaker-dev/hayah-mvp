// File types accepted for case documents. MUST match public.allowed_mime_types() in supabase/trust.sql
// (the database and the storage bucket enforce the same list; this copy only gives users early feedback).
export const ALLOWED_MIME = [
  'application/pdf', 'image/png', 'image/jpeg', 'image/webp', 'text/plain',
  'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.ms-excel', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
]
export const FILE_ACCEPT = '.pdf,.png,.jpg,.jpeg,.webp,.txt,.doc,.docx,.xls,.xlsx'
