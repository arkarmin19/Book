import "server-only";

import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

import { publicEnv } from "@/lib/env";
import type { Database } from "@/types/database.types";

/**
 * Supabase client for Server Components, Server Actions and Route Handlers.
 *
 * It acts as the logged-in user (session read from cookies), so RLS applies.
 * Create a new client per request; never share one between requests.
 */
export async function createClient() {
  const cookieStore = await cookies();

  return createServerClient<Database>(
    publicEnv.NEXT_PUBLIC_SUPABASE_URL,
    publicEnv.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) => {
              cookieStore.set(name, value, options);
            });
          } catch {
            // Server Components cannot set cookies. This is safe to ignore
            // because src/proxy.ts refreshes the session on every request.
          }
        },
      },
    },
  );
}
