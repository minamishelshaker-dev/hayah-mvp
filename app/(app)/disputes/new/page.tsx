import { createClient } from '@/lib/supabase/server'
import NewDisputeForm from '@/components/dispute/NewDisputeForm'

export default async function NewDisputePage() {
  const supabase = await createClient()
  const { data } = await supabase.from('fx_rates').select('currency, egp_per_unit, rate_date')
  const rates = (data ?? []).map((r) => ({ currency: r.currency as string, egp_per_unit: Number(r.egp_per_unit), rate_date: r.rate_date as string }))
  return <NewDisputeForm rates={rates} />
}
