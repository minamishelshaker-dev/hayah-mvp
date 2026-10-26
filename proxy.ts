import { createServerClient } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

const PROTECTED = ['/dashboard', '/disputes', '/sessions', '/admin', '/consent', '/reset-password', '/mfa', '/arbitrations', '/hearings']

export async function proxy(request: NextRequest) {
  // Server components cannot read the URL, so the middleware hands them the path.
  const forward = () => {
    const h = new Headers(request.headers)
    h.set('x-pathname', request.nextUrl.pathname)
    return NextResponse.next({ request: { headers: h } })
  }
  let response = forward()
  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll: () => request.cookies.getAll(),
        setAll: (list) => {
          list.forEach(({ name, value }) => request.cookies.set(name, value))
          response = forward()
          list.forEach(({ name, value, options }) => response.cookies.set(name, value, options))
        },
      },
    }
  )
  const { data: { user } } = await supabase.auth.getUser()
  const path = request.nextUrl.pathname

  if (!user && PROTECTED.some((p) => path.startsWith(p))) {
    const url = request.nextUrl.clone()
    url.pathname = '/login'
    url.search = ''
    url.searchParams.set('next', path)
    return NextResponse.redirect(url)
  }
  if (user && (path === '/login' || path === '/register')) {
    const url = request.nextUrl.clone()
    url.pathname = '/dashboard'
    url.search = ''
    return NextResponse.redirect(url)
  }
  return response
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)'],
}
