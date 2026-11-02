import { publicEnvSchema, type PublicEnv } from "./schema";

/**
 * Validated public environment variables.
 *
 * Each NEXT_PUBLIC_* variable must be referenced literally (process.env.NAME)
 * so Next.js can inline it into the browser bundle.
 */
function loadPublicEnv(): PublicEnv {
  const parsed = publicEnvSchema.safeParse({
    NEXT_PUBLIC_SITE_URL: process.env.NEXT_PUBLIC_SITE_URL,
    NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
    NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
  });

  if (!parsed.success) {
    const problems = parsed.error.issues
      .map((issue) => `  - ${issue.path.join(".")}: ${issue.message}`)
      .join("\n");
    throw new Error(
      `Invalid public environment variables. Check .env.local against .env.example:\n${problems}`,
    );
  }

  return parsed.data;
}

export const publicEnv = loadPublicEnv();
