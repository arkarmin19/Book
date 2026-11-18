-- ============================================================================
-- BookFlow · Migration 1 · Extensions, schemas, enum types, shared helpers
-- ============================================================================

-- btree_gist lets an exclusion constraint combine "=" on uuid/int columns with
-- "&&" (overlaps) on range columns. It is the core of double-booking protection.
create extension if not exists btree_gist with schema extensions;

-- Internal helper functions live in "private". This schema is NOT exposed by the
-- Supabase Data API (only "public" and "graphql_public" are), so these helpers
-- cannot be called over HTTP. RLS policies may still call them.
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Enum types
-- ---------------------------------------------------------------------------
create type public.member_role as enum ('owner', 'manager', 'staff');

-- invited:  added by an owner/manager, has not logged in yet (not bookable)
-- active:   works at the business
-- inactive: removed from the business; row kept so booking history stays valid
create type public.member_status as enum ('invited', 'active', 'inactive');

-- Only 'pending' and 'confirmed' occupy a time slot (see bookings_no_overlap).
-- 'pending' is reserved for a future approval flow; the MVP confirms immediately.
create type public.booking_status as enum ('pending', 'confirmed', 'cancelled', 'completed', 'no_show');

create type public.notification_type as enum ('booking_created', 'booking_cancelled', 'booking_rescheduled');
create type public.notification_status as enum ('queued', 'sent', 'failed');

-- Range of local wall-clock times, used to stop overlapping working-hour intervals.
create type public.timerange as range (subtype = time);

-- ---------------------------------------------------------------------------
-- Shared trigger: keep updated_at current
-- ---------------------------------------------------------------------------
create function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Shared helpers
-- ---------------------------------------------------------------------------

-- True when the text is a timezone name PostgreSQL knows (IANA names such as
-- 'Asia/Bangkok'). Used by a trigger on businesses.
create function private.is_valid_timezone(p_tz text)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (select 1 from pg_catalog.pg_timezone_names where name = p_tz);
$$;

-- Casts text to uuid, returning null instead of raising on bad input.
-- Used by Storage policies, where the folder name comes from the uploader.
create function private.try_uuid(p_value text)
returns uuid
language plpgsql
immutable
set search_path = ''
as $$
begin
  return p_value::uuid;
exception when invalid_text_representation then
  return null;
end;
$$;

grant execute on all functions in schema private to anon, authenticated, service_role;
