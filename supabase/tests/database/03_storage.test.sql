-- ============================================================================
-- BookFlow database tests · Storage buckets and upload policies
-- Run: npm run db:test   (= supabase test db, uses pgTAP; everything is rolled back)
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
select plan(15);

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

-- Size and MIME limits are enforced by the Storage API using the bucket
-- settings, so here we check the settings and the path-based policies.
select results_eq($$
  select id, public, file_size_limit, allowed_mime_types from storage.buckets
  where id in ('avatars', 'business-logos', 'service-images', 'staff-avatars') order by id
$$, $$ values
  ('avatars', true, 2097152::bigint, array['image/jpeg', 'image/png', 'image/webp']),
  ('business-logos', true, 2097152::bigint, array['image/jpeg', 'image/png', 'image/webp']),
  ('service-images', true, 2097152::bigint, array['image/jpeg', 'image/png', 'image/webp']),
  ('staff-avatars', true, 2097152::bigint, array['image/jpeg', 'image/png', 'image/webp'])
$$, 'four public image buckets with a 2 MB limit and image MIME types');

-- Owner of A
select pg_temp.act_as('00000000-0000-4000-8000-000000000001');
select lives_ok($$ insert into storage.objects (bucket_id, name)
                   values ('business-logos', 'aaaaaaaa-0000-4000-8000-000000000001/logo.png') $$,
  'owner can upload their business logo');
select throws_ok($$ insert into storage.objects (bucket_id, name)
                    values ('business-logos', 'bbbbbbbb-0000-4000-8000-000000000001/logo.png') $$,
  '42501', null, 'owner of A cannot upload a logo for business B');
select throws_ok($$ insert into storage.objects (bucket_id, name)
                    values ('business-logos', 'aaaaaaaa-0000-4000-8000-000000000001/nested/logo.png') $$,
  '42501', null, 'logo must sit directly in the business folder');
select lives_ok($$ insert into storage.objects (bucket_id, name)
                   values ('service-images', 'aaaaaaaa-0000-4000-8000-000000000001/5e000000-0000-4000-8000-000000000001/cut.webp') $$,
  'owner can upload an image for their own service');
select throws_ok($$ insert into storage.objects (bucket_id, name)
                    values ('service-images', 'aaaaaaaa-0000-4000-8000-000000000001/5e000000-0000-4000-8000-0000000000b1/x.webp') $$,
  '42501', null, 'cannot upload under a service that belongs to another business');

-- Manager of A
select pg_temp.act_as('00000000-0000-4000-8000-000000000002');
select lives_ok($$ insert into storage.objects (bucket_id, name)
                   values ('staff-avatars', 'aaaaaaaa-0000-4000-8000-000000000001/00000000-0000-4000-8000-000000000003/sam.jpg') $$,
  'manager can upload a staff photo');

-- Staff of A
select pg_temp.act_as('00000000-0000-4000-8000-000000000003');
select lives_ok($$ insert into storage.objects (bucket_id, name)
                   values ('staff-avatars', 'aaaaaaaa-0000-4000-8000-000000000001/00000000-0000-4000-8000-000000000003/me.jpg') $$,
  'staff can upload their own staff photo');
select throws_ok($$ insert into storage.objects (bucket_id, name)
                    values ('staff-avatars', 'aaaaaaaa-0000-4000-8000-000000000001/00000000-0000-4000-8000-000000000004/tara.jpg') $$,
  '42501', null, 'staff cannot upload a photo for a colleague');
select throws_ok($$ insert into storage.objects (bucket_id, name)
                    values ('business-logos', 'aaaaaaaa-0000-4000-8000-000000000001/logo2.png') $$,
  '42501', null, 'staff cannot change the business logo');

-- Customer
select pg_temp.act_as('00000000-0000-4000-8000-000000000005');
select lives_ok($$ insert into storage.objects (bucket_id, name)
                   values ('avatars', '00000000-0000-4000-8000-000000000005/me.png') $$,
  'user can upload their own avatar');
select throws_ok($$ insert into storage.objects (bucket_id, name)
                    values ('avatars', '00000000-0000-4000-8000-000000000006/me.png') $$,
  '42501', null, 'user cannot upload into another user''s avatar folder');
select throws_ok($$ insert into storage.objects (bucket_id, name)
                    values ('avatars', 'not-a-uuid/me.png') $$,
  '42501', null, 'malformed folder names are rejected (no cast error)');

-- Anonymous
select pg_temp.act_as_anon();
select throws_ok($$ insert into storage.objects (bucket_id, name)
                    values ('avatars', '00000000-0000-4000-8000-000000000005/x.png') $$,
  '42501', null, 'anonymous users cannot upload');
select is((select count(*)::int from storage.objects), 5, 'anyone can list objects in the public image buckets');

select pg_temp.act_as_system();
select * from finish();
rollback;
