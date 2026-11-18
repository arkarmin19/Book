import type { SupabaseClient } from "@supabase/supabase-js";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { isSlotConflict } from "@/lib/api/db-errors";
import type { Database } from "@/types/database.types";

import { adminClient, canRunIntegration, createTestUser, nextMondayAt, runId, signedInClient } from "./helpers";

/**
 * Requirement (master prompt §13): two different customer sessions try to book
 * the same staff member and time slot at the same moment. Exactly one succeeds.
 *
 * Runs against the local Supabase stack: npm run db:start, then npm run test:integration
 */
describe.skipIf(!canRunIntegration)("booking concurrency (local Supabase)", () => {
  // Created in beforeAll: a skipped suite still runs this function body during collection.
  let admin: SupabaseClient<Database>;
  const id = runId();
  const emails = {
    owner: `owner-${id}@bookflow.test`,
    staff: `staff-${id}@bookflow.test`,
    customerA: `customer-a-${id}@bookflow.test`,
    customerB: `customer-b-${id}@bookflow.test`,
  };
  const userIds: string[] = [];
  let businessId = "";
  let serviceId = "";
  let staffId = "";

  beforeAll(async () => {
    admin = adminClient();
    const ownerId = await createTestUser(admin, emails.owner, "Owner Test");
    staffId = await createTestUser(admin, emails.staff, "Staff Test");
    userIds.push(ownerId, staffId);
    userIds.push(await createTestUser(admin, emails.customerA, "Customer A"));
    userIds.push(await createTestUser(admin, emails.customerB, "Customer B"));

    const business = await admin
      .from("businesses")
      .insert({ owner_id: ownerId, name: `Race Test ${id}`, slug: `race-test-${id}`, timezone: "Asia/Bangkok" })
      .select("id")
      .single();
    if (business.error) throw business.error;
    businessId = business.data.id;

    const member = await admin
      .from("business_members")
      .insert({ business_id: businessId, user_id: staffId, role: "staff", status: "active", display_name: "Staff" });
    if (member.error) throw member.error;

    const service = await admin
      .from("services")
      .insert({ business_id: businessId, name: "Haircut", duration_minutes: 60, price: 500 })
      .select("id")
      .single();
    if (service.error) throw service.error;
    serviceId = service.data.id;

    const links = await admin
      .from("staff_services")
      .insert({ business_id: businessId, staff_user_id: staffId, service_id: serviceId });
    if (links.error) throw links.error;

    const hours = await admin
      .from("staff_working_hours")
      .insert({ business_id: businessId, staff_user_id: staffId, weekday: 1, start_time: "09:00", end_time: "17:00" });
    if (hours.error) throw hours.error;
  });

  afterAll(async () => {
    if (!admin) return;
    // Order matters: bookings → business (cascades members, services, hours) → users.
    if (businessId) {
      await admin.from("bookings").delete().eq("business_id", businessId);
      await admin.from("businesses").delete().eq("id", businessId);
    }
    for (const userId of userIds) {
      await admin.auth.admin.deleteUser(userId);
    }
  });

  it("lets exactly one of two simultaneous bookings for the same slot succeed", async () => {
    const [customerA, customerB] = await Promise.all([
      signedInClient(emails.customerA),
      signedInClient(emails.customerB),
    ]);
    const slot = nextMondayAt("Asia/Bangkok", 10);
    const args = { p_service_id: serviceId, p_starts_at: slot, p_staff_user_id: staffId };

    const results = await Promise.all([customerA.rpc("create_booking", args), customerB.rpc("create_booking", args)]);

    const successes = results.filter((r) => r.error === null);
    const failures = results.filter((r) => r.error !== null);

    expect(successes).toHaveLength(1);
    expect(failures).toHaveLength(1);
    expect(isSlotConflict(failures[0].error!)).toBe(true);

    const { count } = await admin
      .from("bookings")
      .select("id", { count: "exact", head: true })
      .eq("staff_user_id", staffId)
      .eq("status", "confirmed");
    expect(count).toBe(1);
  });

  it("frees the slot when the winning booking is cancelled", async () => {
    const customerA = await signedInClient(emails.customerA);
    const customerB = await signedInClient(emails.customerB);
    const slot = nextMondayAt("Asia/Bangkok", 13);
    const args = { p_service_id: serviceId, p_starts_at: slot, p_staff_user_id: staffId };

    const first = await customerA.rpc("create_booking", args);
    expect(first.error).toBeNull();

    const blocked = await customerB.rpc("create_booking", args);
    expect(blocked.error?.code).toBe("BF009");

    const cancel = await customerA.rpc("cancel_booking", { p_booking_id: first.data!.id });
    expect(cancel.error).toBeNull();

    const second = await customerB.rpc("create_booking", args);
    expect(second.error).toBeNull();
  });
});
