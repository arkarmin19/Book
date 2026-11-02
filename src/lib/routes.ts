/**
 * Route groups used by the proxy for optimistic auth checks.
 * Role checks (owner / manager / staff) happen on the server in Phase 3,
 * never only here.
 */
export const PROTECTED_PREFIXES = ["/account", "/dashboard"] as const;

/** Pages a logged-in user should not see (they get sent to their dashboard). */
export const AUTH_PAGES = ["/login", "/register"] as const;

export const LOGIN_PATH = "/login";
export const DEFAULT_AFTER_LOGIN_PATH = "/account";

export function matchesPrefix(pathname: string, prefixes: readonly string[]): boolean {
  return prefixes.some((prefix) => pathname === prefix || pathname.startsWith(`${prefix}/`));
}

/**
 * Only allow same-site relative redirects (e.g. "/dashboard?x=1").
 * Blocks open redirects such as "//evil.com" or "https://evil.com".
 */
export function safeRedirectPath(value: string | null | undefined, fallback = DEFAULT_AFTER_LOGIN_PATH): string {
  if (!value) return fallback;
  if (!value.startsWith("/") || value.startsWith("//") || value.startsWith("/\\")) return fallback;
  return value;
}
