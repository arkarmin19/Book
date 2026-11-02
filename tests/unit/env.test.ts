import { describe, expect, it } from "vitest";

import { publicEnvSchema, serverEnvSchema } from "@/lib/env/schema";

const validPublic = {
  NEXT_PUBLIC_SITE_URL: "http://localhost:3000",
  NEXT_PUBLIC_SUPABASE_URL: "http://127.0.0.1:54321",
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: "sb_publishable_example",
};

describe("publicEnvSchema", () => {
  it("accepts a complete, valid configuration", () => {
    expect(publicEnvSchema.safeParse(validPublic).success).toBe(true);
  });

  it("rejects a missing publishable key", () => {
    const result = publicEnvSchema.safeParse({ ...validPublic, NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: "" });
    expect(result.success).toBe(false);
  });

  it("rejects an invalid Supabase URL", () => {
    const result = publicEnvSchema.safeParse({ ...validPublic, NEXT_PUBLIC_SUPABASE_URL: "not-a-url" });
    expect(result.success).toBe(false);
  });
});

describe("serverEnvSchema", () => {
  it("allows optional values to be absent during early phases", () => {
    expect(serverEnvSchema.safeParse({}).success).toBe(true);
  });

  it("rejects empty strings for provided secrets", () => {
    expect(serverEnvSchema.safeParse({ SUPABASE_SECRET_KEY: "" }).success).toBe(false);
  });
});
