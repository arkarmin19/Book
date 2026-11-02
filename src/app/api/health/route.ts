import { fail, ok } from "@/lib/api/response";
import { publicEnv } from "@/lib/env";

/**
 * GET /api/health
 * Confirms the app is running and can reach Supabase Auth with the configured key.
 * Used by the Phase 1 setup check and the Playwright smoke test.
 */
export async function GET() {
  const started = Date.now();

  try {
    const res = await fetch(`${publicEnv.NEXT_PUBLIC_SUPABASE_URL}/auth/v1/health`, {
      headers: { apikey: publicEnv.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY },
      cache: "no-store",
      signal: AbortSignal.timeout(5000),
    });

    if (!res.ok) {
      return fail("SERVICE_UNAVAILABLE", `Supabase Auth responded with HTTP ${res.status}`);
    }

    return ok({
      app: "ok",
      supabaseAuth: "ok",
      latencyMs: Date.now() - started,
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return fail("SERVICE_UNAVAILABLE", `Cannot reach Supabase: ${message}`);
  }
}
