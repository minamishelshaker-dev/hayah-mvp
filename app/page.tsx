import Link from 'next/link'

const POINTS = [
  { t: 'مستندات مختومة', d: 'كل ملف يُرفع تُحسب له بصمة SHA-256 على الخادم، ويمكن لأي طرف إعادة فحص سلامته في أي وقت.' },
  { t: 'سجل تدقيق متسلسل', d: 'كل إجراء يُسجَّل تلقائيًا في قاعدة البيانات ضمن سلسلة بصمات لا تقبل التعديل أو الحذف، ويمكن للمدير التحقق من سلامة السلسلة.' },
  { t: 'اتفاق تسوية بتوقيع الطرفين', d: 'يصوغ الوسيط الاتفاق ثم يُغلق نصه، ويوقّع كل طرف بعد إعادة إدخال كلمة المرور، مع حفظ بصمة النص ووقت التوقيع وعنوان الاتصال.' },
]

export default function Home() {
  return (
    <main className="min-h-screen">
      <header className="mx-auto flex max-w-5xl items-center justify-between px-4 py-5">
        <span className="text-2xl font-extrabold">حياة<span className="text-gold">.</span></span>
        <nav className="flex gap-2">
          <Link href="/login" className="btn btn-ghost">دخول</Link>
          <Link href="/register" className="btn btn-primary">إنشاء حساب</Link>
        </nav>
      </header>

      <section className="bg-navy text-white">
        <div className="mx-auto max-w-5xl px-4 py-16 sm:py-24">
          <h1 className="max-w-2xl text-3xl leading-snug sm:text-5xl sm:leading-snug">
            وساطة إلكترونية للنزاعات التجارية، وكل خطوة فيها موثّقة
          </h1>
          <p className="mt-5 max-w-xl text-lg text-navy-100">
            شركتان، وسيط تعتمده المنصة، جلسات بالفيديو، واتفاق تسوية موقّع إلكترونيًا. وإن لم تنتهِ الوساطة بتسوية، فمسار اختياري إلى تحكيم اتفاقي يُدار على المنصة.
          </p>
          <div className="mt-8 flex flex-wrap gap-3">
            <Link href="/register" className="btn btn-gold">ابدأ نزاعًا جديدًا</Link>
            <Link href="/login" className="btn border border-white/30 text-white hover:bg-white/10">لدي حساب</Link>
          </div>
        </div>
      </section>

      <section className="mx-auto grid max-w-5xl gap-4 px-4 py-12 sm:grid-cols-3">
        {POINTS.map((p) => (
          <div key={p.t} className="panel">
            <h2 className="mb-2 text-lg">{p.t}</h2>
            <p className="hint">{p.d}</p>
          </div>
        ))}
      </section>

      <footer className="mx-auto max-w-5xl px-4 pb-10 text-sm text-navy-500">
        <p className="mb-2"><Link href="/verify" className="font-semibold text-gold-700 underline">التحقق من محضر صادر عن المنصة</Link></p>
        نسخة تجريبية للعرض. التوقيع الإلكتروني فيها توقيع بسيط داخل المنصة، وليس توقيعًا مرخّصًا من هيئة تنمية صناعة تكنولوجيا المعلومات، ويجب مراجعة نصوص الاتفاقات قانونيًا قبل أي استخدام فعلي. وفي التحكيم: المنصة أداة لإدارة الإجراءات وتوثيقها وليست جهة تحكيم، ولا تُصدر حكمًا قابلًا للتنفيذ؛ اتفاق التحكيم والحكم يُوقَّعان خارجها.
      </footer>
    </main>
  )
}
