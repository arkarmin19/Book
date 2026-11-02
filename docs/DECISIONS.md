# BookFlow – Design Decisions

Agreed during Phase 0 (2 Nov 2026).

| # | Topic | Decision |
|---|---|---|
| 1 | Slot grid | Fixed 30-minute grid in the business's local time. Start times must be on :00 or :30; enforced in the booking database functions. Service durations are free (e.g. 45 min). |
| 2 | Cancellation / reschedule cutoff | Per-business `cancellation_cutoff_minutes`, default 120, editable by the owner. Applies to customers for both cancel and reschedule. Owners, managers and the assigned staff member are not restricted. |
| 3 | Staff onboarding | Email invite via Supabase admin invite (server-only). If the email already belongs to a BookFlow user, link directly and notify. Membership is pending until first login. |
| 4 | "Any available staff" | In the MVP. Availability returns the union of eligible staff slots; `create_booking` assigns the eligible staff member with the fewest bookings that day, inside the transaction. 409 if none free. |
| 5 | Currency | One currency per business, default THB. |
| 6 | Starting point | Fresh repository. |
| 7 | Booking statuses | `confirmed`, `cancelled`, `completed`, `no_show` (`pending` reserved). Only `confirmed` occupies a slot. |
| 8 | Double-booking protection | `btree_gist` exclusion constraint on `(staff_user_id, tstzrange(starts_at, ends_at, '[)'))` where status = confirmed, plus transactional RPC functions. |
| 9 | Roles | Everyone is a customer; owner / manager / staff are per-business roles in `business_members`. |
| 10 | Next.js version | Next.js 16 — route guard file is `src/proxy.ts` (formerly `middleware.ts`). |
| 11 | Supabase keys | Publishable key in the browser; secret key server-only via `createAdminClient()`. Server auth checks use `getClaims()`, never `getSession()`. |
