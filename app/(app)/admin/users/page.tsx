import { createClient } from '@/lib/supabase/server'
import FormAction from '@/components/FormAction'
import { updateUser, resetMfa } from '../actions'
import { createAdminClient } from '@/lib/supabase/admin'
import { ROLE_LABEL, KYC_LABEL } from '@/lib/labels'
import type { Profile } from '@/lib/types'

export default async function AdminUsersPage() {
  const supabase = await createClient()
  const { data } = await supabase.from('profiles').select('*').order('created_at', { ascending: false })
  const users = (data ?? []) as Profile[]

  // Which admins/mediators have a verified authenticator? (needs the service role; skipped if it is not configured)
  const hasMfa: Record<string, boolean> = {}
  if (process.env.SUPABASE_SERVICE_ROLE_KEY) {
    const admin = createAdminClient()
    for (const u of users.filter((x) => x.role === 'admin' || x.role === 'mediator')) {
      try {
        const { data: f } = await admin.auth.admin.mfa.listFactors({ userId: u.id })
        hasMfa[u.id] = !!f?.factors?.some((x) => x.status === 'verified')
      } catch { /* leave undefined */ }
    }
  }

  return (
    <div className="space-y-4">
      <h1 className="text-2xl">المستخدمون</h1>
      <p className="hint">الجميع يبدأ بدور «طرف». رقِّ الحساب إلى وسيط أو محامٍ بعد مراجعة بياناته، وحدّث حالة التحقق من الهوية. لا يظهر الوسيط في الدليل ولا يمكن اقتراحه إلا بعد أن يكون دوره «وسيط» وحالة التحقق «تم التحقق» معًا.</p>
      <ul className="space-y-3">
        {users.map((u) => (
          <li key={u.id} className="panel flex flex-col justify-between gap-3 lg:flex-row lg:items-center">
            <div>
              <p className="font-bold">{u.full_name}</p>
              <p className="hint" dir="ltr">{u.email}{u.phone ? ` — ${u.phone}` : ''}</p>
              {(u.role === 'admin' || u.role === 'mediator') && hasMfa[u.id] !== undefined && (
                <p className={`text-sm font-semibold ${hasMfa[u.id] ? 'text-emerald-700' : 'text-red-700'}`}>
                  {hasMfa[u.id] ? '✓ التحقق بخطوتين مفعّل' : '✗ لم يسجّل التحقق بخطوتين بعد'}
                </p>
              )}
              <p className="hint">
                طلب التسجيل بصفة: {u.requested_role ? ROLE_LABEL[u.requested_role] : '—'}
                {u.bar_number ? ` — رقم القيد: ${u.bar_number}` : ''}
              </p>
            </div>
            <FormAction action={updateUser.bind(null, u.id)} submitLabel="حفظ" variant="ghost" resetOnSuccess={false} className="flex flex-wrap items-end gap-2">
              <div>
                <label className="label" htmlFor={`role-${u.id}`}>الدور</label>
                <select id={`role-${u.id}`} name="role" defaultValue={u.role} className="input">
                  {Object.entries(ROLE_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                </select>
              </div>
              <div>
                <label className="label" htmlFor={`kyc-${u.id}`}>التحقق</label>
                <select id={`kyc-${u.id}`} name="kyc_status" defaultValue={u.kyc_status} className="input">
                  {Object.entries(KYC_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                </select>
              </div>
            </FormAction>
            {hasMfa[u.id] && (
              <FormAction action={resetMfa.bind(null, u.id)} submitLabel="إعادة تعيين المصادقة" variant="danger"
                confirmText="سيُحذف عامل التحقق لهذا الحساب ويُسجَّل الإجراء. استخدمه فقط بعد التأكد من هوية صاحب الحساب. هل أنت متأكد؟" />
            )}
          </li>
        ))}
      </ul>
    </div>
  )
}
