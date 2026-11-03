import { notFound } from 'next/navigation'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import PrintButton from '@/components/PrintButton'
import { formatDate, formatEgp } from '@/lib/labels'
import type { ArbAward, Arbitration } from '@/lib/types'

export default async function AwardPrintPage(props: { params: Promise<{ id: string }> }) {
  const params = await props.params
  const supabase = await createClient()
  const { data: gate } = await supabase.rpc('arb_gate_info', { p_arb: params.id })
  if (!gate?.accepted) notFound()
  const { data: arbRow } = await supabase.from('arbitrations').select('*').eq('id', params.id).maybeSingle()
  // RLS: a draft is returned only to the seated arbitrator; an issued award to anyone who may read the file.
  const { data: awardRow } = await supabase.from('arb_awards').select('*').eq('arbitration_id', params.id).maybeSingle()
  if (!arbRow || !awardRow) notFound()
  const arb = arbRow as Arbitration
  const award = awardRow as ArbAward

  const ids = [arb.claimant_id, arb.respondent_id, arb.arbitrator_id].filter(Boolean) as string[]
  const { data: people } = await supabase.rpc('profile_names', { p_ids: ids })
  const name = (id: string | null) => ((id && (people as Record<string, string> | null)?.[id]) || '—')
  const draft = award.status === 'draft'

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-2 print:hidden">
        <Link href={`/arbitrations/${arb.id}`} className="hint underline">← العودة إلى الملف</Link>
        <PrintButton />
      </div>
      <article className="space-y-5 rounded-lg border border-navy-100 bg-white p-8 leading-9 print:rounded-none print:border-0 print:p-0">
        <header className="border-b-2 border-gold pb-3 text-center">
          <p className="text-sm text-navy-500">{draft ? 'مسودة للتوقيع الورقي أو الرقمي — ليست حكمًا نافذًا' : award.signing_mode === 'platform' ? 'نسخة من الحكم الموقَّع رقميًا على المنصة' : 'نسخة من الحكم المسجَّل على المنصة'}</p>
          <h1 className="text-2xl">حكم تحكيم</h1>
          <p dir="ltr" className="font-semibold">{arb.arb_number}</p>
        </header>
        <section className="text-sm">
          <p><b>مقدّم الطلب:</b> {name(arb.claimant_id)} — <b>الطرف الآخر:</b> {name(arb.respondent_id)}</p>
          <p><b>المحكّم:</b> {name(arb.arbitrator_id)} — <b>قيمة النزاع:</b> {formatEgp(arb.dispute_value_egp)}</p>
          {award.award_date && <p><b>تاريخ الحكم:</b> {award.award_date}</p>}
        </section>
        <div className="whitespace-pre-wrap">{award.draft_text}</div>
        {award.signing_mode === 'platform' ? (
          <section className="space-y-1 border-t border-navy pt-4 text-sm">
            <p><b>وُقّع إلكترونيًا على منصة حياة:</b> {name(arb.arbitrator_id)} — {award.signed_at ? formatDate(award.signed_at) : ''}</p>
            <p dir="ltr" className="break-all text-start font-mono text-xs">Platform signature (Ed25519, key {award.signing_key_id ?? '—'}): {award.platform_signature ?? 'pending'}</p>
            <p className="text-xs text-navy-500">للتحقق خارج المنصة: نزّل السجل الموقَّع من صفحة الملف وافحصه بالمفتاح العام وسكربت verify-record.</p>
          </section>
        ) : (
          <section className="grid grid-cols-2 gap-10 pt-10 text-sm">
            <div><p>توقيع المحكّم</p><p className="mt-8 border-t border-navy pt-1">{name(arb.arbitrator_id)}</p></div>
            <div><p>التاريخ</p><p className="mt-8 border-t border-navy pt-1">&nbsp;</p></div>
          </section>
        )}
        <footer className="space-y-1 border-t border-navy-100 pt-3 text-xs text-navy-500">
          <p dir="ltr" className="break-all text-start font-mono">Text SHA-256: {award.draft_hash}</p>
          <p>طُبعت من منصة حياة في {formatDate(new Date().toISOString())}. لا تُودِع المنصة الحكم ولا تنفّذه ولا تضمن شكله النظامي ولا قبول المحكمة لتوقيعه الإلكتروني؛ الإيداع والتنفيذ يتمان وفق القانون خارج المنصة.</p>
        </footer>
      </article>
    </div>
  )
}
