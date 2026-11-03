import type { Metadata, Viewport } from 'next'
// Fonts are served from this site (no request to Google): Cairo for Arabic/Latin UI text,
// Great Vibes only for the Hayah wordmark (the single display font approved by the brand guidelines).
import '@fontsource/cairo/arabic-400.css'
import '@fontsource/cairo/arabic-600.css'
import '@fontsource/cairo/arabic-700.css'
import '@fontsource/cairo/arabic-800.css'
import '@fontsource/cairo/latin-400.css'
import '@fontsource/cairo/latin-600.css'
import '@fontsource/cairo/latin-700.css'
import '@fontsource/cairo/latin-800.css'
import '@fontsource/great-vibes/latin-400.css'
import './globals.css'
import { BRAND } from '@/lib/brand'

const base = process.env.NEXT_PUBLIC_APP_URL ?? 'https://hayah-launch.vercel.app'

export const metadata: Metadata = {
  metadataBase: new URL(base),
  title: { default: BRAND.siteTitle, template: `%s — ${BRAND.nameAr}` },
  description: BRAND.siteDescription,
  applicationName: BRAND.nameEn,
  openGraph: {
    type: 'website',
    siteName: BRAND.nameEn,
    locale: 'ar_EG',
    title: BRAND.siteTitle,
    description: BRAND.siteDescription,
    images: [{ url: '/og.png', width: 1200, height: 630, alt: BRAND.nameEn }],
  },
  twitter: { card: 'summary_large_image', title: BRAND.siteTitle, description: BRAND.siteDescription, images: ['/og.png'] },
}

export const viewport: Viewport = { themeColor: BRAND.navy }

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="ar" dir="rtl">
      <body>{children}</body>
    </html>
  )
}
