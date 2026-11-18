-- ============================================================================
-- BookFlow · Migration 2 · Tables, constraints, indexes
-- ============================================================================
-- Conventions
--   * UUID primary keys (gen_random_uuid()).
--   * All instants are timestamptz (stored as UTC). Weekly schedules are local
--     wall-clock "time" values interpreted in businesses.timezone.
--   * Composite foreign keys (business_id, x) make it impossible for a row to
--     point at a service or staff member that belongs to a different business.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- profiles: one row per Supabase Auth user (created by trigger, migration 3)
-- ---------------------------------------------------------------------------
create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  email       text not null,
  full_name   text check (full_name is null or char_length(full_name) between 1 and 120),
  phone       text check (phone is null or phone ~ '^\+?[0-9 ()-]{6,20}$'),
  avatar_path text check (avatar_path is null or char_length(avatar_path) <= 300),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
comment on table public.profiles is 'Public-schema mirror of auth.users. Never readable by anonymous users.';

-- ---------------------------------------------------------------------------
-- businesses
-- ---------------------------------------------------------------------------
create table public.businesses (
  id                          uuid primary key default gen_random_uuid(),
  owner_id                    uuid not null references public.profiles (id) on delete restrict,
  name                        text not null check (char_length(name) between 2 and 120),
  slug                        text not null unique
                                check (char_length(slug) between 3 and 60
                                       and slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  description                 text check (description is null or char_length(description) <= 2000),
  address                     text check (address is null or char_length(address) <= 300),
  phone                       text check (phone is null or phone ~ '^\+?[0-9 ()-]{6,20}$'),
  email                       text check (email is null or email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  timezone                    text not null default 'Asia/Bangkok',
  currency                    char(3) not null default 'THB' check (currency ~ '^[A-Z]{3}$'),
  logo_path                   text check (logo_path is null or char_length(logo_path) <= 300),
  is_active                   boolean not null default true,
  -- Decision 2: customers cannot cancel/reschedule within this many minutes of the start.
  cancellation_cutoff_minutes integer not null default 120
                                check (cancellation_cutoff_minutes between 0 and 43200),  -- up to 30 days
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now()
);
create index businesses_owner_id_idx on public.businesses (owner_id);
create index businesses_active_name_idx on public.businesses (name) where is_active;

-- ---------------------------------------------------------------------------
-- business_members: per-business roles (owner / manager / staff)
-- ---------------------------------------------------------------------------
create table public.business_members (
  id           uuid primary key default gen_random_uuid(),
  business_id  uuid not null references public.businesses (id) on delete cascade,
  user_id      uuid not null references public.profiles (id) on delete cascade,
  role         public.member_role not null default 'staff',
  status       public.member_status not null default 'invited',
  -- Public-facing staff details (shown on booking pages instead of the private profile)
  display_name text not null check (char_length(display_name) between 1 and 120),
  bio          text check (bio is null or char_length(bio) <= 1000),
  avatar_path  text check (avatar_path is null or char_length(avatar_path) <= 300),
  invited_by   uuid references public.profiles (id) on delete set null,
  joined_at    timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint business_members_business_user_key unique (business_id, user_id)
);
-- Exactly one owner row per business.
create unique index business_members_one_owner_idx on public.business_members (business_id) where role = 'owner';
create index business_members_user_id_idx on public.business_members (user_id);

-- ---------------------------------------------------------------------------
-- services
-- ---------------------------------------------------------------------------
create table public.services (
  id               uuid primary key default gen_random_uuid(),
  business_id      uuid not null references public.businesses (id) on delete cascade,
  name             text not null check (char_length(name) between 2 and 120),
  description      text check (description is null or char_length(description) <= 2000),
  duration_minutes integer not null check (duration_minutes between 5 and 480 and duration_minutes % 5 = 0),
  price            numeric(10, 2) not null check (price >= 0),
  image_path       text check (image_path is null or char_length(image_path) <= 300),
  is_active        boolean not null default true,
  sort_order       integer not null default 0,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  -- Target for composite foreign keys from staff_services and bookings.
  constraint services_business_id_id_key unique (business_id, id)
);
create index services_business_active_idx on public.services (business_id, sort_order) where is_active;

-- ---------------------------------------------------------------------------
-- staff_services: which staff member offers which service
-- ---------------------------------------------------------------------------
create table public.staff_services (
  business_id   uuid not null,
  staff_user_id uuid not null,
  service_id    uuid not null,
  created_at    timestamptz not null default now(),
  primary key (staff_user_id, service_id),
  constraint staff_services_service_fkey foreign key (business_id, service_id)
    references public.services (business_id, id) on delete cascade,
  constraint staff_services_member_fkey foreign key (business_id, staff_user_id)
    references public.business_members (business_id, user_id) on delete cascade
);
create index staff_services_service_idx on public.staff_services (business_id, service_id);

-- ---------------------------------------------------------------------------
-- staff_working_hours: weekly recurring intervals in the business's local time
-- weekday follows PostgreSQL extract(dow): 0 = Sunday … 6 = Saturday
-- end_time may be '24:00' (midnight at the end of the day).
-- ---------------------------------------------------------------------------
create table public.staff_working_hours (
  id            uuid primary key default gen_random_uuid(),
  business_id   uuid not null,
  staff_user_id uuid not null,
  weekday       smallint not null check (weekday between 0 and 6),
  start_time    time not null,
  end_time      time not null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint staff_working_hours_order_chk check (end_time > start_time),
  constraint staff_working_hours_member_fkey foreign key (business_id, staff_user_id)
    references public.business_members (business_id, user_id) on delete cascade,
  -- Split shifts are allowed (09:00–12:00 and 13:00–18:00), overlaps are not.
  constraint staff_working_hours_no_overlap exclude using gist (
    business_id with =,
    staff_user_id with =,
    weekday with =,
    public.timerange(start_time, end_time, '[)') with &&
  )
);

-- ---------------------------------------------------------------------------
-- staff_time_off: holidays / leave. staff_user_id NULL = whole-business closure.
-- ---------------------------------------------------------------------------
create table public.staff_time_off (
  id            uuid primary key default gen_random_uuid(),
  business_id   uuid not null references public.businesses (id) on delete cascade,
  staff_user_id uuid,
  starts_at     timestamptz not null,
  ends_at       timestamptz not null,
  reason        text check (reason is null or char_length(reason) <= 300),
  created_by    uuid references public.profiles (id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint staff_time_off_order_chk check (ends_at > starts_at),
  -- MATCH SIMPLE: the FK is only checked when staff_user_id is not null.
  constraint staff_time_off_member_fkey foreign key (business_id, staff_user_id)
    references public.business_members (business_id, user_id) on delete cascade
);
create index staff_time_off_lookup_idx on public.staff_time_off using gist (business_id, staff_user_id, tstzrange(starts_at, ends_at, '[)'));

-- ---------------------------------------------------------------------------
-- bookings
-- Rows are never deleted: cancelled bookings keep their history and free the slot.
-- Clients cannot write this table directly; only the functions in migration 5 can.
-- ---------------------------------------------------------------------------
create table public.bookings (
  id                    uuid primary key default gen_random_uuid(),
  business_id           uuid not null references public.businesses (id) on delete restrict,
  service_id            uuid not null,
  staff_user_id         uuid not null,
  customer_user_id      uuid not null references public.profiles (id) on delete restrict,
  starts_at             timestamptz not null,
  ends_at               timestamptz not null,
  during                tstzrange generated always as (tstzrange(starts_at, ends_at, '[)')) stored,
  status                public.booking_status not null default 'confirmed',
  booking_reference     text not null unique check (booking_reference ~ '^BF-[A-HJ-NP-Z2-9]{6}$'),
  service_name_snapshot text not null,
  price_snapshot        numeric(10, 2) not null check (price_snapshot >= 0),
  currency_snapshot     char(3) not null,
  customer_note         text check (customer_note is null or char_length(customer_note) <= 500),
  cancelled_at          timestamptz,
  cancelled_by          uuid references public.profiles (id) on delete set null,
  cancellation_reason   text check (cancellation_reason is null or char_length(cancellation_reason) <= 500),
  reschedule_count      integer not null default 0,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  constraint bookings_order_chk check (ends_at > starts_at),
  constraint bookings_cancelled_chk check (status <> 'cancelled' or cancelled_at is not null),
  constraint bookings_service_fkey foreign key (business_id, service_id)
    references public.services (business_id, id) on delete restrict,
  constraint bookings_staff_fkey foreign key (business_id, staff_user_id)
    references public.business_members (business_id, user_id) on delete restrict,
  -- THE double-booking guard. Two occupying bookings for the same staff member
  -- can never overlap, even across businesses (a person can't be in two places).
  -- '[)' ranges: 10:00–10:30 and 10:30–11:00 do not overlap.
  -- Cancelled/completed/no-show rows are ignored, so cancelling frees the slot.
  constraint bookings_no_overlap exclude using gist (
    staff_user_id with =,
    during with &&
  ) where (status in ('pending', 'confirmed'))
);
create index bookings_business_starts_idx on public.bookings (business_id, starts_at);
create index bookings_customer_starts_idx on public.bookings (customer_user_id, starts_at desc);
create index bookings_staff_starts_idx on public.bookings (staff_user_id, starts_at);
create index bookings_service_idx on public.bookings (business_id, service_id);

-- ---------------------------------------------------------------------------
-- notification_logs: one row per email attempt (written by the server only)
-- ---------------------------------------------------------------------------
create table public.notification_logs (
  id                  uuid primary key default gen_random_uuid(),
  booking_id          uuid not null references public.bookings (id) on delete cascade,
  business_id         uuid not null references public.businesses (id) on delete cascade,
  type                public.notification_type not null,
  recipient_email     text not null,
  status              public.notification_status not null default 'queued',
  provider_message_id text,
  error_message       text,
  attempts            integer not null default 0 check (attempts >= 0),
  last_attempt_at     timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create index notification_logs_booking_idx on public.notification_logs (booking_id);
create index notification_logs_retry_idx on public.notification_logs (status, last_attempt_at) where status <> 'sent';

-- ---------------------------------------------------------------------------
-- updated_at triggers
-- ---------------------------------------------------------------------------
create trigger set_updated_at before update on public.profiles            for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.businesses          for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.business_members    for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.services            for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.staff_working_hours for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.staff_time_off      for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.bookings            for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.notification_logs   for each row execute function private.set_updated_at();
