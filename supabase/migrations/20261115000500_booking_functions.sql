-- ============================================================================
-- BookFlow · Migration 5 · Booking functions (the only way to write bookings)
-- ============================================================================
-- Every function runs in one transaction. The final guard against double
-- booking is the bookings_no_overlap exclusion constraint; the checks below
-- exist to give clear error messages before the constraint is reached.
--
-- Error codes (SQLSTATE) raised here — mapped to HTTP in src/lib/api/db-errors.ts
--   BF001 not_authenticated        401
--   BF002 service_unavailable      404  service missing or inactive
--   BF003 business_inactive        422
--   BF004 staff_not_eligible       422  staff not active / doesn't offer service
--   BF005 start_in_past            422
--   BF006 start_not_on_grid        422  must start on :00 or :30 local time
--   BF007 outside_working_hours    422
--   BF008 staff_unavailable        422  time off / business closure
--   BF009 slot_taken               409  overlaps another booking (also 23P01)
--   BF010 booking_not_found        404  missing, or not yours to see
--   BF011 forbidden                403
--   BF012 cutoff_passed            422  too close to the start for a customer
--   BF013 invalid_status           422  e.g. cancelling a cancelled booking
--   BF014 too_far_ahead            422  more than 180 days ahead
--   BF015 invalid_input            400
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Booking reference: "BF-" + 6 characters, no look-alikes (0/O, 1/I).
-- 32^6 ≈ 1.07 billion combinations; collisions are retried on insert.
-- ---------------------------------------------------------------------------
create function private.generate_booking_reference()
returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_bytes bytea := uuid_send(gen_random_uuid());  -- bytes 0–5 are fully random in UUIDv4
  v_ref text := 'BF-';
begin
  for i in 0..5 loop
    v_ref := v_ref || substr(v_alphabet, (get_byte(v_bytes, i) % 32) + 1, 1);
  end loop;
  return v_ref;
end;
$$;

-- ---------------------------------------------------------------------------
-- Time rules shared by create and reschedule
-- ---------------------------------------------------------------------------
create function private.assert_valid_start(p_starts_at timestamptz, p_timezone text)
returns void
language plpgsql
stable
set search_path = ''
as $$
declare
  v_local timestamp := p_starts_at at time zone p_timezone;
begin
  if p_starts_at is null then
    raise exception 'A start time is required.' using errcode = 'BF015';
  end if;
  if p_starts_at <= now() then
    raise exception 'This time is in the past.' using errcode = 'BF005';
  end if;
  if p_starts_at > now() + interval '180 days' then
    raise exception 'Bookings can be made up to 180 days ahead.' using errcode = 'BF014';
  end if;
  -- Decision 1: fixed 30-minute grid in the business's local time.
  if extract(epoch from (v_local - date_trunc('day', v_local))) % 1800 <> 0 then
    raise exception 'Appointments start on the hour or half hour.' using errcode = 'BF006';
  end if;
end;
$$;

-- True when the member is active at the business and offers the service.
create function private.staff_can_serve(p_business_id uuid, p_staff_user_id uuid, p_service_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1
    from public.staff_services ss
    join public.business_members m
      on m.business_id = ss.business_id and m.user_id = ss.staff_user_id
    where ss.business_id = p_business_id
      and ss.staff_user_id = p_staff_user_id
      and ss.service_id = p_service_id
      and m.status = 'active'
  );
$$;

-- Returns NULL when [p_starts_at, p_ends_at) is free for the staff member,
-- otherwise the first problem found. Shared with the availability engine (Phase 7).
create function private.slot_problem(
  p_business_id uuid,
  p_staff_user_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_timezone text,
  p_exclude_booking_id uuid default null
)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  v_local_start timestamp := p_starts_at at time zone p_timezone;
  v_local_end   timestamp := p_ends_at at time zone p_timezone;
  v_day         date      := v_local_start::date;
  v_range       tstzrange := tstzrange(p_starts_at, p_ends_at, '[)');
begin
  -- 1. Fully inside one working interval of that local day.
  --    (date + time = local timestamp; '24:00' means midnight at the end of the day.)
  if not exists (
    select 1
    from public.staff_working_hours wh
    where wh.business_id = p_business_id
      and wh.staff_user_id = p_staff_user_id
      and wh.weekday = extract(dow from v_local_start)::smallint
      and v_day + wh.start_time <= v_local_start
      and v_day + wh.end_time >= v_local_end
  ) then
    return 'outside_working_hours';
  end if;

  -- 2. Not during the staff member's leave or a business-wide closure.
  if exists (
    select 1
    from public.staff_time_off t
    where t.business_id = p_business_id
      and (t.staff_user_id = p_staff_user_id or t.staff_user_id is null)
      and tstzrange(t.starts_at, t.ends_at, '[)') && v_range
  ) then
    return 'staff_unavailable';
  end if;

  -- 3. No other occupying booking for this person (in any business).
  if exists (
    select 1
    from public.bookings b
    where b.staff_user_id = p_staff_user_id
      and b.status in ('pending', 'confirmed')
      and b.during && v_range
      and b.id is distinct from p_exclude_booking_id
  ) then
    return 'slot_taken';
  end if;

  return null;
end;
$$;

create function private.raise_slot_problem(p_problem text)
returns void
language plpgsql
set search_path = ''
as $$
begin
  case p_problem
    when 'outside_working_hours' then
      raise exception 'This time is outside the staff member''s working hours.' using errcode = 'BF007';
    when 'staff_unavailable' then
      raise exception 'The staff member is unavailable at this time.' using errcode = 'BF008';
    when 'slot_taken' then
      raise exception 'This time slot has just been booked. Please choose another time.' using errcode = 'BF009';
    else
      raise exception 'This time slot is not available.' using errcode = 'BF009';
  end case;
end;
$$;

-- Insert with booking-reference collision retry. Exclusion violations (23P01)
-- are NOT caught here; callers decide what to do with them.
create function private.insert_booking(
  p_business_id uuid, p_service_id uuid, p_staff_user_id uuid, p_customer_user_id uuid,
  p_starts_at timestamptz, p_ends_at timestamptz,
  p_service_name text, p_price numeric, p_currency text, p_note text
)
returns public.bookings
language plpgsql
set search_path = ''
as $$
declare
  v_row public.bookings;
  v_constraint text;
begin
  for attempt in 1..5 loop
    begin
      insert into public.bookings (
        business_id, service_id, staff_user_id, customer_user_id, starts_at, ends_at,
        status, booking_reference, service_name_snapshot, price_snapshot, currency_snapshot, customer_note
      ) values (
        p_business_id, p_service_id, p_staff_user_id, p_customer_user_id, p_starts_at, p_ends_at,
        'confirmed', private.generate_booking_reference(), p_service_name, p_price, p_currency, p_note
      )
      returning * into v_row;
      return v_row;
    exception when unique_violation then
      get stacked diagnostics v_constraint = constraint_name;
      if v_constraint <> 'bookings_booking_reference_key' or attempt = 5 then
        raise;
      end if;
    end;
  end loop;
  return null; -- unreachable
end;
$$;

-- How the current user relates to a booking: 'manager' (owner or manager of
-- the business), 'staff' (assigned staff member), 'customer', or NULL.
create function private.booking_actor(p_booking public.bookings)
returns text
language sql
stable
set search_path = ''
as $$
  select case
    when private.has_business_role(p_booking.business_id, array['owner', 'manager']::public.member_role[]) then 'manager'
    when p_booking.staff_user_id = (select auth.uid()) and private.has_business_role(p_booking.business_id) then 'staff'
    when p_booking.customer_user_id = (select auth.uid()) then 'customer'
    else null
  end;
$$;

create function private.clean_text(p_value text, p_max integer)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v text := nullif(btrim(p_value), '');
begin
  if v is not null and char_length(v) > p_max then
    raise exception 'Text is too long (maximum % characters).', p_max using errcode = 'BF015';
  end if;
  return v;
end;
$$;

-- ===========================================================================
-- create_booking
--   p_staff_user_id NULL = "any available staff" (decision 4): the eligible,
--   free staff member with the fewest bookings that day is chosen.
--   Price, end time, customer and reference are always derived here, never
--   taken from the browser.
-- ===========================================================================
create function public.create_booking(
  p_service_id uuid,
  p_starts_at timestamptz,
  p_staff_user_id uuid default null,
  p_customer_note text default null
)
returns public.bookings
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := auth.uid();
  v_service  public.services;
  v_business public.businesses;
  v_ends_at  timestamptz;
  v_note     text;
  v_problem  text;
  v_booking  public.bookings;
  v_candidate record;
begin
  if v_uid is null then
    raise exception 'Please log in to book an appointment.' using errcode = 'BF001';
  end if;

  select * into v_service from public.services where id = p_service_id;
  if not found or not v_service.is_active then
    raise exception 'This service is not available.' using errcode = 'BF002';
  end if;

  select * into v_business from public.businesses where id = v_service.business_id;
  if not v_business.is_active then
    raise exception 'This business is not accepting bookings.' using errcode = 'BF003';
  end if;

  v_note := private.clean_text(p_customer_note, 500);
  perform private.assert_valid_start(p_starts_at, v_business.timezone);
  v_ends_at := p_starts_at + make_interval(mins => v_service.duration_minutes);

  -- Specific staff member requested -------------------------------------------
  if p_staff_user_id is not null then
    if p_staff_user_id = v_uid
       or not private.staff_can_serve(v_business.id, p_staff_user_id, v_service.id) then
      raise exception 'This staff member does not offer this service.' using errcode = 'BF004';
    end if;

    v_problem := private.slot_problem(v_business.id, p_staff_user_id, p_starts_at, v_ends_at, v_business.timezone);
    if v_problem is not null then
      perform private.raise_slot_problem(v_problem);
    end if;

    begin
      v_booking := private.insert_booking(
        v_business.id, v_service.id, p_staff_user_id, v_uid, p_starts_at, v_ends_at,
        v_service.name, v_service.price, v_business.currency, v_note);
    exception when exclusion_violation then
      -- Lost a race with a concurrent booking.
      perform private.raise_slot_problem('slot_taken');
    end;
    return v_booking;
  end if;

  -- Any available staff -----------------------------------------------------
  for v_candidate in
    select m.user_id
    from public.staff_services ss
    join public.business_members m
      on m.business_id = ss.business_id and m.user_id = ss.staff_user_id
    where ss.business_id = v_business.id
      and ss.service_id = v_service.id
      and m.status = 'active'
      and m.user_id <> v_uid
    order by (
      select count(*)
      from public.bookings b
      where b.staff_user_id = m.user_id
        and b.status in ('pending', 'confirmed')
        and (b.starts_at at time zone v_business.timezone)::date
            = (p_starts_at at time zone v_business.timezone)::date
    ), m.created_at, m.user_id
  loop
    if private.slot_problem(v_business.id, v_candidate.user_id, p_starts_at, v_ends_at, v_business.timezone) is null then
      begin
        v_booking := private.insert_booking(
          v_business.id, v_service.id, v_candidate.user_id, v_uid, p_starts_at, v_ends_at,
          v_service.name, v_service.price, v_business.currency, v_note);
        return v_booking;
      exception when exclusion_violation then
        -- Someone else took this person just now; try the next one.
        null;
      end;
    end if;
  end loop;

  raise exception 'No staff member is available at this time. Please choose another time.' using errcode = 'BF009';
end;
$$;

-- ===========================================================================
-- reschedule_booking — same validation path as create_booking
--   Customers: cutoff applies, may choose another eligible staff member.
--   Assigned staff: may move their own booking, not hand it to someone else.
--   Owners/managers: no cutoff; may reassign staff.
--   p_new_staff_user_id NULL = keep the current staff member.
--   The original duration is kept even if the service duration changed since.
-- ===========================================================================
create function public.reschedule_booking(
  p_booking_id uuid,
  p_new_starts_at timestamptz,
  p_new_staff_user_id uuid default null
)
returns public.bookings
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := auth.uid();
  v_booking  public.bookings;
  v_business public.businesses;
  v_service  public.services;
  v_actor    text;
  v_staff    uuid;
  v_ends_at  timestamptz;
  v_problem  text;
begin
  if v_uid is null then
    raise exception 'Please log in.' using errcode = 'BF001';
  end if;

  select * into v_booking from public.bookings where id = p_booking_id for update;
  v_actor := case when found then private.booking_actor(v_booking) end;
  if v_actor is null then
    raise exception 'Booking not found.' using errcode = 'BF010';
  end if;

  if v_booking.status not in ('pending', 'confirmed') then
    raise exception 'Only upcoming, confirmed bookings can be rescheduled.' using errcode = 'BF013';
  end if;

  select * into v_business from public.businesses where id = v_booking.business_id;
  select * into v_service  from public.services   where id = v_booking.service_id;

  if not v_business.is_active then
    raise exception 'This business is not accepting bookings.' using errcode = 'BF003';
  end if;

  if v_actor = 'customer' then
    if not v_service.is_active then
      raise exception 'This service is no longer offered. Please contact the business.' using errcode = 'BF002';
    end if;
    if v_booking.starts_at - now() < make_interval(mins => v_business.cancellation_cutoff_minutes) then
      raise exception 'Bookings can no longer be changed this close to the start time.' using errcode = 'BF012';
    end if;
  end if;

  v_staff := coalesce(p_new_staff_user_id, v_booking.staff_user_id);
  if v_actor = 'staff' and v_staff <> v_booking.staff_user_id then
    raise exception 'Staff members cannot reassign bookings.' using errcode = 'BF011';
  end if;

  perform private.assert_valid_start(p_new_starts_at, v_business.timezone);

  if v_staff = v_booking.customer_user_id
     or not private.staff_can_serve(v_business.id, v_staff, v_booking.service_id) then
    raise exception 'This staff member does not offer this service.' using errcode = 'BF004';
  end if;

  v_ends_at := p_new_starts_at + (v_booking.ends_at - v_booking.starts_at);
  v_problem := private.slot_problem(v_business.id, v_staff, p_new_starts_at, v_ends_at,
                                    v_business.timezone, v_booking.id);
  if v_problem is not null then
    perform private.raise_slot_problem(v_problem);
  end if;

  begin
    update public.bookings
       set starts_at = p_new_starts_at,
           ends_at = v_ends_at,
           staff_user_id = v_staff,
           reschedule_count = reschedule_count + 1
     where id = v_booking.id
    returning * into v_booking;
  exception when exclusion_violation then
    perform private.raise_slot_problem('slot_taken');
  end;

  return v_booking;
end;
$$;

-- ===========================================================================
-- cancel_booking — frees the slot (status leaves the exclusion constraint)
-- ===========================================================================
create function public.cancel_booking(p_booking_id uuid, p_reason text default null)
returns public.bookings
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := auth.uid();
  v_booking  public.bookings;
  v_cutoff   integer;
  v_actor    text;
  v_reason   text;
begin
  if v_uid is null then
    raise exception 'Please log in.' using errcode = 'BF001';
  end if;

  select * into v_booking from public.bookings where id = p_booking_id for update;
  v_actor := case when found then private.booking_actor(v_booking) end;
  if v_actor is null then
    raise exception 'Booking not found.' using errcode = 'BF010';
  end if;

  if v_booking.status not in ('pending', 'confirmed') then
    raise exception 'This booking cannot be cancelled.' using errcode = 'BF013';
  end if;

  v_reason := private.clean_text(p_reason, 500);

  if v_actor = 'customer' then
    select cancellation_cutoff_minutes into v_cutoff from public.businesses where id = v_booking.business_id;
    if v_booking.starts_at - now() < make_interval(mins => v_cutoff) then
      raise exception 'Bookings can no longer be cancelled this close to the start time.' using errcode = 'BF012';
    end if;
  end if;

  update public.bookings
     set status = 'cancelled',
         cancelled_at = now(),
         cancelled_by = v_uid,
         cancellation_reason = v_reason
   where id = v_booking.id
  returning * into v_booking;

  return v_booking;
end;
$$;

-- ===========================================================================
-- update_booking_status — owners/managers and the assigned staff member
--   pending   → confirmed
--   confirmed → completed | no_show   (only once the appointment has started)
--   completed ↔ no_show, and either → confirmed (to undo a mistake)
--   Cancelling uses cancel_booking instead.
-- ===========================================================================
create function public.update_booking_status(p_booking_id uuid, p_status public.booking_status)
returns public.bookings
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_booking public.bookings;
  v_actor   text;
  v_allowed boolean;
begin
  if v_uid is null then
    raise exception 'Please log in.' using errcode = 'BF001';
  end if;

  select * into v_booking from public.bookings where id = p_booking_id for update;
  v_actor := case when found then private.booking_actor(v_booking) end;
  if v_actor is null then
    raise exception 'Booking not found.' using errcode = 'BF010';
  end if;
  if v_actor = 'customer' then
    raise exception 'Only the business can change a booking''s status.' using errcode = 'BF011';
  end if;

  v_allowed := case
    when v_booking.status = 'pending' and p_status = 'confirmed' then true
    when v_booking.status = 'confirmed' and p_status in ('completed', 'no_show') then v_booking.starts_at <= now()
    when v_booking.status in ('completed', 'no_show') and p_status in ('completed', 'no_show', 'confirmed')
      then p_status <> v_booking.status
    else false
  end;

  if not v_allowed then
    raise exception 'A booking cannot change from % to %.', v_booking.status, p_status using errcode = 'BF013';
  end if;

  begin
    update public.bookings set status = p_status where id = v_booking.id returning * into v_booking;
  exception when exclusion_violation then
    perform private.raise_slot_problem('slot_taken');
  end;

  return v_booking;
end;
$$;

-- ---------------------------------------------------------------------------
-- Privileges: logged-in users only. (Supabase grants EXECUTE to anon by default.)
-- ---------------------------------------------------------------------------
revoke execute on function public.create_booking(uuid, timestamptz, uuid, text) from public, anon;
revoke execute on function public.reschedule_booking(uuid, timestamptz, uuid) from public, anon;
revoke execute on function public.cancel_booking(uuid, text) from public, anon;
revoke execute on function public.update_booking_status(uuid, public.booking_status) from public, anon;

grant execute on function public.create_booking(uuid, timestamptz, uuid, text) to authenticated;
grant execute on function public.reschedule_booking(uuid, timestamptz, uuid) to authenticated;
grant execute on function public.cancel_booking(uuid, text) to authenticated;
grant execute on function public.update_booking_status(uuid, public.booking_status) to authenticated;
