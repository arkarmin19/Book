// ============================================================================
// BookFlow demo data for LOCAL development.
//
//   npm run db:reset     # fresh database from migrations
//   npm run db:seed      # this script
//
// Uses the official Supabase admin API (secret key) so the demo users can log
// in normally. Refuses to run against anything except a local Supabase stack.
// ============================================================================
import { createClient } from "@supabase/supabase-js";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const secret = process.env.SUPABASE_SECRET_KEY;

if (!url || !secret) {
  console.error("Missing NEXT_PUBLIC_SUPABASE_URL or SUPABASE_SECRET_KEY in .env.local");
  process.exit(1);
}
if (!/^http:\/\/(127\.0\.0\.1|localhost)(:\d+)?$/.test(url)) {
  console.error(`Refusing to seed a non-local database: ${url}`);
  process.exit(1);
}

const admin = createClient(url, secret, { auth: { persistSession: false, autoRefreshToken: false } });
const PASSWORD = "Password123!";

/** Throws on a Supabase error so the script stops at the first problem. */
function check(result, what) {
  if (result.error) {
    console.error(`✗ ${what}: ${result.error.message}`);
    process.exit(1);
  }
  return result.data;
}

const existing = check(await admin.from("businesses").select("id").eq("slug", "siam-cuts").maybeSingle(), "check existing");
if (existing) {
  console.log("Demo data already exists. Run `npm run db:reset` first to start over.");
  process.exit(0);
}

async function user(email, fullName) {
  const data = check(
    await admin.auth.admin.createUser({ email, password: PASSWORD, email_confirm: true, user_metadata: { full_name: fullName } }),
    `create user ${email}`,
  );
  return data.user.id;
}

const ownerId = await user("owner@bookflow.test", "Somchai Owner");
const managerId = await user("manager@bookflow.test", "Malee Manager");
const staff1Id = await user("staff1@bookflow.test", "Niran Stylist");
const staff2Id = await user("staff2@bookflow.test", "Ploy Therapist");
await user("customer@bookflow.test", "Chris Customer");

const business = check(
  await admin
    .from("businesses")
    .insert({
      owner_id: ownerId,
      name: "Siam Cuts & Spa",
      slug: "siam-cuts",
      description: "Haircuts, colouring and Thai massage in the heart of Bangkok.",
      address: "123 Sukhumvit Rd, Khlong Toei, Bangkok 10110",
      phone: "+66 2 123 4567",
      email: "hello@siamcuts.test",
      timezone: "Asia/Bangkok",
      currency: "THB",
    })
    .select("id")
    .single(),
  "create business",
);
const businessId = business.id;

check(
  await admin.from("business_members").insert([
    { business_id: businessId, user_id: managerId, role: "manager", status: "active", display_name: "Malee", joined_at: new Date().toISOString() },
    { business_id: businessId, user_id: staff1Id, role: "staff", status: "active", display_name: "Niran", bio: "Senior stylist, 8 years experience.", joined_at: new Date().toISOString() },
    { business_id: businessId, user_id: staff2Id, role: "staff", status: "active", display_name: "Ploy", bio: "Certified Thai massage therapist.", joined_at: new Date().toISOString() },
  ]),
  "add members",
);

const services = check(
  await admin
    .from("services")
    .insert([
      { business_id: businessId, name: "Men's haircut", duration_minutes: 30, price: 350, sort_order: 1, description: "Cut, wash and style." },
      { business_id: businessId, name: "Women's haircut", duration_minutes: 60, price: 650, sort_order: 2, description: "Consultation, cut and blow-dry." },
      { business_id: businessId, name: "Hair colouring", duration_minutes: 120, price: 1800, sort_order: 3 },
      { business_id: businessId, name: "Thai massage (60 min)", duration_minutes: 60, price: 500, sort_order: 4 },
      { business_id: businessId, name: "Thai massage (90 min)", duration_minutes: 90, price: 700, sort_order: 5 },
    ])
    .select("id, name"),
  "create services",
);
const serviceId = (name) => services.find((s) => s.name === name).id;

check(
  await admin.from("staff_services").insert([
    ...["Men's haircut", "Women's haircut", "Hair colouring"].map((n) => ({ business_id: businessId, staff_user_id: staff1Id, service_id: serviceId(n) })),
    ...["Thai massage (60 min)", "Thai massage (90 min)"].map((n) => ({ business_id: businessId, staff_user_id: staff2Id, service_id: serviceId(n) })),
    { business_id: businessId, staff_user_id: ownerId, service_id: serviceId("Men's haircut") },
  ]),
  "assign services",
);

// Mon–Sat, 10:00–13:00 and 14:00–19:00 (lunch break). weekday: 0 = Sunday.
const hours = [];
for (const staffId of [staff1Id, staff2Id, ownerId]) {
  for (let weekday = 1; weekday <= 6; weekday++) {
    hours.push({ business_id: businessId, staff_user_id: staffId, weekday, start_time: "10:00", end_time: "13:00" });
    hours.push({ business_id: businessId, staff_user_id: staffId, weekday, start_time: "14:00", end_time: "19:00" });
  }
}
check(await admin.from("staff_working_hours").insert(hours), "working hours");

console.log(`
✓ Demo data created. All passwords: ${PASSWORD}

  owner@bookflow.test     owner of "Siam Cuts & Spa" (also cuts hair)
  manager@bookflow.test   manager
  staff1@bookflow.test    stylist
  staff2@bookflow.test    massage therapist
  customer@bookflow.test  customer
`);
