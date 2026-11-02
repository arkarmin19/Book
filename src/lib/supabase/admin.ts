import "server-only";

import { createClient } from "@supabase/supabase-js";

import { publicEnv } from "@/lib/env";
import { requireServerEnv } from "@/lib/env/server";
import type { Database } from "@/types/database.types";

/**
 * Admin client using the Supabase SECRET key. It BYPASSES Row Level Security.
 *
 * Only use it for tasks a user's session cannot do, e.g. sending staff invites
 * (auth.admin.inviteUserByEmail) or writing notification logs from the server.
 * Always run your own authorization check before calling it.
 */
export function createAdminClient() {
  return createClient<Database>(
    publicEnv.NEXT_PUBLIC_SUPABASE_URL,
    requireServerEnv("SUPABASE_SECRET_KEY"),
    {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    },
  );
}
