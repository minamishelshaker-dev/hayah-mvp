import Link from 'next/link'
import HayahLogo from '@/components/HayahLogo'

const methods = [
  { number: '01', title: 'التفاوض', text: 'مساحة منظمة لعرض وجهات النظر ومحاولة الوصول إلى حل ودي.' },
  { number: '02', title: 'الوساطة', text: 'إدارة النزاع بمساعدة وسيط، مع توثيق الخطوات والاتفاقات داخل المنصة.' },
  { number: '03', title: 'التوفيق', text: 'استكشاف مقترحات تسوية تساعد الأطراف على تقريب وجهات النظر.' },
  { number: '04', title: 'التحكيم الاتفاقي', text: 'إدارة بعض إجراءات التحكيم عند وجود اتفاق بين الأطراف، وفق نطاق خدمات المنصة.' },
]

const features = [
  { icon: '01', title: 'مسار واضح للنزاع', text: 'تابع مراحل الملف والإجراءات المطلوبة من خلال تجربة رقمية منظمة.' },
  { icon: '02', title: 'مستندات موثقة', text: 'تدعم المنصة حفظ المستندات والتحقق من سلامة الملفات وفق الوظائف المتاحة.' },
  { icon: '03', title: 'جلسات عن بُعد', text: 'إمكانية إدارة جلسات إلكترونية بحسب إعدادات الملف وتوافر الخدمة.' },
  { icon: '04', title: 'اتفاقات وسجل إجراءات', text: 'توثيق الإجراءات والاتفاقات ضمن سجل الملف وفق آليات المنصة.' },
]

export default function Home() {
  return (
    <main className="min-h-screen overflow-hidden bg-[#F4F6F9] text-[#0D1B2A]">
      <header className="sticky top-0 z-40 border-b border-[#0D1B2A]/10 bg-white/95 backdrop-blur">
        <div className="mx-auto flex max-w-7xl items-center justify-between px-5 py-4 lg:px-8">
          <HayahLogo href="/" size="sm" variant="default" className="landing-header-logo" />
          <nav className="hidden items-center gap-7 text-sm font-semibold md:flex">
            <a href="#services" className="transition hover:text-[#0D1B2A]">الخدمات</a>
            <a href="#how-it-works" className="transition hover:text-[#0D1B2A]">كيف تعمل</a>
            <a href="#trust" className="transition hover:text-[#0D1B2A]">التوثيق والثقة</a>
          </nav>
          <div className="flex items-center gap-2">
            <Link href="/login" className="hidden rounded-xl px-4 py-2.5 text-sm font-bold text-[#0D1B2A] hover:bg-[#0D1B2A]/5 sm:inline-flex">تسجيل الدخول</Link>
            <Link href="/register" className="rounded-xl bg-[#0D1B2A] px-4 py-2.5 text-sm font-bold text-white shadow-sm transition hover:bg-[#1B2B3F]">ابدأ الآن</Link>
          </div>
        </div>
      </header>

      <section className="relative isolate">
        <div className="absolute inset-0 -z-10 bg-[radial-gradient(ellipse_at_top_left,_rgba(212,160,23,0.18),_transparent_40%),linear-gradient(135deg,#0D1B2A,#1B2B3F_58%,#0D1B2A)]" />
        <div className="mx-auto grid max-w-7xl items-center gap-12 px-5 py-20 text-white sm:py-24 lg:grid-cols-[1.15fr_0.85fr] lg:px-8 lg:py-28">
          <div>
            <span className="inline-flex items-center gap-2 rounded-full border border-white/20 bg-white/10 px-4 py-2 text-sm font-semibold text-[#F6EBCB]"><span className="h-2 w-2 rounded-full bg-[#F6EBCB]" /> طريق رقمي أكثر تنظيمًا لحل النزاعات</span>
            <h1 className="mt-7 max-w-3xl text-4xl font-extrabold leading-[1.35] sm:text-5xl lg:text-6xl">نحو مستقبل <span className="text-[#F6EBCB]">أسرع للعدالة</span></h1>
            <p className="mt-6 max-w-2xl text-lg leading-9 text-white/80 sm:text-xl">منصة رقمية تساعد الأطراف على إدارة المنازعات المدنية والتجارية، وتنظيم إجراءات التسوية وتوثيق خطواتها في مكان واحد.</p>
            <div className="mt-9 flex flex-wrap gap-3">
              <Link href="/register" className="inline-flex items-center justify-center rounded-xl bg-[#F6EBCB] px-6 py-3.5 font-extrabold text-[#253d3e] shadow-lg transition hover:-translate-y-0.5 hover:bg-[#E6EAF0]">إنشاء حساب <span className="mr-2" aria-hidden="true">←</span></Link>
              <a href="#how-it-works" className="inline-flex items-center justify-center rounded-xl border border-white/30 bg-white/5 px-6 py-3.5 font-bold text-white transition hover:bg-white/10">تعرّف على المنصة</a>
            </div>
            <p className="mt-5 text-xs leading-6 text-white/60">المنصة أداة لإدارة الإجراءات وتوثيقها، ولا تُعد جهة قضائية أو جهة تحكيم.</p>
          </div>
          <div className="relative mx-auto w-full max-w-lg">
            <div className="absolute -inset-5 rounded-[2rem] bg-[#F6EBCB]/10 blur-2xl" />
            <div className="relative rounded-[2rem] border border-white/20 bg-white/10 p-5 shadow-2xl backdrop-blur sm:p-7">
              <div className="flex items-center justify-between border-b border-white/15 pb-5">
                <div><p className="text-sm text-white/65">مسار إدارة النزاع</p><h2 className="mt-1 text-xl font-extrabold">من الخلاف إلى التسوية</h2></div>
                <span className="rounded-2xl bg-[#F6EBCB]/15 p-3 text-2xl text-[#F6EBCB]" aria-hidden="true">⚖</span>
              </div>
              <div className="mt-6 space-y-4">
                {[
                  ['1', 'تسجيل النزاع', 'إدخال البيانات الأساسية والمستندات'],
                  ['2', 'دعوة الطرف الآخر', 'بدء التواصل ضمن مسار منظم'],
                  ['3', 'إدارة الإجراءات', 'اختيار المسار المناسب وتوثيق الخطوات'],
                  ['4', 'توثيق النتيجة', 'حفظ الاتفاق أو نتيجة الإجراءات بحسب الحالة'],
                ].map(([n, title, text]) => <div key={n} className="flex items-center gap-4 rounded-2xl border border-white/10 bg-[#073f42]/45 p-4"><span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-[#F6EBCB] font-extrabold text-[#0D1B2A]">{n}</span><div><h3 className="font-bold">{title}</h3><p className="mt-1 text-sm text-white/65">{text}</p></div></div>)}
              </div>
              <div className="mt-5 rounded-xl bg-white/10 px-4 py-3 text-sm text-white/75">تُحدّد الإجراءات المتاحة وفق نوع الملف وصلاحيات المستخدم.</div>
            </div>
          </div>
        </div>
      </section>

      <section id="trust" className="border-b border-[#dce8e6] bg-white">
        <div className="mx-auto grid max-w-7xl gap-5 px-5 py-7 sm:grid-cols-3 lg:px-8">
          {[['توثيق الإجراءات', 'سجل منظم للخطوات التي تتم داخل المنصة'], ['حماية الوصول', 'إجراءات وصلاحيات بحسب دور المستخدم'], ['إدارة رقمية', 'الوصول إلى تفاصيل الملف من مكان واحد']].map(([title, text]) => <div key={title} className="flex items-start gap-3"><span className="mt-1 flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-[#e5f3f0] font-bold text-[#0D1B2A]">✓</span><div><h2 className="font-extrabold">{title}</h2><p className="mt-1 text-sm leading-6 text-[#3A4C63]">{text}</p></div></div>)}
        </div>
      </section>

      <section id="services" className="mx-auto max-w-7xl px-5 py-20 lg:px-8 lg:py-24">
        <div className="mx-auto max-w-3xl text-center"><p className="font-extrabold text-[#0D1B2A]">خدمات المنصة</p><h2 className="mt-3 text-3xl font-extrabold leading-relaxed sm:text-4xl">خيارات متعددة لإدارة الخلافات</h2><p className="mt-3 leading-8 text-[#3A4C63]">تختلف الطريقة الأنسب بحسب طبيعة النزاع وموافقة الأطراف والإطار القانوني المنطبق.</p></div>
        <div className="mt-12 grid gap-5 sm:grid-cols-2 lg:grid-cols-4">
          {methods.map((m) => <article key={m.number} className="group rounded-2xl border border-[#dce8e6] bg-white p-6 shadow-[0_4px_20px_rgba(13,27,42,0.05)] transition hover:-translate-y-1 hover:border-[#0D1B2A]/40 hover:shadow-[0_12px_32px_rgba(13,115,119,0.12)]"><span className="flex h-12 w-12 items-center justify-center rounded-2xl bg-[#e5f3f0] text-sm font-extrabold text-[#0D1B2A] transition group-hover:bg-[#0D1B2A] group-hover:text-white">{m.number}</span><h3 className="mt-5 text-xl font-extrabold">{m.title}</h3><p className="mt-3 text-sm leading-7 text-[#3A4C63]">{m.text}</p></article>)}
        </div>
      </section>

      <section id="how-it-works" className="bg-[#eaf4f2] py-20 lg:py-24">
        <div className="mx-auto grid max-w-7xl items-center gap-12 px-5 lg:grid-cols-2 lg:px-8">
          <div><p className="font-extrabold text-[#0D1B2A]">كيف تعمل حياة؟</p><h2 className="mt-3 text-3xl font-extrabold leading-relaxed sm:text-4xl">خطوات أوضح، وتجربة أكثر تنظيمًا</h2><p className="mt-5 leading-8 text-[#3A4C63]">تجمع المنصة عناصر إدارة النزاع في مسار رقمي واحد، مع إبقاء القرارات الإجرائية للأطراف والجهات المختصة بحسب الحالة.</p><Link href="/register" className="mt-7 inline-flex rounded-xl bg-[#0D1B2A] px-6 py-3.5 font-bold text-white transition hover:bg-[#1B2B3F]">ابدأ باستخدام المنصة</Link></div>
          <div className="space-y-4">{features.map((f) => <div key={f.icon} className="flex gap-4 rounded-2xl border border-[#d5e6e3] bg-white p-5"><span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-[#0D1B2A] font-extrabold text-white">{f.icon}</span><div><h3 className="font-extrabold">{f.title}</h3><p className="mt-1 text-sm leading-7 text-[#3A4C63]">{f.text}</p></div></div>)}</div>
        </div>
      </section>

      <section className="mx-auto max-w-7xl px-5 py-20 lg:px-8">
        <div className="overflow-hidden rounded-[2rem] bg-[#103f42] px-6 py-12 text-center text-white sm:px-12 sm:py-16">
          <p className="font-bold text-[#F6EBCB]">ابدأ بخطوتك الأولى</p><h2 className="mx-auto mt-3 max-w-3xl text-3xl font-extrabold leading-relaxed sm:text-4xl">إدارة رقمية للنزاعات، من البداية وحتى توثيق النتيجة</h2><p className="mx-auto mt-4 max-w-2xl leading-8 text-white/70">أنشئ حسابًا للاطلاع على الوظائف المتاحة داخل المنصة.</p><Link href="/register" className="mt-7 inline-flex rounded-xl bg-[#F6EBCB] px-6 py-3.5 font-extrabold text-[#0D1B2A] transition hover:bg-[#E6EAF0]">إنشاء حساب</Link>
        </div>
      </section>

      <footer className="border-t border-[#dce8e6] bg-white">
        <div className="mx-auto flex max-w-7xl flex-col gap-4 px-5 py-8 text-sm text-[#3A4C63] sm:flex-row sm:items-center sm:justify-between lg:px-8">
          <div><p className="font-extrabold text-[#0D1B2A]">حياة <span className="text-[#0D1B2A]">.</span></p><p className="mt-1">حلول رقمية لتسوية المنازعات</p></div>
          <p className="max-w-2xl leading-6">تنبيه: المنصة أداة لإدارة الإجراءات وتوثيقها وليست جهة قضائية أو جهة تحكيم. يجب مراجعة النصوص القانونية والإجراءات قبل أي استخدام فعلي.</p>
          <Link href="/login" className="font-bold text-[#0D1B2A] hover:underline">تسجيل الدخول</Link>
        </div>
      </footer>
    </main>
  )
}
