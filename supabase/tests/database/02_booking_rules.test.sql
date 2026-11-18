-- ============================================================================
-- BookFlow database tests · Booking rules (create, cancel, reschedule, status)
-- Run: npm run db:test   (= supabase test db, uses pgTAP; everything is rolled back)
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
select plan(51);

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

-- Results of successful calls are kept here so later tests can refer to them.
create temp table t_booking (label text primary key, id uuid, staff uuid, ref text);
grant all on t_booking to authenticated;

-- ===========================================================================
-- 1. Happy path
-- ===========================================================================
select pg_temp.act_as('00000000-0000-4000-8000-000000000005');

select lives_ok($$
  insert into t_booking
  select 'b1', b.id, b.staff_user_id, b.booking_reference
  from public.create_booking('5e000000-0000-4000-8000-000000000001', pg_temp.next_monday('10:00'),
                             '00000000-0000-4000-8000-000000000003', '  First visit  ') b
$$, 'customer books Haircut with Sam at 10:00');

select results_eq($$
  select b.status::text, b.ends_at - b.starts_at, b.price_snapshot, b.currency_snapshot::text,
         b.service_name_snapshot, b.customer_user_id, b.customer_note
  from public.bookings b where b.id = (select id from t_booking where label = 'b1')
$$, $$ values ('confirmed', interval '60 minutes', 500.00::numeric(10,2), 'THB', 'Haircut',
               '00000000-0000-4000-8000-000000000005'::uuid, 'First visit') $$,
  'server derives status, end time, price, currency, customer and trims the note');

select matches((select ref from t_booking where label = 'b1'), '^BF-[A-HJ-NP-Z2-9]{6}$',
  'booking reference has the BF-XXXXXX format');

-- ===========================================================================
-- 2. Rules that reject a booking
-- ===========================================================================
select throws_ok($$ select public.create_booking('5e000000-0000-4000-8000-000000000001', pg_temp.next_monday('10:30'),
                    '00000000-0000-4000-8000-000000000003') $$,
  'BF009', null, 'overlapping booking for the same staff member is rejected');

select lives_ok($$ select public.create_booking('5e000000-0000-4000-8000-000000000001', pg_temp.next_monday('11:00'),
                   '00000000-0000-4000-8000-000000000003') $$,
  'back-to-back booking (11:00 right after 10:00–11:00) is allowed');

select throws_ok($$ select public.create_booking('5e000000-0000-4000-8000-000000000001', now() - interval '1 day',
                    '00000000-0000-4000-8000-000000000003') $$,
  'BF005', null, 'start in the past is rejected');

select throws_ok($$ select public.create_booking('5e000000-0000-4000-8000-000000000001', now() + interval '200 days',
                    '00000000-0000-4000-8000-000000000003') $$,
  'BF014', null, 'start more than 180 days ahead is rejected');

select throws_ok($$ select public.create_booking('5e000000-0000-4000-8000-000000000001', pg_temp.next_monday('13:15'),
                    '00000000-0000-4000-8000-000000000003') $$,
  'BF006', null, 'start off the 30-minute grid is rejected');

select throws_ok($$ select public.create_booking('5e000000-0000-4000-8000-000000000001', pg_temp.next_monday('08:00'),
                    '00000000-0000-4000-8000-000000000003') $$,
  'BF007', null, 'start before working hours is rejected');

select throws_ok($$ select public.create_booking('5e000000-0000-4000-8000-000000000001', pg_temp.next_monday('16:30'),
                    '00000000-0000-4000-8000-000000000003') $$,
  'BF007', null, 'booking that would end after working hours (16:30 + 60 min) is rejected');

select throws_ok($$ select public.create_booking('5e000000-0000-4000-8000-000000000001', pg_temp.next_monday('10:00') + interval '1 day',
                    '00000000-0000-4000-8000-000000000003') $$,
  'BF007', null, 'day with no working hours (Tuesday) is rejected');

select throws_ok($$ select public.create_booking('5e000000-0000-4000-8000-000000000002', pg_temp.next_monday('14:00'),
                    '00000000-0000-4000-8000-000000000004') $$,
  'BF004', null, 'staff member who does not offer the service is rejected');

select throws_ok($$ select public.create_booking('5e000000-0000-4000-8000-000000000003', pg_temp.next_monday('14:00'),
                    '00000000-0000-4000-8000-000000000003') $$,
  'BF002', null, 'inactive service is rejected');

select throws_ok($$ select public.create_booking('5e000000-0000-4000-8000-000000000001', pg_temp.next_monday('14:00'),
                    '00000000-0000-4000-8000-000000000003', repeat('x', 501)) $$,
  'BF015', null, 'note longer than 500 characters is rejected');

-- Time off and business closure (set up as the system).
select pg_temp.act_as_system();
insert into public.staff_time_off (business_id, staff_user_id, starts_at, ends_at, reason) values
  ('aaaaaaaa-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000003',
   pg_temp.next_monday('14:00'), pg_temp.next_monday('15:00'), 'Dentist');
select pg_temp.act_as('00000000-0000-4000-8000-000000000005');

select throws_ok($$ select public.create_booking('5e000000-0000-4000-8000-000000000001', pg_temp.next_monday('13:30'),
                    '00000000-0000-4000-8000-000000000003') $$,
  'BF008', null, 'booking overlapping staff time off is rejected');

-- Booking yourself (a staff member as their own customer) is not allowed.
select pg_temp.act_as('00000000-0000-4000-8000-000000000003');
select throws_ok($$ select public.create_booking('5e000000-0000-4000-8000-000000000001', pg_temp.next_monday('15:00'),
                    '00000000-0000-4000-8000-000000000003') $$,
  'BF004', null, 'staff cannot book an appointment with themselves');

-- Not logged in.
select pg_temp.act_as_anon();
select throws_ok($$ select public.create_booking('5e000000-0000-4000-8000-000000000001', pg_temp.next_monday('15:00'),
                    '00000000-0000-4000-8000-000000000003') $$,
  '42501', null, 'anonymous users cannot call create_booking');

-- Inactive business (deactivated as the system, re-activated afterwards).
select pg_temp.act_as_system();
update public.businesses set is_active = false where id = 'aaaaaaaa-0000-4000-8000-000000000001';
select pg_temp.act_as('00000000-0000-4000-8000-000000000005');
select throws_ok($$ select public.create_booking('5e000000-0000-4000-8000-000000000001', pg_temp.next_monday('15:00'),
                    '00000000-0000-4000-8000-000000000003') $$,
  'BF003', null, 'inactive business is rejected');
select pg_temp.act_as_system();
update public.businesses set is_active = true where id = 'aaaaaaaa-0000-4000-8000-000000000001';

-- ===========================================================================
-- 3. "Any available staff"
-- ===========================================================================
select pg_temp.act_as('00000000-0000-4000-8000-000000000006');

-- Sam has two bookings Monday, Tara none → Tara is chosen even though Sam is free at 12:00.
select lives_ok($$
  insert into t_booking
  select 'any1', b.id, b.staff_user_id, b.booking_reference
  from public.create_booking('5e000000-0000-4000-8000-000000000001', pg_temp.next_monday('12:00')) b
$$, 'any-staff booking succeeds');
select is((select staff from t_booking where label = 'any1'), '00000000-0000-4000-8000-000000000004'::uuid,
  'any-staff picks the eligible staff member with the fewest bookings that day');

-- 10:00: Sam is busy, Tara is free → Tara.
select is((select staff_user_id from public.create_booking('5e000000-0000-4000-8000-000000000001', pg_temp.next_monday('10:00'))),
  '00000000-0000-4000-8000-000000000004'::uuid, 'any-staff skips a busy staff member');

-- 10:00 again: both busy → conflict.
select throws_ok($$ select public.create_booking('5e000000-0000-4000-8000-000000000001', pg_temp.next_monday('10:00')) $$,
  'BF009', null, 'any-staff with nobody free returns slot_taken');

-- ===========================================================================
-- 4. Visibility of bookings
-- ===========================================================================
select is((select count(*)::int from public.bookings), 2, 'customer 2 sees only their own two bookings');

select pg_temp.act_as('00000000-0000-4000-8000-000000000004');
select is((select count(*)::int from public.bookings), 2, 'staff Tara sees only bookings assigned to her');

select pg_temp.act_as('00000000-0000-4000-8000-000000000002');
select is((select count(*)::int from public.bookings), 4, 'manager sees every booking of the business');

select pg_temp.act_as('00000000-0000-4000-8000-000000000007');
select is((select count(*)::int from public.bookings), 0, 'owner of another business sees none');

select pg_temp.act_as('00000000-0000-4000-8000-000000000003');
select is((select count(*)::int from public.profiles
           where id in ('00000000-0000-4000-8000-000000000005', '00000000-0000-4000-8000-000000000006')),
  1, 'staff Sam can read the profile of his own customer only');

-- ===========================================================================
-- 5. Cancel
-- ===========================================================================
select pg_temp.act_as('00000000-0000-4000-8000-000000000006');
select throws_ok($$ select public.cancel_booking((select id from t_booking where label = 'b1')) $$,
  'BF010', null, 'a customer cannot cancel someone else''s booking');
select throws_ok($$ update public.bookings set status = 'cancelled' where customer_user_id = auth.uid() $$,
  '42501', null, 'customers cannot update bookings directly');

select pg_temp.act_as('00000000-0000-4000-8000-000000000005');
select results_eq($$
  select status::text, cancelled_by, cancellation_reason
  from public.cancel_booking((select id from t_booking where label = 'b1'), 'Feeling unwell')
$$, $$ values ('cancelled', '00000000-0000-4000-8000-000000000005'::uuid, 'Feeling unwell') $$,
  'customer cancels own booking');
select throws_ok($$ select public.cancel_booking((select id from t_booking where label = 'b1')) $$,
  'BF013', null, 'cancelling twice is rejected');
select lives_ok($$ select public.create_booking('5e000000-0000-4000-8000-000000000001', pg_temp.next_monday('10:00'),
                   '00000000-0000-4000-8000-000000000003') $$,
  'cancelled booking released its slot (same slot can be booked again)');

-- Cutoff: set it to 8 days so every upcoming booking is inside it.
select pg_temp.act_as_system();
update public.businesses set cancellation_cutoff_minutes = 11520 where id = 'aaaaaaaa-0000-4000-8000-000000000001';
select pg_temp.act_as('00000000-0000-4000-8000-000000000006');
select throws_ok($$ select public.cancel_booking((select id from t_booking where label = 'any1')) $$,
  'BF012', null, 'customer cannot cancel inside the cutoff');
select throws_ok($$ select public.reschedule_booking((select id from t_booking where label = 'any1'), pg_temp.next_monday('15:00')) $$,
  'BF012', null, 'customer cannot reschedule inside the cutoff');

select pg_temp.act_as('00000000-0000-4000-8000-000000000002');
select lives_ok($$ select public.cancel_booking((select id from t_booking where label = 'any1'), 'Staff sick') $$,
  'manager can cancel inside the cutoff');
select pg_temp.act_as_system();
update public.businesses set cancellation_cutoff_minutes = 120 where id = 'aaaaaaaa-0000-4000-8000-000000000001';

-- ===========================================================================
-- 6. Reschedule (same validation path)
-- ===========================================================================
select pg_temp.act_as('00000000-0000-4000-8000-000000000005');
select lives_ok($$
  insert into t_booking
  select 'r1', b.id, b.staff_user_id, b.booking_reference
  from public.create_booking('5e000000-0000-4000-8000-000000000002', pg_temp.next_monday('15:00'),
                             '00000000-0000-4000-8000-000000000003') b
$$, 'customer books a 90-minute massage 15:00–16:30');

select results_eq($$
  select starts_at, ends_at, reschedule_count
  from public.reschedule_booking((select id from t_booking where label = 'r1'), pg_temp.next_monday('15:30'))
$$, $$ values (pg_temp.next_monday('15:30'), pg_temp.next_monday('17:00'), 1) $$,
  'rescheduling into a range that overlaps its own old time works and keeps the duration');

select throws_ok($$ select public.reschedule_booking((select id from t_booking where label = 'r1'), pg_temp.next_monday('11:00')) $$,
  'BF009', null, 'rescheduling onto another booking is rejected');
select throws_ok($$ select public.reschedule_booking((select id from t_booking where label = 'r1'), pg_temp.next_monday('16:00')) $$,
  'BF007', null, 'rescheduling past the end of working hours is rejected');
select throws_ok($$ select public.reschedule_booking((select id from t_booking where label = 'r1'), pg_temp.next_monday('15:30'),
                    '00000000-0000-4000-8000-000000000004') $$,
  'BF004', null, 'rescheduling to a staff member who does not offer the service is rejected');

select pg_temp.act_as('00000000-0000-4000-8000-000000000003');
select throws_ok($$ select public.reschedule_booking((select id from t_booking where label = 'r1'), pg_temp.next_monday('12:30'),
                    '00000000-0000-4000-8000-000000000004') $$,
  'BF011', null, 'staff cannot hand their booking to someone else');

-- ===========================================================================
-- 7. Status updates
-- ===========================================================================
select throws_ok($$ select public.update_booking_status((select id from t_booking where label = 'r1'), 'completed') $$,
  'BF013', null, 'a future booking cannot be marked completed');

select pg_temp.act_as('00000000-0000-4000-8000-000000000005');
select throws_ok($$ select public.update_booking_status((select id from t_booking where label = 'r1'), 'completed') $$,
  'BF011', null, 'customers cannot change booking status');

-- Simulate a past appointment (system writes directly; constraints still apply).
select pg_temp.act_as_system();
update public.bookings set starts_at = now() - interval '2 hours', ends_at = now() - interval '30 minutes'
where id = (select id from t_booking where label = 'r1');

select pg_temp.act_as('00000000-0000-4000-8000-000000000003');
select is((select status::text from public.update_booking_status((select id from t_booking where label = 'r1'), 'completed')),
  'completed', 'assigned staff marks a past appointment completed');
select is((select status::text from public.update_booking_status((select id from t_booking where label = 'r1'), 'no_show')),
  'no_show', 'completed can be corrected to no_show');
select throws_ok($$ select public.update_booking_status((select id from t_booking where label = 'r1'), 'cancelled') $$,
  'BF013', null, 'status update cannot cancel (cancel_booking must be used)');

-- ===========================================================================
-- 8. Time zones and the 30-minute grid (decision 1)
-- ===========================================================================
-- India is UTC+05:30: 10:00 local = 04:30 UTC, which is on the local grid.
select lives_ok($$ select private.assert_valid_start(
  ((now() at time zone 'Asia/Kolkata')::date + 3 + time '10:00') at time zone 'Asia/Kolkata', 'Asia/Kolkata') $$,
  'grid is checked in local time (Asia/Kolkata 10:00 = 04:30 UTC is valid)');
select throws_ok($$ select private.assert_valid_start(
  ((now() at time zone 'Asia/Kolkata')::date + 3 + time '10:15') at time zone 'Asia/Kolkata', 'Asia/Kolkata') $$,
  'BF006', null, 'Asia/Kolkata 10:15 is off the grid');

-- Daylight saving: London clocks go forward on 28 March 2027 (01:00 UTC).
-- Working hours Sunday 09:00–17:00 local are 08:00–16:00 UTC that day.
select pg_temp.act_as_system();
insert into public.businesses (id, owner_id, name, slug, timezone) values
  ('cccccccc-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000007', 'London Lane', 'london-lane', 'Europe/London');
insert into public.staff_working_hours (business_id, staff_user_id, weekday, start_time, end_time) values
  ('cccccccc-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000007', 0, '09:00', '17:00');

select is(private.slot_problem('cccccccc-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000007',
            '2027-03-28 08:00Z', '2027-03-28 09:00Z', 'Europe/London'),
  null, 'DST day: 09:00 BST (08:00 UTC) is inside working hours');
select is(private.slot_problem('cccccccc-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000007',
            '2027-03-28 16:00Z', '2027-03-28 17:00Z', 'Europe/London'),
  'outside_working_hours', 'DST day: 17:00 BST (16:00 UTC) is outside working hours');
select is(private.slot_problem('cccccccc-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000007',
            '2027-03-21 16:00Z', '2027-03-21 17:00Z', 'Europe/London'),
  null, 'week before DST: 16:00 GMT (16:00 UTC) is inside working hours');

select pg_temp.act_as_system();
select * from finish();
rollback;
