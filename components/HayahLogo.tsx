import Link from 'next/link'

type HayahLogoProps = {
  href?: string
  size?: 'sm' | 'md' | 'lg' | 'xl'
  variant?: 'default' | 'dark' | 'mono' | 'white'
  tagline?: boolean
  className?: string
}

export default function HayahLogo({
  href = '/',
  size = 'sm',
  variant = 'default',
  tagline = true,
  className = '',
}: HayahLogoProps) {
  return (
    <Link
      href={href}
      className={`hayah-logo hayah-logo--${size} hayah-logo--${variant} ${className}`.trim()}
      aria-label="Hayah ADR Platform"
    >
      <span className="hayah-logo__wordmark" aria-hidden="true">
        <span className="hayah-logo__accent hayah-logo__accent--left" />
        <span className="hayah-logo__word">Hayah</span>
        <span className="hayah-logo__accent hayah-logo__accent--right" />
      </span>
      {tagline && <span className="hayah-logo__tagline">ADR PLATFORM</span>}
    </Link>
  )
}
