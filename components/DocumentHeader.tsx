import HayahLogo from '@/components/HayahLogo'
import { BRAND } from '@/lib/brand'

// Letterhead for printed / saved-as-PDF documents. The app header is hidden when printing,
// so this carries the identity onto the paper (monochrome logo: the guidelines' print version).
export default function DocumentHeader() {
  return (
    <div className="hidden border-b-2 border-gold pb-3 text-center print:block">
      <div className="flex justify-center"><HayahLogo href="/" size="sm" variant="mono" /></div>
      <p className="mt-1 text-xs text-navy-500">{BRAND.nameAr}</p>
    </div>
  )
}
