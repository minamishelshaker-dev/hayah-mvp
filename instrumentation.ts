// Server-side error visibility without a third-party package: every unhandled request error becomes ONE structured JSON line
// in the Vercel runtime logs (searchable, and ready for a log drain). Message and stack only; never request bodies or headers,
// because pages here carry case content. To add Sentry later: `npx @sentry/wizard@latest -i nextjs` (it extends this hook).
export function onRequestError(
  err: unknown,
  request: { path: string; method: string },
  context: { routePath?: string; routeType?: string; routerKind?: string }
) {
  const e = err as { message?: string; stack?: string; digest?: string }
  console.error(JSON.stringify({
    level: 'error', at: new Date().toISOString(), digest: e?.digest, message: e?.message,
    stack: e?.stack?.split('\n').slice(0, 8).join('\n'), method: request.method, path: request.path.split('?')[0],
    route: context.routePath, routeType: context.routeType,
  }))
}
