'use server'

import { redirect } from 'next/navigation'
import { z } from 'zod'
import { createClient } from '@/lib/supabase/server'
import { safeNext } from '@/lib/utils'
import { rateLimited } from '@/lib/ratelimit'
import type { ActionResult } from '@/lib/types'

const TOO_MANY = 'محاولات كثيرة. انتظر بضع دقائق ثم أعد المحاولة.'

export async function login(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  const who = String(fd.get('email') ?? '').trim().toLowerCase()
  if ((await rateLimited('login', 20, 600)) || (await rateLimited('login-email', 8, 600, who))) return { error: TOO_MANY }
  const { error } = await (await createClient()).auth.signInWithPassword({
    email: String(fd.get('email') ?? '').trim(),
    password: String(fd.get('password') ?? ''),
  })
  if (error) return { error: 'البريد الإلكتروني أو كلمة المرور غير صحيحة' }
  redirect(safeNext(fd.get('next')))
}

const registerSchema = z.object({
  full_name: z.string().trim().min(3, 'أدخل الاسم الكامل'),
  email: z.string().trim().email('البريد الإلكتروني غير صالح'),
  password: z.string().min(8, 'كلمة المرور يجب ألا تقل عن 8 أحرف'),
  phone: z.string().trim().optional(),
  requested_role: z.enum(['party', 'lawyer', 'mediator', 'arbitrator']),
  bar_number: z.string().trim().optional(),
})

export async function register(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  if (await rateLimited('register', 8, 3600)) return { error: TOO_MANY }
  const parsed = registerSchema.safeParse(Object.fromEntries(fd))
  if (!parsed.success) return { error: parsed.error.issues[0].message }
  const v = parsed.data
  if (v.requested_role === 'lawyer' && !v.bar_number) return { error: 'أدخل رقم القيد بالنقابة' }

  const { data, error } = await (await createClient()).auth.signUp({
    email: v.email,
    password: v.password,
    // The database ignores this role request: everyone starts as "party" until an admin promotes them.
    options: {
      // After clicking the confirmation email the user lands here and gets a session.
      emailRedirectTo: `${process.env.NEXT_PUBLIC_APP_URL ?? 'http://localhost:3000'}/auth/callback?next=${encodeURIComponent(safeNext(fd.get('next')))}`,
      data: { full_name: v.full_name, phone: v.phone, requested_role: v.requested_role, bar_number: v.bar_number },
    },
  })
  if (error) return { error: 'تعذّر إنشاء الحساب: ' + error.message }
  if (data.session) redirect(safeNext(fd.get('next')))
  return { message: 'تم إنشاء الحساب. افتح رسالة التفعيل في بريدك ثم سجّل الدخول.' }
}

export async function requestPasswordReset(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  const email = String(fd.get('email') ?? '').trim()
  if (!z.string().email().safeParse(email).success) return { error: 'البريد الإلكتروني غير صالح' }
  if ((await rateLimited('forgot', 8, 3600)) || (await rateLimited('forgot-email', 3, 3600, email.toLowerCase()))) return { error: TOO_MANY }
  const base = process.env.NEXT_PUBLIC_APP_URL ?? 'http://localhost:3000'
  await (await createClient()).auth.resetPasswordForEmail(email, {
    redirectTo: `${base}/auth/callback?next=${encodeURIComponent('/reset-password')}`,
  })
  // Same answer whether or not the address is registered, so the form cannot be used to probe for accounts.
  return { message: 'إن كان البريد مسجّلًا لدينا فسيصلك رابط لتعيين كلمة مرور جديدة. افتحه من نفس المتصفح الذي طلبت منه.' }
}

export async function updatePassword(_prev: ActionResult, fd: FormData): Promise<ActionResult> {
  const password = String(fd.get('password') ?? '')
  if (password.length < 8) return { error: 'كلمة المرور يجب ألا تقل عن 8 أحرف' }
  if (password !== String(fd.get('confirm') ?? '')) return { error: 'كلمتا المرور غير متطابقتين' }
  const { error } = await (await createClient()).auth.updateUser({ password })
  if (error) return { error: 'تعذّر تغيير كلمة المرور: ' + error.message }
  redirect('/dashboard')
}
