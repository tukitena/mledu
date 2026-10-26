-- Account profile and request-time access checks (AUTH-03/04/07/08 foundation).
-- Account management commands are added in GĐ 2; this migration only provides
-- the data every later command depends on to identify the caller.

create type app.account_type as enum ('admin', 'receptionist', 'user');

create table app.account_profiles (
  id uuid primary key references auth.users (id) on delete restrict,
  -- Trimmed, lower-case login email. Unique including soft-deleted accounts (AUTH-04).
  login_email_key text not null,
  full_name text not null,
  account_type app.account_type not null default 'user',
  is_enabled boolean not null default true,
  must_change_password boolean not null default true,
  phone text,
  birth_date date,
  -- Relative path inside the private `avatars` bucket: <account id>/<file>.<ext>.
  avatar_path text,
  -- Auth sessions created before this instant are rejected at request time.
  sessions_valid_after timestamptz,
  row_version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  deleted_by uuid references app.account_profiles (id),
  constraint account_profiles_login_email_key_key unique (login_email_key),
  constraint account_profiles_login_email_key_check
    check (login_email_key = lower(btrim(login_email_key)) and login_email_key <> ''),
  constraint account_profiles_full_name_check check (
    full_name = btrim(full_name)
    and full_name is nfc normalized
    and char_length(full_name) between 1 and 200
  ),
  constraint account_profiles_phone_check
    check (phone is null or phone ~ '^(0[0-9]{9,10}|\+[0-9]{8,15})$'),
  constraint account_profiles_avatar_path_check check (
    avatar_path is null
    or (
      split_part(avatar_path, '/', 1) = id::text
      and avatar_path ~ '^[0-9a-f-]{36}/[A-Za-z0-9_-]{1,64}\.(jpg|png|webp)$'
    )
  ),
  constraint account_profiles_row_version_check check (row_version >= 1),
  constraint account_profiles_deleted_check check (deleted_by is null or deleted_at is not null)
);

comment on table app.account_profiles is
  'Internal account (Admin/Receptionist/User). Class roles live in staff assignments.';

alter table app.account_profiles enable row level security;
revoke all on table app.account_profiles from public, anon, authenticated;

-- Resolves the caller for the current request from the database, never from
-- role claims in the JWT. Fails with:
--   401 unauthenticated            no user/session claim
--   401 session_invalid            Auth session missing, expired or revoked
--   401 account_disabled           account disabled or soft-deleted
--   403 password_change_required   temporary password not changed yet
-- p_lock keeps a share lock on the account row until the command commits, so
-- a concurrent disable/role change waits for (or blocks) the command.
create function app_private.require_account(
  p_allow_password_change boolean default false,
  p_lock boolean default false
)
returns app.account_profiles
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_session_claim text := auth.jwt() ->> 'session_id';
  v_session_created_at timestamptz;
  v_account app.account_profiles;
begin
  if v_user_id is null
    or v_session_claim is null
    or v_session_claim !~ '^[0-9a-fA-F-]{36}$'
  then
    perform app_private.raise_api_error(401, 'unauthenticated');
  end if;

  select s.created_at
    into v_session_created_at
    from auth.sessions s
   where s.id = v_session_claim::uuid
     and s.user_id = v_user_id
     and (s.not_after is null or s.not_after > now());
  if not found then
    perform app_private.raise_api_error(401, 'session_invalid');
  end if;

  if p_lock then
    select * into v_account from app.account_profiles a where a.id = v_user_id for share;
  else
    select * into v_account from app.account_profiles a where a.id = v_user_id;
  end if;

  if not found or v_account.deleted_at is not null or not v_account.is_enabled then
    perform app_private.raise_api_error(401, 'account_disabled');
  end if;

  if v_account.sessions_valid_after is not null
    and v_session_created_at < v_account.sessions_valid_after
  then
    perform app_private.raise_api_error(401, 'session_invalid');
  end if;

  if v_account.must_change_password and not p_allow_password_change then
    perform app_private.raise_api_error(403, 'password_change_required');
  end if;

  return v_account;
end
$$;

-- Used by the Worker session middleware on every authenticated request.
create function api.current_session(p_allow_password_change boolean default false)
returns table (account_id uuid, account_type text, must_change_password boolean)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_account app.account_profiles;
begin
  v_account := app_private.require_account(p_allow_password_change);
  return query select v_account.id, v_account.account_type::text, v_account.must_change_password;
end
$$;

grant execute on function api.current_session(boolean) to authenticated;
