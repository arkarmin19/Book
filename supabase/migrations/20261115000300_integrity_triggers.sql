-- ============================================================================
-- BookFlow · Migration 3 · Integrity triggers
-- ============================================================================
-- Rules here hold no matter how a row is written (API, dashboard, SQL editor
-- as a logged-in user). When auth.uid() is NULL the caller is the system
-- (migrations, seed scripts, server code using the secret key), which is trusted.
-- RLS (migration 4) decides WHO may write a table; these triggers decide WHAT
-- they may change.
-- Error codes: 42501 = insufficient_privilege (API → 403),
--              22023 = invalid_parameter_value (API → 400).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- New Supabase Auth user → profile row
-- ---------------------------------------------------------------------------
create function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email, full_name)
  values (
    new.id,
    coalesce(new.email, ''),
    nullif(btrim(coalesce(new.raw_user_meta_data ->> 'full_name', '')), '')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- Keep profiles.email in sync when a user changes their email address.
create function private.handle_user_email_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles set email = coalesce(new.email, '') where id = new.id;
  return new;
end;
$$;

create trigger on_auth_user_email_changed
  after update of email on auth.users
  for each row
  when (old.email is distinct from new.email)
  execute function private.handle_user_email_change();

-- ---------------------------------------------------------------------------
-- businesses
-- ---------------------------------------------------------------------------
create function private.businesses_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
begin
  if not private.is_valid_timezone(new.timezone) then
    raise exception 'Unknown timezone "%". Use an IANA name such as Asia/Bangkok.', new.timezone
      using errcode = '22023';
  end if;

  if v_actor is null then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.owner_id <> v_actor then
      raise exception 'You can only create a business that you own.' using errcode = '42501';
    end if;
    return new;
  end if;

  -- UPDATE
  if new.owner_id is distinct from old.owner_id then
    raise exception 'Ownership cannot be transferred here.' using errcode = '42501';
  end if;
  if new.is_active is distinct from old.is_active and old.owner_id <> v_actor then
    raise exception 'Only the owner can activate or deactivate the business.' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger businesses_before_write
  before insert or update on public.businesses
  for each row execute function private.businesses_before_write();

-- The creator automatically becomes the owner member.
create function private.businesses_after_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.business_members (business_id, user_id, role, status, display_name, joined_at)
  select new.id, p.id, 'owner', 'active',
         coalesce(p.full_name, split_part(p.email, '@', 1), 'Owner'),
         now()
  from public.profiles p
  where p.id = new.owner_id;
  return new;
end;
$$;

create trigger businesses_after_insert
  after insert on public.businesses
  for each row execute function private.businesses_after_insert();

-- ---------------------------------------------------------------------------
-- business_members
--   owner   : manage managers and staff; cannot demote/remove themselves
--   manager : manage staff only
--   staff   : edit own display details; accept own invite
-- ---------------------------------------------------------------------------
create function private.business_members_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor       uuid := auth.uid();
  v_actor_role  public.member_role;
  v_business_id uuid := case when tg_op = 'DELETE' then old.business_id else new.business_id end;
  v_owner_id    uuid;
begin
  if v_actor is null then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  select role into v_actor_role
  from public.business_members
  where business_id = v_business_id and user_id = v_actor and status = 'active';

  select owner_id into v_owner_id from public.businesses where id = v_business_id;

  if tg_op = 'INSERT' then
    if new.role = 'owner' then
      -- Only the automatic owner row created with a new business.
      if not (new.user_id = v_actor and v_owner_id = v_actor) then
        raise exception 'Owner membership is created automatically with the business.' using errcode = '42501';
      end if;
    elsif new.role = 'manager' and v_actor_role is distinct from 'owner' then
      raise exception 'Only the owner can add managers.' using errcode = '42501';
    elsif new.role = 'staff' and (v_actor_role is null or v_actor_role = 'staff') then
      raise exception 'Only owners and managers can add staff.' using errcode = '42501';
    end if;
    return new;
  end if;

  if tg_op = 'DELETE' then
    -- v_owner_id is null when the whole business is being deleted (cascade).
    if old.role = 'owner' and v_owner_id is not null then
      raise exception 'The owner cannot be removed from the business.' using errcode = '42501';
    elsif old.role = 'manager' and v_actor_role is distinct from 'owner' then
      raise exception 'Only the owner can remove managers.' using errcode = '42501';
    elsif v_actor_role is null or v_actor_role = 'staff' then
      raise exception 'Only owners and managers can remove members.' using errcode = '42501';
    end if;
    return old;
  end if;

  -- UPDATE ------------------------------------------------------------------
  if new.business_id <> old.business_id or new.user_id <> old.user_id then
    raise exception 'business_id and user_id cannot be changed.' using errcode = '42501';
  end if;

  -- Is anything besides the public display fields changing?
  if (new.role, new.status, new.invited_by, new.joined_at)
     is not distinct from (old.role, old.status, old.invited_by, old.joined_at) then
    -- Display-only change: the member themself, the owner, or a manager (for staff rows).
    if old.user_id = v_actor
       or v_actor_role = 'owner'
       or (v_actor_role = 'manager' and old.role = 'staff') then
      return new;
    end if;
    raise exception 'You cannot edit this member.' using errcode = '42501';
  end if;

  -- Accepting your own invite: invited -> active, nothing else.
  if old.user_id = v_actor and old.status = 'invited' and new.status = 'active'
     and new.role = old.role and new.invited_by is not distinct from old.invited_by then
    new.joined_at := coalesce(new.joined_at, now());
    return new;
  end if;

  if old.role = 'owner' then
    raise exception 'The owner''s role and status cannot be changed.' using errcode = '42501';
  end if;
  if new.role = 'owner' then
    raise exception 'Ownership cannot be transferred here.' using errcode = '42501';
  end if;
  if v_actor_role = 'owner' then
    return new;
  end if;
  if v_actor_role = 'manager' and old.role = 'staff' and new.role = 'staff' then
    return new;
  end if;
  raise exception 'You cannot change this member''s role or status.' using errcode = '42501';
end;
$$;

create trigger business_members_guard
  before insert or update or delete on public.business_members
  for each row execute function private.business_members_guard();
