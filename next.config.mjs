const isProd = process.env.NODE_ENV === 'production'
const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL ?? ''
const supabaseWs = supabaseUrl ? supabaseUrl.replace(/^http/, 'ws') : ''

// Content-Security-Policy is shipped in REPORT-ONLY mode: it logs violations in the browser console without blocking.
// Test a full video call and every page, fix what it reports, then rename the header to Content-Security-Policy.
// Note: 'unsafe-inline' scripts are allowed (Next.js inline scripts need nonces to avoid it), so this CSP limits
// where scripts/frames/connections may come from, but it is not a complete XSS barrier.
const csp = [
  "default-src 'self'",
  "base-uri 'self'",
  "form-action 'self'",
  "frame-ancestors 'none'",
  "object-src 'none'",
  `img-src 'self' data: blob: ${supabaseUrl}`,
  "style-src 'self' 'unsafe-inline'",
  "font-src 'self'",
  "script-src 'self' 'unsafe-inline' https://*.daily.co",
  `connect-src 'self' ${supabaseUrl} ${supabaseWs} https://*.daily.co wss://*.daily.co`,
  'frame-src https://*.daily.co',
  "media-src 'self' blob: https://*.daily.co",
  "worker-src 'self' blob:",
].join('; ')

/** @type {import('next').NextConfig} */
const nextConfig = {
  experimental: { serverActions: { bodySizeLimit: '2mb' } },
  async headers() {
    return [
      {
        source: '/:path*',
        headers: [
          { key: 'X-Content-Type-Options', value: 'nosniff' },
          { key: 'X-Frame-Options', value: 'DENY' }, // enforced anti-clickjacking (frame-ancestors above is report-only)
          { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
          { key: 'Permissions-Policy', value: 'geolocation=(), payment=(), usb=()' },
          ...(isProd
            ? [
                { key: 'Strict-Transport-Security', value: 'max-age=31536000; includeSubDomains' },
                // Set CSP_ENFORCE=true on Vercel after a full test (video call + every page) to start BLOCKING violations.
                { key: process.env.CSP_ENFORCE === 'true' ? 'Content-Security-Policy' : 'Content-Security-Policy-Report-Only', value: csp },
              ]
            : []),
        ],
      },
    ]
  },
}
export default nextConfig
