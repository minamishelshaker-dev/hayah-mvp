import { createClient } from '@/lib/supabase/server'
import PageFrame from '@/components/PageFrame'
import FormAction from '@/components/FormAction'
import { rateLimited } from '@/lib/ratelimit'
import { acceptInvitation, declineInvitation } from '@/app/(app)/disputes/actions'

type Preview = { dispute_number: string; claimant_name: string; invited_email: string; status: string }

export default async function InvitePage(props: { params: Promise<{ token: string }> }) {
  const params = await props.params
  const next = encodeURIComponent(`/invite/${params.token}`)
  if (await rateLimited('invite-page', 40, 600)) {
    return (
      <PageFrame>
        <div className="mx-auto max-w-md py-12">
          <p role="alert" className="panel font-semibold text-red-700">طلبات كثيرة. حاول بعد قليل.</p>
        </div>
      </PageFrame>
    )
  }
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data } = await supabase.rpc('invitation_preview', { p_token: params.token })
  const inv = data as Preview | null

  return (
    <PageFrame>
      <div className="mx-auto max-w-xl py-8">
        <div className="panel space-y-4">
          {!inv && <p className="font-semibold text-red-700">رابط الدعوة غير صالح.</p>}
          {inv && inv.status !== 'pending' && (
            <p className="font-semibold text-red-700">{inv.status === 'expired' ? 'انتهت صلاحية هذه الدعوة.' : 'تم استخدام هذه الدعوة من قبل.'}</p>
          )}
          {inv && inv.status === 'pending' && (
            <>
              <h1 className="text-xl">دعوة إلى وساطة</h1>
              <p>
                دعاك <span className="font-bold">{inv.claimant_name}</span> إلى وساطة إلكترونية في النزاع{' '}
                <span dir="ltr" className="font-semibold">{inv.dispute_number}</span>. الوساطة اختيارية وسرّية، ولا يترتب على قبولها الإقرار بأي حق.
              </p>
              <p className="hint">الدعوة موجّهة إلى <span dir="ltr">{inv.invited_email}</span>.</p>
              {user ? (
                <div className="space-y-4">
                  <FormAction action={acceptInvitation.bind(null, params.token)} submitLabel="قبول الدعوة" variant="gold" />
                  <FormAction action={declineInvitation.bind(null, params.token)} submitLabel="أرفض الدعوة" variant="danger" className="space-y-2 border-t border-navy-100 pt-4" confirmText="سيُلغى الملف وتُبلَّغ به الجهة الداعية. هل أنت متأكد؟">
                    <label className="label" htmlFor="reason">سبب الرفض (اختياري)</label>
                    <textarea id="reason" name="reason" rows={2} maxLength={500} className="input" />
                  </FormAction>
                </div>
              ) : (
                <div className="flex flex-wrap gap-2">
                  <a href={`/login?next=${next}`} className="btn btn-primary">دخول</a>
                  <a href={`/register?next=${next}`} className="btn btn-ghost">إنشاء حساب</a>
                </div>
              )}
            </>
          )}
        </div>
      </div>
    </PageFrame>
  )
}
