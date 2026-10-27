-- GĐ 2: own profile and avatar (AUTH-08, techstack §4.5).
--
-- Avatar flow: the Worker reserves a new path for the caller, hands the browser
-- a signed upload URL for exactly that path, then downloads and checks the real
-- file before set_my_avatar() switches avatar_path with version check and audit.
-- A reserved path can be committed once; after it is replaced it can never be
-- referenced again, so deleting the old file after commit is safe.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', false, 5000000, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- No storage.objects policy is created for `avatars`: clients never read or
-- write the bucket with their own JWT. Upload uses a signed upload URL for one
-- reserved path; display goes through the Worker after a permission check.

create table app.avatar_uploads (
  path text primary key,
  account_id uuid not null references app.account_profiles (id),
  created_at timestamptz not null default now(),
  -- Set by the Worker (service role) after it checked the stored file itself.
  verified_at timestamptz,
  committed_at timestamptz,
  discarded_at timestamptz,
  constraint avatar_uploads_path_check check (
    split_part(path, '/', 1) = account_id::text
    and path ~ '^[0-9a-f-]{36}/[A-Za-z0-9_-]{1,64}\.(jpg|png|webp)$'
  ),
  constraint avatar_uploads_state_check check (
    (committed_at is null or discarded_at is null)
    and (committed_at is null or verified_at is not null)
  )
);

create index avatar_uploads_account_idx on app.avatar_uploads (account_id, created_at desc);

comment on table app.avatar_uploads is
  'Avatar paths handed out for upload; single use. Uncommitted rows mark files to clean up.';

alter table app.avatar_uploads enable row level security;
revoke all on table app.avatar_uploads from public, anon, authenticated;

-- MyProfile DTO (packages/contracts/src/profile.ts).
create function app_private.my_profile(p_account app.account_profiles)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_account.id,
    'email', p_account.login_email_key,
    'fullName', p_account.full_name,
    'accountType', p_account.account_type,
    'mustChangePassword', p_account.must_change_password,
    'phone', p_account.phone,
    'birthDate', p_account.birth_date,
    'avatarPath', p_account.avatar_path,
    'rowVersion', p_account.row_version
  )
$$;

-- Readable while the password must still be changed, so the SPA can route
-- the user to that step (AUTH-01).
create function api.get_my_profile()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  return app_private.my_profile(app_private.require_account(p_allow_password_change => true));
end
$$;

-- AUTH-08: own name, phone and birth date. Email, type, status and
-- assignments are not part of self-service.
create function api.update_my_profile(
  p_full_name text,
  p_phone text,
  p_birth_date date,
  p_expected_version bigint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_caller app.account_profiles := app_private.require_account(p_lock => true);
  v_full_name text := app_private.normalize_name(p_full_name);
  v_phone text := app_private.normalize_phone(p_phone);
  v_birth_date date := app_private.check_birth_date(p_birth_date);
  v_before app.account_profiles;
  v_after app.account_profiles;
begin
  select * into v_before from app.account_profiles a where a.id = v_caller.id for update;
  if p_expected_version is null or v_before.row_version <> p_expected_version then
    perform app_private.raise_api_error(409, 'version_conflict');
  end if;
  if v_before.full_name = v_full_name
    and v_before.phone is not distinct from v_phone
    and v_before.birth_date is not distinct from v_birth_date
  then
    return app_private.my_profile(v_before);
  end if;

  update app.account_profiles a
     set full_name = v_full_name,
         phone = v_phone,
         birth_date = v_birth_date,
         row_version = a.row_version + 1,
         updated_at = now()
   where a.id = v_caller.id
  returning * into v_after;

  perform app_private.record_account_change(v_before, v_after, v_caller.id, 'app', 'account.profile.update');
  return app_private.my_profile(v_after);
end
$$;

-- Hands out a new single-use path under the caller's folder. At most 20
-- unused reservations per hour per account.
create function api.reserve_avatar_upload(p_extension text)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_caller app.account_profiles := app_private.require_account();
  v_path text;
begin
  if p_extension is null or p_extension not in ('jpg', 'png', 'webp') then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  if (select count(*) from app.avatar_uploads u
       where u.account_id = v_caller.id
         and u.committed_at is null
         and u.created_at > now() - interval '1 hour') >= 20
  then
    perform app_private.raise_api_error(429, 'rate_limited');
  end if;
  v_path := format('%s/%s.%s', v_caller.id, replace(gen_random_uuid()::text, '-', ''), p_extension);
  insert into app.avatar_uploads (path, account_id) values (v_path, v_caller.id);
  return v_path;
end
$$;

-- Switches the avatar to a reserved path whose file the Worker has verified.
-- Returns the new profile and the path that is no longer referenced.
create function api.set_my_avatar(p_path text, p_expected_version bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_caller app.account_profiles := app_private.require_account(p_lock => true);
  v_upload app.avatar_uploads;
  v_before app.account_profiles;
  v_after app.account_profiles;
begin
  select * into v_upload from app.avatar_uploads u where u.path = p_path for update;
  -- Signed upload URLs are valid for 2 hours; older reservations are not accepted.
  if not found
    or v_upload.account_id <> v_caller.id
    or v_upload.verified_at is null
    or v_upload.committed_at is not null
    or v_upload.discarded_at is not null
    or v_upload.created_at <= now() - interval '2 hours'
  then
    perform app_private.raise_api_error(400, 'avatar_invalid');
  end if;

  select * into v_before from app.account_profiles a where a.id = v_caller.id for update;
  if p_expected_version is null or v_before.row_version <> p_expected_version then
    perform app_private.raise_api_error(409, 'version_conflict');
  end if;

  update app.account_profiles a
     set avatar_path = p_path,
         row_version = a.row_version + 1,
         updated_at = now()
   where a.id = v_caller.id
  returning * into v_after;
  update app.avatar_uploads u set committed_at = now() where u.path = p_path;

  perform app_private.record_account_change(v_before, v_after, v_caller.id, 'app', 'account.avatar.update');
  return jsonb_build_object('profile', app_private.my_profile(v_after),
                            'previousPath', v_before.avatar_path);
end
$$;

create function api.clear_my_avatar(p_expected_version bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_caller app.account_profiles := app_private.require_account(p_lock => true);
  v_before app.account_profiles;
  v_after app.account_profiles;
begin
  select * into v_before from app.account_profiles a where a.id = v_caller.id for update;
  if p_expected_version is null or v_before.row_version <> p_expected_version then
    perform app_private.raise_api_error(409, 'version_conflict');
  end if;
  if v_before.avatar_path is null then
    return jsonb_build_object('profile', app_private.my_profile(v_before), 'previousPath', null);
  end if;

  update app.account_profiles a
     set avatar_path = null,
         row_version = a.row_version + 1,
         updated_at = now()
   where a.id = v_caller.id
  returning * into v_after;

  perform app_private.record_account_change(v_before, v_after, v_caller.id, 'app', 'account.avatar.remove');
  return jsonb_build_object('profile', app_private.my_profile(v_after),
                            'previousPath', v_before.avatar_path);
end
$$;

-- Worker (service role) bookkeeping around Storage. Only the Worker can mark a
-- file as checked, so set_my_avatar() called directly through the Data API
-- cannot skip the content check. A path that was never
-- committed is marked discarded before its file is deleted, so it can no
-- longer be committed; a committed path is reported as referenced while any
-- profile still uses it.
create function api.mark_avatar_verified(p_path text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  update app.avatar_uploads u
     set verified_at = now()
   where u.path = p_path and u.committed_at is null and u.discarded_at is null;
  if not found then
    perform app_private.raise_api_error(400, 'avatar_invalid');
  end if;
end
$$;

create function api.discard_avatar_upload(p_path text)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_upload app.avatar_uploads;
begin
  select * into v_upload from app.avatar_uploads u where u.path = p_path for update;
  if not found then
    return false;
  end if;
  if v_upload.committed_at is null and v_upload.discarded_at is null then
    update app.avatar_uploads u set discarded_at = now() where u.path = p_path;
  end if;
  return v_upload.committed_at is null
      or not exists (select 1 from app.account_profiles a where a.avatar_path = p_path);
end
$$;

grant execute on function api.get_my_profile() to authenticated;
grant execute on function api.update_my_profile(text, text, date, bigint) to authenticated;
grant execute on function api.reserve_avatar_upload(text) to authenticated;
grant execute on function api.set_my_avatar(text, bigint) to authenticated;
grant execute on function api.clear_my_avatar(bigint) to authenticated;
grant execute on function api.mark_avatar_verified(text) to service_role;
grant execute on function api.discard_avatar_upload(text) to service_role;
