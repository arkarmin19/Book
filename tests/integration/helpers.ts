import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { TZDate } from "@date-fns/tz";
import { nextMonday, set } from "date-fns";

import type { Database } from "@/types/database.types";

/**
 * Helpers for integration tests that run against the LOCAL Supabase stack
 * (npm run db:start). They need SUPABASE_SECRET_KEY in .env.local and are
 * skipped automatically when it is missing (e.g. in CI).
 */

// Load .env.local if present (Node 20.12+). Vitest does not do this by itself.
try {
  process.loadEnvFile(".env.local");
} catch {
  // No .env.local: tests that need Supabase will be skipped.
}

export const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";
const PUBLISHABLE_KEY = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? "";
const SECRET_KEY = process.env.SUPABASE_SECRET_KEY ?? "";

/** Only ever run destructive integration tests against a local stack. */
export const canRunIntegration =
  Boolean(SUPABASE_URL && PUBLISHABLE_KEY && SECRET_KEY) && /^http:\/\/(127\.0\.0\.1|localhost)(:\d+)?$/.test(SUPABASE_URL);

const noSession = { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } };

export function adminClient(): SupabaseClient<Database> {
  return createClient<Database>(SUPABASE_URL, SECRET_KEY, noSession);
}

export const TEST_PASSWORD = "Integration-Test-Pa55!";

/** Creates a confirmed user and returns their id. */
export async function createTestUser(admin: SupabaseClient<Database>, email: string, fullName: string) {
  const { data, error } = await admin.auth.admin.createUser({
    email,
    password: TEST_PASSWORD,
    email_confirm: true,
    user_metadata: { full_name: fullName },
  });
  if (error || !data.user) throw new Error(`createUser(${email}) failed: ${error?.message}`);
  return data.user.id;
}

/** A separate client with its own session, like a separate browser. */
export async function signedInClient(email: string): Promise<SupabaseClient<Database>> {
  const client = createClient<Database>(SUPABASE_URL, PUBLISHABLE_KEY, noSession);
  const { error } = await client.auth.signInWithPassword({ email, password: TEST_PASSWORD });
  if (error) throw new Error(`signIn(${email}) failed: ${error.message}`);
  return client;
}

/** Next Monday (1–7 days ahead) at hh:mm in the given IANA timezone, as an ISO 8601 string with offset. */
export function nextMondayAt(timezone: string, hours: number, minutes = 0): string {
  // TZDate makes date-fns calculate in that timezone; nextMonday is always 1–7 days ahead.
  const monday = nextMonday(TZDate.tz(timezone));
  return set(monday, { hours, minutes, seconds: 0, milliseconds: 0 }).toISOString();
}

/** Short random suffix so repeated runs never collide. */
export function runId(): string {
  return Math.random().toString(36).slice(2, 8);
}
