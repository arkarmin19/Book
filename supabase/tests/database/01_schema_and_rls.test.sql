-- ============================================================================
-- BookFlow database tests · Schema, triggers and Row Level Security
-- Run: npm run db:test   (= supabase test db, uses pgTAP; everything is rolled back)
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
select plan(40);

-- ---------------------------------------------------------------------------
-- Fixtures (identical in every test file; everything is rolled back at the end)
--   Business A "Siam Cuts" (Asia/Bangkok): owner …01, manager …02, staff …03, …04
--   Business B "Other Spa": owner …07
--   Customers: …05, …06
--   Services A: Haircut 60 min (staff 03 + 04), Massage 90 min (staff 03), Old service (inactive)
--   Working hours: staff 03 and 04, Mondays 09:00–17:00 Bangkok time
-- ---------------------------------------------------------------------------
create function pg_temp.act_as(p_user uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  set local role authenticated;
end $$;

create function pg_temp.act_as_anon() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  set local role anon;
end $$;

create function pg_temp.act_as_system() returns void language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claims', '', true);
end $$;

-- Next Monday at the given Bangkok wall-clock time (always 1–7 days ahead).
create function pg_temp.next_monday(p_time text) returns timestamptz language sql stable as $$
  select ((date_trunc('week', now() at time zone 'Asia/Bangkok') + interval '7 days')::date + p_time::time)
         at time zone 'Asia/Bangkok';
$$;

grant execute on all functions in schema pg_temp to anon, authenticated;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-4000-8000-000000000001', 'owner.a@test.local',    '{"full_name":"Olivia Owner"}'),
  ('00000000-0000-4000-8000-000000000002', 'manager.a@test.local',  '{"full_name":"Max Manager"}'),
  ('00000000-0000-4000-8000-000000000003', 'staff.a1@test.local',   '{"full_name":"Sam Staff"}'),
  ('00000000-0000-4000-8000-000000000004', 'staff.a2@test.local',   '{"full_name":"Tara Staff"}'),
  ('00000000-0000-4000-8000-000000000005', 'customer1@test.local',  '{"full_name":"Chris Customer"}'),
  ('00000000-0000-4000-8000-000000000006', 'customer2@test.local',  '{"full_name":"Dana Customer"}'),
  ('00000000-0000-4000-8000-000000000007', 'owner.b@test.local',    '{"full_name":"Ben Owner"}');

insert into public.businesses (id, owner_id, name, slug, timezone) values
  ('aaaaaaaa-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000001', 'Siam Cuts', 'siam-cuts', 'Asia/Bangkok'),
  ('bbbbbbbb-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000007', 'Other Spa', 'other-spa', 'Asia/Bangkok');

insert into public.business_members (business_id, user_id, role, status, display_name) values
  ('aaaaaaaa-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000002', 'manager', 'active', 'Max'),
  ('aaaaaaaa-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000003', 'staff',   'active', 'Sam'),
  ('aaaaaaaa-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000004', 'staff',   'active', 'Tara');

insert into public.services (id, business_id, name, duration_minutes, price, is_active) values
  ('5e000000-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001', 'Haircut', 60, 500.00, true),
  ('5e000000-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000001', 'Massage', 90, 1200.00, true),
  ('5e000000-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000001', 'Old service', 30, 100.00, false),
  ('5e000000-0000-4000-8000-0000000000b1', 'bbbbbbbb-0000-4000-8000-000000000001', 'Facial', 60, 900.00, true);

insert into public.staff_services (business_id, staff_user_id, service_id) values
  ('aaaaaaaa-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000003', '5e000000-0000-4000-8000-000000000001'),
  ('aaaaaaaa-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000004', '5e000000-0000-4000-8000-000000000001'),
  ('aaaaaaaa-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000003', '5e000000-0000-4000-8000-000000000002'),
  ('aaaaaaaa-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000003', '5e000000-0000-4000-8000-000000000003');

insert into public.staff_working_hours (business_id, staff_user_id, weekday, start_time, end_time) values
  ('aaaaaaaa-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000003', 1, '09:00', '17:00'),
  ('aaaaaaaa-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000004', 1, '09:00', '17:00');
-- ---------------------------------------------------------------------------

-- ===========================================================================
-- 1. Schema essentials
-- ===========================================================================
select tables_are('public', array[
  'profiles', 'businesses', 'business_members', 'services', 'staff_services',
  'staff_working_hours', 'staff_time_off', 'bookings', 'notification_logs'
], 'public schema has exactly the nine BookFlow tables');

select is(
  (select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity),
  0, 'RLS is enabled on every public table');

select col_type_is('public', 'bookings', 'starts_at', 'timestamp with time zone', 'bookings.starts_at is timestamptz');
select has_index('public', 'bookings', 'bookings_no_overlap', 'exclusion constraint index exists');

-- ===========================================================================
-- 2. Triggers: profiles, owner membership, timezone
-- ===========================================================================
select is((select full_name from public.profiles where id = '00000000-0000-4000-8000-000000000001'),
          'Olivia Owner', 'new auth user gets a profile with full_name');

select results_eq(
  $$ select role::text, status::text from public.business_members
     where business_id = 'aaaaaaaa-0000-4000-8000-000000000001' and user_id = '00000000-0000-4000-8000-000000000001' $$,
  $$ values ('owner', 'active') $$,
  'creating a business makes the creator an active owner member');

select throws_ok(
  $$ insert into public.businesses (owner_id, name, slug, timezone)
     values ('00000000-0000-4000-8000-000000000001', 'Bad TZ', 'bad-tz', 'Mars/Olympus') $$,
  '22023', null, 'unknown timezone is rejected');

select throws_ok(
  $$ insert into public.staff_working_hours (business_id, staff_user_id, weekday, start_time, end_time)
     values ('aaaaaaaa-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000003', 1, '16:00', '18:00') $$,
  '23P01', null, 'overlapping working-hour intervals are rejected');

select lives_ok(
  $$ insert into public.staff_working_hours (business_id, staff_user_id, weekday, start_time, end_time)
     values ('aaaaaaaa-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000003', 1, '17:00', '24:00') $$,
  'adjacent interval ending at 24:00 is allowed');

select throws_ok(
  $$ insert into public.staff_services (business_id, staff_user_id, service_id)
     values ('aaaaaaaa-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000003', '5e000000-0000-4000-8000-0000000000b1') $$,
  '23503', null, 'composite FK: cannot assign another business''s service');

-- ===========================================================================
-- 3. Anonymous visitors
-- ===========================================================================
update public.businesses set is_active = false where id = 'bbbbbbbb-0000-4000-8000-000000000001';
select pg_temp.act_as_anon();

select results_eq($$ select slug from public.businesses order by slug $$, $$ values ('siam-cuts') $$,
  'anon sees active businesses only');
select results_eq($$ select name from public.services order by name $$, $$ values ('Haircut'), ('Massage') $$,
  'anon sees active services of active businesses only');
select is((select count(*)::int from public.business_members), 4, 'anon sees active members of active businesses');
select throws_ok($$ select * from public.profiles $$, '42501', null, 'anon cannot read profiles at all');
select throws_ok($$ select * from public.bookings $$, '42501', null, 'anon cannot read bookings at all');
select throws_ok(
  $$ insert into public.businesses (owner_id, name, slug) values ('00000000-0000-4000-8000-000000000001', 'X', 'xx-x') $$,
  '42501', null, 'anon cannot create businesses');

-- ===========================================================================
-- 4. Customers
-- ===========================================================================
select pg_temp.act_as('00000000-0000-4000-8000-000000000005');

select results_eq($$ select id from public.profiles $$, $$ values ('00000000-0000-4000-8000-000000000005'::uuid) $$,
  'a customer sees only their own profile');
select lives_ok($$ update public.profiles set full_name = 'Chris C.' where id = auth.uid() $$, 'customer can edit own name');
select throws_ok($$ update public.profiles set email = 'x@y.z' where id = auth.uid() $$,
  '42501', null, 'customer cannot change profile email column');
select is_empty($$ select 1 from public.staff_working_hours $$, 'customer cannot read staff schedules');
select throws_ok(
  $$ insert into public.bookings (business_id, service_id, staff_user_id, customer_user_id, starts_at, ends_at,
       booking_reference, service_name_snapshot, price_snapshot, currency_snapshot)
     values ('aaaaaaaa-0000-4000-8000-000000000001', '5e000000-0000-4000-8000-000000000001',
             '00000000-0000-4000-8000-000000000003', auth.uid(), now() + interval '1 day',
             now() + interval '1 day 1 hour', 'BF-AAAAAA', 'Haircut', 0, 'THB') $$,
  '42501', null, 'customer cannot insert bookings directly (price could be faked)');
select is_empty(
  $$ update public.services set price = 1 where business_id = 'aaaaaaaa-0000-4000-8000-000000000001' returning id $$,
  'customer cannot update services');

-- ===========================================================================
-- 5. Staff
-- ===========================================================================
select pg_temp.act_as('00000000-0000-4000-8000-000000000003');

select is((select count(*)::int from public.staff_working_hours), 3, 'staff can read their business schedules');
select throws_ok(
  $$ insert into public.services (business_id, name, duration_minutes, price)
     values ('aaaaaaaa-0000-4000-8000-000000000001', 'Sneaky', 30, 1) $$,
  '42501', null, 'staff cannot create services');
select lives_ok(
  $$ insert into public.staff_time_off (business_id, staff_user_id, starts_at, ends_at, reason)
     values ('aaaaaaaa-0000-4000-8000-000000000001', auth.uid(), now() + interval '30 days', now() + interval '31 days', 'Holiday') $$,
  'staff can add their own time off');
select throws_ok(
  $$ insert into public.staff_time_off (business_id, staff_user_id, starts_at, ends_at)
     values ('aaaaaaaa-0000-4000-8000-000000000001', null, now() + interval '30 days', now() + interval '31 days') $$,
  '42501', null, 'staff cannot create a business-wide closure');
select throws_ok(
  $$ update public.business_members set role = 'manager' where user_id = auth.uid() $$,
  '42501', null, 'staff cannot promote themselves');
select lives_ok(
  $$ update public.business_members set bio = 'Senior stylist' where user_id = auth.uid() $$,
  'staff can edit their own public bio');

-- ===========================================================================
-- 6. Managers
-- ===========================================================================
select pg_temp.act_as('00000000-0000-4000-8000-000000000002');

select lives_ok(
  $$ insert into public.services (business_id, name, duration_minutes, price)
     values ('aaaaaaaa-0000-4000-8000-000000000001', 'Beard trim', 30, 250) $$,
  'manager can create services');
select throws_ok(
  $$ update public.businesses set is_active = false where id = 'aaaaaaaa-0000-4000-8000-000000000001' $$,
  '42501', null, 'manager cannot deactivate the business');
select throws_ok(
  $$ insert into public.business_members (business_id, user_id, role, display_name)
     values ('aaaaaaaa-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000006', 'manager', 'New manager') $$,
  '42501', null, 'manager cannot add another manager');
select lives_ok(
  $$ insert into public.business_members (business_id, user_id, role, display_name)
     values ('aaaaaaaa-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000006', 'staff', 'New staff') $$,
  'manager can add staff (status defaults to invited)');
select is_empty(
  $$ update public.services set price = 1 where business_id = 'bbbbbbbb-0000-4000-8000-000000000001' returning id $$,
  'manager of A cannot touch services of business B');

-- ===========================================================================
-- 7. Owners
-- ===========================================================================
select pg_temp.act_as('00000000-0000-4000-8000-000000000001');

select throws_ok(
  $$ update public.business_members set role = 'staff'
     where business_id = 'aaaaaaaa-0000-4000-8000-000000000001' and user_id = auth.uid() $$,
  '42501', null, 'owner cannot demote themselves (business would have no owner)');
select throws_ok(
  $$ update public.businesses set owner_id = '00000000-0000-4000-8000-000000000002'
     where id = 'aaaaaaaa-0000-4000-8000-000000000001' $$,
  '42501', null, 'owner_id cannot be changed by an update');
select lives_ok(
  $$ update public.businesses set cancellation_cutoff_minutes = 240 where id = 'aaaaaaaa-0000-4000-8000-000000000001' $$,
  'owner can change the cancellation cutoff');
select lives_ok(
  $$ update public.business_members set role = 'manager'
     where business_id = 'aaaaaaaa-0000-4000-8000-000000000001' and user_id = '00000000-0000-4000-8000-000000000004' $$,
  'owner can promote staff to manager');
select is_empty(
  $$ select 1 from public.business_members where business_id = 'bbbbbbbb-0000-4000-8000-000000000001' $$,
  'owner of A cannot see members of inactive business B');

-- ===========================================================================
-- 8. A user creating their own business
-- ===========================================================================
select pg_temp.act_as('00000000-0000-4000-8000-000000000005');
select lives_ok(
  $$ insert into public.businesses (owner_id, name, slug) values (auth.uid(), 'Chris Nails', 'chris-nails') $$,
  'any logged-in user can register a business as its owner');
select throws_ok(
  $$ insert into public.businesses (owner_id, name, slug)
     values ('00000000-0000-4000-8000-000000000006', 'Fake', 'fake-biz') $$,
  '42501', null, 'cannot register a business in someone else''s name');

select pg_temp.act_as_system();
select * from finish();
rollback;
