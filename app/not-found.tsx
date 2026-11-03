import Link from 'next/link'
import PageFrame from '@/components/PageFrame'

export const metadata = { title: 'الصفحة غير موجودة' }

export default function NotFound() {
  return (
    <PageFrame>
      <div className="panel mx-auto mt-10 max-w-lg space-y-3 text-center">
        <p dir="ltr" className="text-sm font-semibold text-gold-700">404</p>
        <h1 className="text-xl">الصفحة غير موجودة</h1>
        <p className="hint">قد يكون الرابط غير صحيح أو انتهت صلاحيته. يمكنك العودة إلى الصفحة الرئيسية أو إلى لوحة التحكم.</p>
        <div className="flex justify-center gap-2">
          <Link href="/" className="btn btn-primary">الصفحة الرئيسية</Link>
          <Link href="/dashboard" className="btn btn-ghost">لوحة التحكم</Link>
        </div>
      </div>
    </PageFrame>
  )
}
