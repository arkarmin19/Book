-- ============================================================================
-- BookFlow · Migration 4 · Row Level Security and table privileges
-- ============================================================================
-- Two layers:
--   1. GRANTs say which operations/columns a role may use at all.
--   2. RLS policies say which ROWS it may see or change.
-- Roles: anon (not logged in), authenticated (logged in), service_role
-- (server secret key, bypasses RLS — used only in src/lib/supabase/admin.ts).
--
-- (select auth.uid()) is wrapped in a sub-select so PostgreSQL evaluates it
-- once per query instead of once per row (Supabase performance guidance).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Helper functions (SECURITY DEFINER so they can read business_members without
-- triggering its own RLS policies, which would otherwise recurse).
-- ---------------------------------------------------------------------------
create function private.has_business_role(
  p_business_id uuid,
  p_roles public.member_role[] default array['owner', 'manager', 'staff']::public.member_role[]
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.business_members m
    where m.business_id = p_business_id
      and m.user_id = (select auth.uid())
      and m.status = 'active'
      and m.role = any (p_roles)
  );
$$;

create function private.is_business_active(p_business_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select b.is_active from public.businesses b where b.id = p_business_id), false);
$$;

-- Who may read a profile (name, email, phone) other than its owner:
--   * owners/managers: members of their business and customers who booked there
--   * staff: customers of bookings assigned to them
create function private.can_view_profile(p_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    p_profile_id = (select auth.uid())
    or exists (
      select 1
      from public.business_members viewer
      where viewer.user_id = (select auth.uid())
        and viewer.status = 'active'
        and viewer.role in ('owner', 'manager')
        and (
          exists (select 1 from public.business_members t
                  where t.business_id = viewer.business_id and t.user_id = p_profile_id)
          or exists (select 1 from public.bookings b
                     where b.business_id = viewer.business_id and b.customer_user_id = p_profile_id)
        )
    )
    or exists (
      select 1
      from public.bookings b
      join public.business_members viewer
        on viewer.business_id = b.business_id and viewer.user_id = b.staff_user_id
      where b.staff_user_id = (select auth.uid())
        and b.customer_user_id = p_profile_id
        and viewer.status = 'active'
    );
$$;

-- ---------------------------------------------------------------------------
-- Enable RLS everywhere
-- ---------------------------------------------------------------------------
alter table public.profiles            enable row level security;
alter table public.businesses          enable row level security;
alter table public.business_members    enable row level security;
alter table public.services            enable row level security;
alter table public.staff_services      enable row level security;
alter table public.staff_working_hours enable row level security;
alter table public.staff_time_off      enable row level security;
alter table public.bookings            enable row level security;
alter table public.notification_logs   enable row level security;

-- ---------------------------------------------------------------------------
-- Baseline privileges. Supabase grants ALL on new public tables to anon and
-- authenticated by default; tighten that first, then grant back what is needed.
-- TRUNCATE ignores RLS, so it is always revoked.
-- ---------------------------------------------------------------------------
revoke truncate, references, trigger on all tables in schema public from anon, authenticated;
revoke insert, update, delete on all tables in schema public from anon;

-- Anonymous visitors never see private data.
revoke select on public.profiles, public.staff_working_hours, public.staff_time_off,
                 public.bookings, public.notification_logs from anon;

-- ===========================================================================
-- profiles
-- ===========================================================================
revoke insert, update, delete on public.profiles from authenticated;
grant update (full_name, phone, avatar_path) on public.profiles to authenticated;

create policy "profiles: read own or related"
  on public.profiles for select to authenticated
  using (private.can_view_profile(id));

create policy "profiles: update own"
  on public.profiles for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- ===========================================================================
-- businesses (no DELETE: deactivate instead)
-- ===========================================================================
revoke delete, update on public.businesses from authenticated;
grant update (name, slug, description, address, phone, email, timezone, currency,
              logo_path, is_active, cancellation_cutoff_minutes)
  on public.businesses to authenticated;

create policy "businesses: public reads active"
  on public.businesses for select to anon, authenticated
  using (is_active);

create policy "businesses: members read own"
  on public.businesses for select to authenticated
  using (owner_id = (select auth.uid()) or private.has_business_role(id));

create policy "businesses: create as owner"
  on public.businesses for insert to authenticated
  with check (owner_id = (select auth.uid()));

create policy "businesses: owner/manager update"
  on public.businesses for update to authenticated
  using (private.has_business_role(id, array['owner', 'manager']::public.member_role[]))
  with check (private.has_business_role(id, array['owner', 'manager']::public.member_role[]));

-- ===========================================================================
-- business_members
-- ===========================================================================
create policy "members: public reads active staff of active businesses"
  on public.business_members for select to anon, authenticated
  using (status = 'active' and private.is_business_active(business_id));

create policy "members: members read own business; users read own rows"
  on public.business_members for select to authenticated
  using (user_id = (select auth.uid()) or private.has_business_role(business_id));

create policy "members: owner/manager add"
  on public.business_members for insert to authenticated
  with check (private.has_business_role(business_id, array['owner', 'manager']::public.member_role[]));

create policy "members: owner/manager or self update"
  on public.business_members for update to authenticated
  using (user_id = (select auth.uid())
         or private.has_business_role(business_id, array['owner', 'manager']::public.member_role[]))
  with check (user_id = (select auth.uid())
              or private.has_business_role(business_id, array['owner', 'manager']::public.member_role[]));

create policy "members: owner/manager remove"
  on public.business_members for delete to authenticated
  using (private.has_business_role(business_id, array['owner', 'manager']::public.member_role[]));

-- ===========================================================================
-- services
-- ===========================================================================
create policy "services: public reads active"
  on public.services for select to anon, authenticated
  using (is_active and private.is_business_active(business_id));

create policy "services: members read all"
  on public.services for select to authenticated
  using (private.has_business_role(business_id));

create policy "services: owner/manager insert"
  on public.services for insert to authenticated
  with check (private.has_business_role(business_id, array['owner', 'manager']::public.member_role[]));

create policy "services: owner/manager update"
  on public.services for update to authenticated
  using (private.has_business_role(business_id, array['owner', 'manager']::public.member_role[]))
  with check (private.has_business_role(business_id, array['owner', 'manager']::public.member_role[]));

create policy "services: owner/manager delete"
  on public.services for delete to authenticated
  using (private.has_business_role(business_id, array['owner', 'manager']::public.member_role[]));

-- ===========================================================================
-- staff_services (assign = insert, unassign = delete)
-- ===========================================================================
revoke update on public.staff_services from authenticated;

create policy "staff_services: public reads bookable"
  on public.staff_services for select to anon, authenticated
  using (
    private.is_business_active(business_id)
    and exists (select 1 from public.services s
                where s.id = service_id and s.business_id = staff_services.business_id and s.is_active)
    and exists (select 1 from public.business_members m
                where m.business_id = staff_services.business_id
                  and m.user_id = staff_user_id and m.status = 'active')
  );

create policy "staff_services: members read all"
  on public.staff_services for select to authenticated
  using (private.has_business_role(business_id));

create policy "staff_services: owner/manager assign"
  on public.staff_services for insert to authenticated
  with check (private.has_business_role(business_id, array['owner', 'manager']::public.member_role[]));

create policy "staff_services: owner/manager unassign"
  on public.staff_services for delete to authenticated
  using (private.has_business_role(business_id, array['owner', 'manager']::public.member_role[]));

-- ===========================================================================
-- staff_working_hours (members read; owner/manager write)
-- Customers never read schedules directly; the availability function does.
-- ===========================================================================
create policy "working_hours: members read"
  on public.staff_working_hours for select to authenticated
  using (private.has_business_role(business_id));

create policy "working_hours: owner/manager insert"
  on public.staff_working_hours for insert to authenticated
  with check (private.has_business_role(business_id, array['owner', 'manager']::public.member_role[]));

create policy "working_hours: owner/manager update"
  on public.staff_working_hours for update to authenticated
  using (private.has_business_role(business_id, array['owner', 'manager']::public.member_role[]))
  with check (private.has_business_role(business_id, array['owner', 'manager']::public.member_role[]));

create policy "working_hours: owner/manager delete"
  on public.staff_working_hours for delete to authenticated
  using (private.has_business_role(business_id, array['owner', 'manager']::public.member_role[]));

-- ===========================================================================
-- staff_time_off (members read; owner/manager write any; staff write own leave)
-- Business-wide closures (staff_user_id is null) are owner/manager only.
-- ===========================================================================
create policy "time_off: members read"
  on public.staff_time_off for select to authenticated
  using (private.has_business_role(business_id));

create policy "time_off: insert"
  on public.staff_time_off for insert to authenticated
  with check (
    private.has_business_role(business_id, array['owner', 'manager']::public.member_role[])
    or (staff_user_id = (select auth.uid()) and private.has_business_role(business_id))
  );

create policy "time_off: update"
  on public.staff_time_off for update to authenticated
  using (
    private.has_business_role(business_id, array['owner', 'manager']::public.member_role[])
    or (staff_user_id = (select auth.uid()) and private.has_business_role(business_id))
  )
  with check (
    private.has_business_role(business_id, array['owner', 'manager']::public.member_role[])
    or (staff_user_id = (select auth.uid()) and private.has_business_role(business_id))
  );

create policy "time_off: delete"
  on public.staff_time_off for delete to authenticated
  using (
    private.has_business_role(business_id, array['owner', 'manager']::public.member_role[])
    or (staff_user_id = (select auth.uid()) and private.has_business_role(business_id))
  );

-- ===========================================================================
-- bookings: READ ONLY for clients. All writes go through the functions in
-- migration 5 (create_booking, reschedule_booking, cancel_booking,
-- update_booking_status), which run every validation rule.
-- ===========================================================================
revoke insert, update, delete on public.bookings from authenticated;

create policy "bookings: customer reads own"
  on public.bookings for select to authenticated
  using (customer_user_id = (select auth.uid()));

create policy "bookings: assigned staff reads"
  on public.bookings for select to authenticated
  using (staff_user_id = (select auth.uid()) and private.has_business_role(business_id));

create policy "bookings: owner/manager reads business"
  on public.bookings for select to authenticated
  using (private.has_business_role(business_id, array['owner', 'manager']::public.member_role[]));

-- ===========================================================================
-- notification_logs: written by the server (secret key) only
-- ===========================================================================
revoke insert, update, delete on public.notification_logs from authenticated;

create policy "notification_logs: owner/manager read"
  on public.notification_logs for select to authenticated
  using (private.has_business_role(business_id, array['owner', 'manager']::public.member_role[]));
