import { describe, expect, it } from "vitest";

import { PROTECTED_PREFIXES, matchesPrefix, safeRedirectPath } from "@/lib/routes";

describe("matchesPrefix", () => {
  it("matches the prefix itself and nested paths", () => {
    expect(matchesPrefix("/dashboard", PROTECTED_PREFIXES)).toBe(true);
    expect(matchesPrefix("/dashboard/abc/calendar", PROTECTED_PREFIXES)).toBe(true);
    expect(matchesPrefix("/account/appointments", PROTECTED_PREFIXES)).toBe(true);
  });

  it("does not match lookalike paths", () => {
    expect(matchesPrefix("/dashboards", PROTECTED_PREFIXES)).toBe(false);
    expect(matchesPrefix("/accountant", PROTECTED_PREFIXES)).toBe(false);
    expect(matchesPrefix("/", PROTECTED_PREFIXES)).toBe(false);
  });
});

describe("safeRedirectPath", () => {
  it("keeps same-site relative paths", () => {
    expect(safeRedirectPath("/dashboard?tab=week")).toBe("/dashboard?tab=week");
  });

  it("blocks open redirects", () => {
    expect(safeRedirectPath("https://evil.com")).toBe("/account");
    expect(safeRedirectPath("//evil.com")).toBe("/account");
    expect(safeRedirectPath("/\\evil.com")).toBe("/account");
  });

  it("falls back when empty", () => {
    expect(safeRedirectPath(null)).toBe("/account");
    expect(safeRedirectPath("", "/dashboard")).toBe("/dashboard");
  });
});
