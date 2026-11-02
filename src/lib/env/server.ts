import "server-only";

import { serverEnvSchema, type ServerEnv } from "./schema";

let cached: ServerEnv | null = null;

/**
 * Validated server-only environment variables.
 * The `server-only` import makes the build fail if a client component imports this file.
 */
export function getServerEnv(): ServerEnv {
  if (cached) return cached;

  const parsed = serverEnvSchema.safeParse({
    SUPABASE_SECRET_KEY: process.env.SUPABASE_SECRET_KEY || undefined,
    RESEND_API_KEY: process.env.RESEND_API_KEY || undefined,
    EMAIL_FROM: process.env.EMAIL_FROM || undefined,
  });

  if (!parsed.success) {
    const problems = parsed.error.issues
      .map((issue) => `  - ${issue.path.join(".")}: ${issue.message}`)
      .join("\n");
    throw new Error(`Invalid server environment variables:\n${problems}`);
  }

  cached = parsed.data;
  return cached;
}

/** Returns a required server variable or throws a clear error naming it. */
export function requireServerEnv<K extends keyof ServerEnv>(key: K): NonNullable<ServerEnv[K]> {
  const value = getServerEnv()[key];
  if (value === undefined || value === null || value === "") {
    throw new Error(`Missing required server environment variable: ${String(key)}`);
  }
  return value as NonNullable<ServerEnv[K]>;
}
