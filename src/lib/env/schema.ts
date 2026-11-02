import { z } from "zod";

/**
 * Environment variable schemas.
 *
 * Kept in their own file (no side effects) so unit tests can import them
 * without needing real environment variables.
 */

/** Variables that are safe to expose to the browser (NEXT_PUBLIC_*). */
export const publicEnvSchema = z.object({
  NEXT_PUBLIC_SITE_URL: z.url(),
  NEXT_PUBLIC_SUPABASE_URL: z.url(),
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: z.string().min(1, "Supabase publishable (anon) key is required"),
});

/**
 * Server-only variables. NEVER import these into client components.
 *
 * Resend values are optional until Phase 11 (email notifications);
 * the secret key is optional until the first admin task (staff invites, Phase 6).
 * Code that needs them checks for their presence and fails with a clear error.
 */
export const serverEnvSchema = z.object({
  SUPABASE_SECRET_KEY: z.string().min(1).optional(),
  RESEND_API_KEY: z.string().min(1).optional(),
  EMAIL_FROM: z.string().min(1).optional(),
});

export type PublicEnv = z.infer<typeof publicEnvSchema>;
export type ServerEnv = z.infer<typeof serverEnvSchema>;
