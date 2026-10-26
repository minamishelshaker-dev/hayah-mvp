import type { Metadata } from 'next'
// Cairo is served from this site (no request to Google): Arabic + Latin subsets, the weights the design uses.
import '@fontsource/cairo/arabic-400.css'
import '@fontsource/cairo/arabic-600.css'
import '@fontsource/cairo/arabic-700.css'
import '@fontsource/cairo/arabic-800.css'
import '@fontsource/cairo/latin-400.css'
import '@fontsource/cairo/latin-600.css'
import '@fontsource/cairo/latin-700.css'
import '@fontsource/cairo/latin-800.css'
import './globals.css'

export const metadata: Metadata = {
  title: 'حياة — وساطة وتحكيم إلكترونيان موثّقان',
  description: 'منصة لإدارة الوساطة في النزاعات التجارية في مصر وتوثيق مسارها',
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="ar" dir="rtl">
      <body>{children}</body>
    </html>
  )
}
