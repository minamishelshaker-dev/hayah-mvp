// Creates demo accounts for the investor walkthrough.
// Usage: npm run seed   (reads .env.local; needs SUPABASE_SERVICE_ROLE_KEY)
import { createClient } from '@supabase/supabase-js'

const url = process.env.NEXT_PUBLIC_SUPABASE_URL
const key = process.env.SUPABASE_SERVICE_ROLE_KEY
if (!url || !key) throw new Error('Set NEXT_PUBLIC_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in .env.local')

// Demo accounts are a known door into the system. Refuse to create them unless the operator says so explicitly,
// and never with a password that is written in the repository.
if (process.env.SEED_CONFIRM !== 'yes') {
  throw new Error('Refusing to seed: set SEED_CONFIRM=yes to confirm this is a demo/staging project, never one holding real cases.')
}
import { randomBytes } from 'node:crypto'
const PASSWORD = process.env.SEED_PASSWORD || `Demo-${randomBytes(9).toString('base64url')}`
const admin = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } })

const users = [
  { email: 'admin@hayah.demo', name: 'مدير المنصة', role: 'admin' },
  { email: 'mediator1@hayah.demo', name: 'أ. هالة الشريف', role: 'mediator', years: 14, spec: ['تجاري', 'مقاولات'], bio: 'وسيطة في النزاعات التجارية وعقود المقاولات.' },
  { email: 'mediator2@hayah.demo', name: 'د. كريم عبد الرحمن', role: 'mediator', years: 9, spec: ['شركات', 'توريد'], bio: 'محكّم ووسيط في نزاعات الشركاء وعقود التوريد.' },
  { email: 'arbitrator1@hayah.demo', name: 'د. ماجد الصاوي', role: 'arbitrator', years: 20, spec: ['تجاري', 'مقاولات'], bio: 'محكّم في المنازعات التجارية وعقود المقاولات.' },
  { email: 'claimant@hayah.demo', name: 'شركة النيل للتجارة', role: 'party' },
  { email: 'respondent@hayah.demo', name: 'شركة الدلتا للتوريدات', role: 'party' },
]

for (const u of users) {
  let id
  const { data, error } = await admin.auth.admin.createUser({
    email: u.email, password: PASSWORD, email_confirm: true, user_metadata: { full_name: u.name },
  })
  if (error) {
    const { data: list } = await admin.auth.admin.listUsers({ perPage: 200 })
    id = list?.users.find((x) => x.email === u.email)?.id
    if (!id) throw error
  } else id = data.user.id

  // The service role is allowed to set role / KYC (normal users are not).
  const { error: pErr } = await admin.from('profiles').update({ role: u.role, kyc_status: 'verified' }).eq('id', id)
  if (pErr) throw pErr
  if (u.role === 'mediator' || u.role === 'arbitrator') {
    const { error: mErr } = await admin.from('mediator_profiles')
      .update({ bio: u.bio, specializations: u.spec, years_experience: u.years }).eq('id', id)
    if (mErr) throw mErr
  }
  console.log('ok', u.email)
}
console.log(`\nDone. Password for all demo accounts (not stored anywhere): ${PASSWORD}\nDelete these accounts before the first real case.`)
