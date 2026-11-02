import { expect, test } from "@playwright/test";

test("home page renders", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { level: 1, name: "BookFlow" })).toBeVisible();
});

test("health check reaches Supabase", async ({ request }) => {
  const res = await request.get("/api/health");
  expect(res.status()).toBe(200);
  const body = (await res.json()) as { data: { supabaseAuth: string } };
  expect(body.data.supabaseAuth).toBe("ok");
});

test("protected routes redirect anonymous users to login", async ({ page }) => {
  await page.goto("/dashboard");
  // The login page itself is built in Phase 3; here we only check the redirect.
  await expect(page).toHaveURL(/\/login\?next=%2Fdashboard/);
});
