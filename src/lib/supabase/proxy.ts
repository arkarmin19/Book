import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

import { publicEnv } from "@/lib/env";
import type { Database } from "@/types/database.types";

/**
 * Refreshes the Supabase auth session for an incoming request.
 *
 * Returns the response that carries any refreshed auth cookies, plus the
 * verified user id (or null). Callers must return `response` (or copy its
 * cookies onto their own response), otherwise sessions are lost.
 */
export async function updateSession(request: NextRequest) {
  let response = NextResponse.next({ request });

  const supabase = createServerClient<Database>(
    publicEnv.NEXT_PUBLIC_SUPABASE_URL,
    publicEnv.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet, headers?: Record<string, string>) {
          // 1. Make refreshed cookies visible to Server Components in this request.
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
          // 2. Rebuild the response so it carries the updated request cookies.
          response = NextResponse.next({ request });
          // 3. Send refreshed cookies back to the browser.
          cookiesToSet.forEach(({ name, value, options }) => {
            response.cookies.set(name, value, options);
          });
          // 4. Newer @supabase/ssr versions pass cache headers so CDNs never
          //    cache a response that sets auth cookies.
          if (headers) {
            Object.entries(headers).forEach(([key, value]) => response.headers.set(key, value));
          }
        },
      },
    },
  );

  // IMPORTANT: no code between createServerClient and getClaims().
  // getClaims() verifies the JWT signature; never trust getSession() on the server.
  const { data } = await supabase.auth.getClaims();
  const userId = typeof data?.claims?.sub === "string" ? data.claims.sub : null;

  return { response, userId };
}
