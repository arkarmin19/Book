import { NextResponse, type NextRequest } from "next/server";

import {
  AUTH_PAGES,
  DEFAULT_AFTER_LOGIN_PATH,
  LOGIN_PATH,
  PROTECTED_PREFIXES,
  matchesPrefix,
  safeRedirectPath,
} from "@/lib/routes";
import { updateSession } from "@/lib/supabase/proxy";

/**
 * Next.js 16 Proxy (formerly middleware.ts). Runs before matching routes.
 *
 * 1. Refreshes the Supabase session cookie.
 * 2. Optimistic guard: unauthenticated users can't open /account or /dashboard.
 *
 * This is a convenience layer only. Real authorization lives in Route Handlers,
 * server components and PostgreSQL RLS.
 */
export async function proxy(request: NextRequest) {
  const { response, userId } = await updateSession(request);
  const { pathname, search } = request.nextUrl;

  if (!userId && matchesPrefix(pathname, PROTECTED_PREFIXES)) {
    const url = request.nextUrl.clone();
    url.pathname = LOGIN_PATH;
    url.search = "";
    url.searchParams.set("next", `${pathname}${search}`);
    return withSessionCookies(NextResponse.redirect(url), response);
  }

  if (userId && matchesPrefix(pathname, AUTH_PAGES)) {
    const url = request.nextUrl.clone();
    url.pathname = safeRedirectPath(request.nextUrl.searchParams.get("next"), DEFAULT_AFTER_LOGIN_PATH);
    url.search = "";
    return withSessionCookies(NextResponse.redirect(url), response);
  }

  return response;
}

/** Copy refreshed auth cookies onto a redirect so the session isn't dropped. */
function withSessionCookies(target: NextResponse, source: NextResponse): NextResponse {
  source.cookies.getAll().forEach((cookie) => target.cookies.set(cookie));
  return target;
}

export const config = {
  matcher: [
    // Everything except Next internals, static files and images.
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico)$).*)",
  ],
};
