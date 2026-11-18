-- ============================================================================
-- BookFlow · Migration 6 · Storage buckets and policies
-- ============================================================================
-- All four buckets are PUBLIC for reading (images are shown on public pages via
-- their public URL), but writing is restricted by path:
--
--   business-logos   {business_id}/{file}              owner / manager
--   service-images   {business_id}/{service_id}/{file} owner / manager
--   staff-avatars    {business_id}/{user_id}/{file}    owner / manager, or that staff member
--   avatars          {user_id}/{file}                  the user themself
--
-- The bucket settings enforce the size (2 MB) and image MIME types on the
-- server, so a modified client cannot upload a 50 MB file or a script.
-- ============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('business-logos', 'business-logos', true, 2097152, array['image/jpeg', 'image/png', 'image/webp']),
  ('service-images', 'service-images', true, 2097152, array['image/jpeg', 'image/png', 'image/webp']),
  ('staff-avatars',  'staff-avatars',  true, 2097152, array['image/jpeg', 'image/png', 'image/webp']),
  ('avatars',        'avatars',        true, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Can the current user write this object path?
create function private.can_write_storage_object(p_bucket_id text, p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_folders text[] := storage.foldername(p_name);
  v_first   uuid := private.try_uuid(v_folders[1]);
  v_second  uuid := private.try_uuid(v_folders[2]);
begin
  if v_uid is null or v_first is null then
    return false;
  end if;

  case p_bucket_id
    when 'avatars' then
      return v_first = v_uid and coalesce(array_length(v_folders, 1), 0) = 1;

    when 'business-logos' then
      return coalesce(array_length(v_folders, 1), 0) = 1
         and private.has_business_role(v_first, array['owner', 'manager']::public.member_role[]);

    when 'service-images' then
      return coalesce(array_length(v_folders, 1), 0) = 2
         and v_second is not null
         and private.has_business_role(v_first, array['owner', 'manager']::public.member_role[])
         and exists (select 1 from public.services s where s.id = v_second and s.business_id = v_first);

    when 'staff-avatars' then
      return coalesce(array_length(v_folders, 1), 0) = 2
         and v_second is not null
         and exists (select 1 from public.business_members m
                     where m.business_id = v_first and m.user_id = v_second)
         and (private.has_business_role(v_first, array['owner', 'manager']::public.member_role[])
              or (v_second = v_uid and private.has_business_role(v_first)));

    else
      return false;
  end case;
end;
$$;

create policy "bookflow images: public read"
  on storage.objects for select to anon, authenticated
  using (bucket_id in ('business-logos', 'service-images', 'staff-avatars', 'avatars'));

create policy "bookflow images: upload"
  on storage.objects for insert to authenticated
  with check (
    bucket_id in ('business-logos', 'service-images', 'staff-avatars', 'avatars')
    and private.can_write_storage_object(bucket_id, name)
  );

create policy "bookflow images: replace"
  on storage.objects for update to authenticated
  using (
    bucket_id in ('business-logos', 'service-images', 'staff-avatars', 'avatars')
    and private.can_write_storage_object(bucket_id, name)
  )
  with check (
    bucket_id in ('business-logos', 'service-images', 'staff-avatars', 'avatars')
    and private.can_write_storage_object(bucket_id, name)
  );

create policy "bookflow images: delete"
  on storage.objects for delete to authenticated
  using (
    bucket_id in ('business-logos', 'service-images', 'staff-avatars', 'avatars')
    and private.can_write_storage_object(bucket_id, name)
  );
