-- GĐ 2: accounts, Auth commands and request-time access (AUTH-01–08).
--
-- Supabase Auth keeps passwords and sessions. Every Auth change MLedu needs
-- (create account, temporary password, own password change, email reset) is
-- prepared by a checked RPC as an app.auth_commands row, executed by GoTrue and
-- completed by a deferred trigger on auth.users inside GoTrue's own transaction,
-- so the profile change, history and audit commit or roll back with the Auth
-- change (design tested in GĐ 0: docs/developer/decisions/auth-audit-transaction.md).
--
-- Disable/enable, soft delete/restore and User/Receptionist changes do not touch
-- Auth: the access token hook and require_account() read the current account
-- state on every token issue and request, so they are ordinary RPCs with audit.

alter table app.account_profiles
  -- Last time the password was set by any designed flow. Reset links issued
  -- before it are no longer accepted (AUTH-02).
  add column credentials_changed_at timestamptz,
  add column deleted_reason text,
  add constraint account_profiles_deleted_reason_check check (
    (deleted_at is null and deleted_reason is null)
    or (deleted_at is not null and deleted_reason is not null
        and char_length(deleted_reason) between 1 and 1000)
  ),
  add constraint account_profiles_birth_date_check
    check (birth_date is null or birth_date >= date '1900-01-01');

-------------------------------------------------------------------------------
-- Input normalization (C.1.1, AUTH-07). Raise 400 validation_failed.
-------------------------------------------------------------------------------

create function app_private.normalize_email(p_email text)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
begin
  if char_length(v_email) not between 3 and 254 or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  return v_email;
end
$$;

create function app_private.normalize_name(p_value text)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  v_value text := normalize(regexp_replace(coalesce(p_value, ''), '^\s+|\s+$', '', 'g'), nfc);
begin
  if char_length(v_value) not between 1 and 200 then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  return v_value;
end
$$;

-- Optional phone: separators are dropped; empty becomes NULL.
create function app_private.normalize_phone(p_value text)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  v_value text := nullif(regexp_replace(coalesce(p_value, ''), '[\s.()-]', '', 'g'), '');
begin
  if v_value is not null and v_value !~ '^(0[0-9]{9,10}|\+[0-9]{8,15})$' then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  return v_value;
end
$$;

-- Optional birth date: not in the future (business date) and not before 1900.
create function app_private.check_birth_date(p_value date)
returns date
language plpgsql
stable
set search_path = ''
as $$
begin
  if p_value is not null
    and (p_value > app_private.business_date(now()) or p_value < date '1900-01-01')
  then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  return p_value;
end
$$;

create function app_private.normalize_reason(p_value text)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  v_value text := normalize(regexp_replace(coalesce(p_value, ''), '^\s+|\s+$', '', 'g'), nfc);
begin
  if char_length(v_value) not between 1 and 1000 then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  return v_value;
end
$$;

-------------------------------------------------------------------------------
-- History, audit and DTOs for account changes.
-------------------------------------------------------------------------------

-- Business snapshot without secrets. Key names avoid "password" on purpose:
-- assert_no_secrets() rejects them in audit/history payloads.
create function app_private.account_snapshot(p_account app.account_profiles)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'login_email_key', p_account.login_email_key,
    'full_name', p_account.full_name,
    'account_type', p_account.account_type,
    'is_enabled', p_account.is_enabled,
    'credential_change_required', p_account.must_change_password,
    'phone', p_account.phone,
    'birth_date', p_account.birth_date,
    'avatar_path', p_account.avatar_path,
    'deleted_at', p_account.deleted_at,
    'deleted_by', p_account.deleted_by,
    'deleted_reason', p_account.deleted_reason
  )
$$;

-- Records the new version and the audit row of one account change, inside the
-- caller's transaction. p_before is NULL for a new account.
create function app_private.record_account_change(
  p_before app.account_profiles,
  p_after app.account_profiles,
  p_actor_id uuid,
  p_source text,
  p_action text,
  p_operator text default null,
  p_reason text default null
)
returns void
language plpgsql
set search_path = ''
as $$
begin
  perform app_private.record_version('account_profile', p_after.id, p_after.row_version,
    app_private.account_snapshot(p_after), p_actor_id, p_reason);
  perform app_private.write_audit(
    p_actor_id,
    p_source,
    p_action,
    jsonb_build_object('account_id', p_after.id),
    jsonb_strip_nulls(jsonb_build_object(
      'before', case when p_before.id is null then null else app_private.account_snapshot(p_before) end,
      'after', app_private.account_snapshot(p_after),
      'operator', p_operator,
      'reason', p_reason
    ))
  );
end
$$;

create function app_private.account_status(p_account app.account_profiles)
returns text
language sql
stable
set search_path = ''
as $$
  select case
    when p_account.deleted_at is not null then 'deleted'
    when not p_account.is_enabled then 'disabled'
    else 'active'
  end
$$;

-- AccountSummary DTO (packages/contracts/src/accounts.ts).
create function app_private.account_summary(p_account app.account_profiles)
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
    'status', app_private.account_status(p_account),
    'mustChangePassword', p_account.must_change_password,
    'phone', p_account.phone,
    'birthDate', p_account.birth_date,
    'hasAvatar', p_account.avatar_path is not null,
    'rowVersion', p_account.row_version,
    'createdAt', p_account.created_at,
    'deletedAt', p_account.deleted_at,
    'deletedReason', p_account.deleted_reason
  )
$$;

-------------------------------------------------------------------------------
-- Request-time caller checks.
-------------------------------------------------------------------------------

-- A session opened from an email link (recovery or magic link) has AMR claims
-- but none of them is "password". Such sessions may only reset the password.
create function app_private.is_email_link_session(p_session_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from auth.mfa_amr_claims c where c.session_id = p_session_id)
     and not exists (
       select 1 from auth.mfa_amr_claims c
        where c.session_id = p_session_id and c.authentication_method = 'password'
     )
$$;

drop function app_private.require_account(boolean, boolean);

-- Resolves the caller for the current request from the database, never from
-- role claims in the JWT. Fails with:
--   401 unauthenticated            no user/session claim
--   401 session_invalid            Auth session missing, expired or revoked
--   401 account_disabled           account disabled or soft-deleted
--   403 password_reset_required    session opened from an email link (AUTH-02)
--   403 password_change_required   temporary password not changed yet
-- p_lock keeps a share lock on the account row until the command commits, so
-- a concurrent disable/role change waits for (or blocks) the command.
create function app_private.require_account(
  p_allow_password_change boolean default false,
  p_lock boolean default false,
  p_allow_email_link boolean default false
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

  if not p_allow_email_link and app_private.is_email_link_session(v_session_claim::uuid) then
    perform app_private.raise_api_error(403, 'password_reset_required');
  end if;

  if v_account.must_change_password and not p_allow_password_change then
    perform app_private.raise_api_error(403, 'password_change_required');
  end if;

  return v_account;
end
$$;

create function app_private.require_admin()
returns app.account_profiles
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_actor app.account_profiles;
begin
  v_actor := app_private.require_account(p_lock => true);
  if v_actor.account_type <> 'admin' then
    perform app_private.raise_api_error(403, 'forbidden');
  end if;
  return v_actor;
end
$$;

-- Locks a target of an account-management command. Admin accounts are never
-- managed through the application (AUTH-06), whoever the caller is.
create function app_private.lock_managed_account(p_account_id uuid, p_expected_version bigint)
returns app.account_profiles
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_account app.account_profiles;
begin
  select * into v_account from app.account_profiles a where a.id = p_account_id for update;
  if not found then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  if v_account.account_type = 'admin' then
    perform app_private.raise_api_error(403, 'admin_account_forbidden');
  end if;
  if p_expected_version is null or v_account.row_version <> p_expected_version then
    perform app_private.raise_api_error(409, 'version_conflict');
  end if;
  return v_account;
end
$$;

-------------------------------------------------------------------------------
-- Access token hook: no token for disabled/deleted accounts or revoked sessions.
-------------------------------------------------------------------------------

-- Runs for every token Supabase Auth issues (sign-in, refresh, email link).
-- Configured in supabase/config.toml [auth.hook.custom_access_token]; hosted
-- projects must enable the same hook. Claims are returned unchanged: account
-- type is never read from the JWT.
create function app_private.access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_account app.account_profiles;
  v_session_id uuid;
  v_session_created_at timestamptz;
begin
  select * into v_account from app.account_profiles a where a.id = (event ->> 'user_id')::uuid;
  if not found or v_account.deleted_at is not null or not v_account.is_enabled then
    return jsonb_build_object('error',
      jsonb_build_object('http_code', 403, 'message', 'account_disabled'));
  end if;

  v_session_id := nullif(event -> 'claims' ->> 'session_id', '')::uuid;
  select s.created_at into v_session_created_at from auth.sessions s where s.id = v_session_id;
  if (found and v_session_created_at < v_account.sessions_valid_after)
    or (not found and event ->> 'authentication_method' = 'token_refresh')
  then
    return jsonb_build_object('error',
      jsonb_build_object('http_code', 403, 'message', 'session_invalid'));
  end if;

  return jsonb_build_object('claims', event -> 'claims');
end
$$;

grant usage on schema app_private to supabase_auth_admin;
grant execute on function app_private.access_token_hook(jsonb) to supabase_auth_admin;

-------------------------------------------------------------------------------
-- Auth commands: prepared by a checked RPC, completed inside GoTrue's transaction.
-------------------------------------------------------------------------------

create table app.auth_commands (
  id uuid primary key default gen_random_uuid(),
  kind text not null,
  -- app: application request; ops: controlled operations tool (AUTH-06).
  source text not null,
  actor_id uuid references app.account_profiles (id),
  -- Session that prepared an app command; re-checked when the command completes.
  actor_session_id uuid,
  -- Operator named by the operations tool; recorded in audit.
  operator text,
  -- Account the command applies to. For account.create, the id of the new user.
  target_id uuid not null,
  -- Non-secret data the completion needs (account.create profile fields).
  payload jsonb not null default '{}',
  expected_version bigint,
  request_id text,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default clock_timestamp() + interval '60 seconds',
  consumed_at timestamptz,
  constraint auth_commands_kind_check check (kind in (
    'account.create', 'account.password.temporary', 'account.password.change', 'account.password.reset'
  )),
  constraint auth_commands_source_check check (
    (source = 'app' and actor_id is not null and actor_session_id is not null and operator is null)
    or (source = 'ops' and actor_id is null and char_length(operator) between 1 and 200)
  ),
  constraint auth_commands_self_check check (
    kind not in ('account.password.change', 'account.password.reset')
    or (source = 'app' and actor_id = target_id)
  ),
  constraint auth_commands_payload_check check (jsonb_typeof(payload) = 'object')
);

create index auth_commands_open_idx on app.auth_commands (target_id) where consumed_at is null;

comment on table app.auth_commands is
  'Checked intent for one Supabase Auth change; consumed by the auth.users trigger. No secrets.';

alter table app.auth_commands enable row level security;
revoke all on table app.auth_commands from public, anon, authenticated;

create function app_private.auth_commands_before_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.created_at := now();
  new.expires_at := clock_timestamp() + interval '60 seconds';
  new.request_id := coalesce(new.request_id, app_private.current_request_id());
  perform app_private.assert_no_secrets(new.payload);
  return new;
end
$$;

create trigger auth_commands_before_insert
  before insert on app.auth_commands
  for each row execute function app_private.auth_commands_before_insert();

-- The prepared intent of an app command still holds at completion time: the
-- actor is enabled, of the right type, and its session is still valid. The
-- session row stays share-locked until commit, so a logout waits (GĐ 0 finding).
create function app_private.recheck_command_actor(p_command app.auth_commands)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_actor app.account_profiles;
  v_session_created_at timestamptz;
begin
  if p_command.source = 'ops' then
    return;
  end if;

  select * into v_actor from app.account_profiles a where a.id = p_command.actor_id for share;
  select s.created_at into v_session_created_at
    from auth.sessions s
   where s.id = p_command.actor_session_id
     and s.user_id = p_command.actor_id
     and (s.not_after is null or s.not_after > now())
     for share;

  if v_actor.id is null
    or v_actor.deleted_at is not null
    or not v_actor.is_enabled
    or v_session_created_at is null
    or v_session_created_at < v_actor.sessions_valid_after
    or (p_command.kind in ('account.create', 'account.password.temporary')
        and (v_actor.account_type <> 'admin' or v_actor.must_change_password))
  then
    raise exception using errcode = '42501', message = 'auth_command_actor_revoked';
  end if;
end
$$;

create function app_private.take_auth_command(p_ref text, p_kind text, p_target uuid)
returns app.auth_commands
language plpgsql
set search_path = ''
as $$
declare
  v_command app.auth_commands;
begin
  if p_ref is null or p_ref !~ '^[0-9a-f-]{36}$' then
    raise exception using errcode = '42501', message = 'auth_command_required';
  end if;
  select * into v_command from app.auth_commands c where c.id = p_ref::uuid for update;
  if not found
    or v_command.kind <> p_kind
    or v_command.target_id <> p_target
    or v_command.consumed_at is not null
    or v_command.expires_at <= clock_timestamp()
  then
    raise exception using errcode = '42501', message = 'auth_command_invalid';
  end if;
  return v_command;
end
$$;

-- Own password change/reset goes through PUT /auth/v1/user, which cannot carry
-- app metadata. GoTrue signs out every other session of the user in the same
-- transaction, so the open command whose session still exists is the one that
-- made this change.
create function app_private.take_self_command(p_target uuid)
returns app.auth_commands
language plpgsql
set search_path = ''
as $$
declare
  v_command app.auth_commands;
begin
  select * into v_command
    from app.auth_commands c
   where c.target_id = p_target
     and c.kind in ('account.password.change', 'account.password.reset')
     and c.consumed_at is null
     and c.expires_at > clock_timestamp()
     and exists (
       select 1 from auth.sessions s where s.id = c.actor_session_id and s.user_id = p_target
     )
   order by c.created_at desc
   limit 1
     for update;
  if not found then
    raise exception using errcode = '42501', message = 'auth_command_required';
  end if;
  return v_command;
end
$$;

-- Audit written inside GoTrue's transaction keeps the request ID of the API
-- request that prepared the command (current_request_id() reads this setting).
create function app_private.use_command_request_id(p_command app.auth_commands)
returns void
language plpgsql
set search_path = ''
as $$
begin
  perform set_config('request.headers',
    jsonb_build_object('x-request-id', p_command.request_id)::text, true);
end
$$;

-- Completes the command behind one GoTrue change of auth.users. Any failure
-- raises, which aborts GoTrue's transaction: no Auth change without its
-- MLedu state and audit, and no audit without the Auth change.
create function app_private.complete_auth_command(p_user_id uuid, p_event text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user auth.users;
  v_command app.auth_commands;
  v_before app.account_profiles;
  v_after app.account_profiles;
  v_session_created_at timestamptz;
  v_link_issued_at timestamptz;
  v_ref text;
begin
  -- Read the row as it is at commit: GoTrue writes app_metadata after the
  -- INSERT/password UPDATE that queued this trigger.
  select * into strict v_user from auth.users u where u.id = p_user_id;
  v_ref := v_user.raw_app_meta_data ->> 'mledu_command';

  if p_event = 'insert' then
    v_command := app_private.take_auth_command(v_ref, 'account.create', p_user_id);
    perform app_private.recheck_command_actor(v_command);
    if lower(btrim(v_user.email)) is distinct from v_command.payload ->> 'email' then
      raise exception using errcode = '42501', message = 'auth_command_mismatch';
    end if;

    insert into app.account_profiles (
      id, login_email_key, full_name, account_type, phone, birth_date,
      must_change_password, credentials_changed_at
    )
    values (
      p_user_id,
      v_command.payload ->> 'email',
      v_command.payload ->> 'full_name',
      (v_command.payload ->> 'account_type')::app.account_type,
      v_command.payload ->> 'phone',
      (v_command.payload ->> 'birth_date')::date,
      true,
      clock_timestamp()
    )
    returning * into v_after;

    perform app_private.use_command_request_id(v_command);
    perform app_private.record_account_change(null, v_after, v_command.actor_id,
      v_command.source, 'account.create', v_command.operator);

  elsif p_event = 'password' then
    if exists (
      select 1 from app.auth_commands c
       where v_ref ~ '^[0-9a-f-]{36}$' and c.id = v_ref::uuid
         and c.kind = 'account.password.temporary' and c.consumed_at is null
    ) then
      -- Admin/ops update through the Auth Admin API carries the command id; an
      -- id left in app_metadata by an earlier, consumed command never matches.
      v_command := app_private.take_auth_command(v_ref, 'account.password.temporary', p_user_id);
    else
      v_command := app_private.take_self_command(p_user_id);
    end if;

    select * into v_before from app.account_profiles a where a.id = p_user_id for update;
    if not found then
      raise exception using errcode = '42501', message = 'auth_command_mismatch';
    end if;
    perform app_private.recheck_command_actor(v_command);

    case v_command.kind
      when 'account.password.temporary' then
        if v_before.deleted_at is not null
          or (v_command.source = 'app' and v_before.account_type = 'admin')
          or v_before.row_version <> v_command.expected_version
        then
          raise exception using errcode = '42501', message = 'auth_command_stale';
        end if;
        -- GoTrue already signed out every session; the mark also covers tokens.
        update app.account_profiles a
           set must_change_password = true,
               sessions_valid_after = clock_timestamp(),
               credentials_changed_at = clock_timestamp(),
               row_version = a.row_version + 1,
               updated_at = now()
         where a.id = p_user_id
        returning * into v_after;

      when 'account.password.change' then
        if v_before.deleted_at is not null or not v_before.is_enabled then
          raise exception using errcode = '42501', message = 'auth_command_stale';
        end if;
        -- The current session is kept; GoTrue signed out the others (AUTH-08).
        update app.account_profiles a
           set must_change_password = false,
               credentials_changed_at = clock_timestamp(),
               row_version = a.row_version + 1,
               updated_at = now()
         where a.id = p_user_id
        returning * into v_after;

      when 'account.password.reset' then
        select s.created_at into v_session_created_at
          from auth.sessions s where s.id = v_command.actor_session_id;
        -- One reset per issued link: the link must be newer than the last
        -- password change, and the reset session must come from that link.
        -- GoTrue clears recovery_sent_at in this transaction, so the issue
        -- time recorded by prepare_password_reset() is used.
        v_link_issued_at := (v_command.payload ->> 'link_issued_at')::timestamptz;
        if v_before.deleted_at is not null
          or not v_before.is_enabled
          or v_link_issued_at is null
          or v_link_issued_at <= coalesce(v_before.credentials_changed_at, '-infinity')
          or v_session_created_at < v_link_issued_at
        then
          raise exception using errcode = '42501', message = 'reset_link_invalid';
        end if;
        -- Every session ends, including the one that reset (AUTH-02).
        update app.account_profiles a
           set must_change_password = false,
               sessions_valid_after = clock_timestamp(),
               credentials_changed_at = clock_timestamp(),
               row_version = a.row_version + 1,
               updated_at = now()
         where a.id = p_user_id
        returning * into v_after;
    end case;

    perform app_private.use_command_request_id(v_command);
    perform app_private.record_account_change(v_before, v_after, v_command.actor_id,
      v_command.source, v_command.kind, v_command.operator);
  else
    raise exception using errcode = '22023', message = 'unknown_auth_event';
  end if;

  update app.auth_commands c set consumed_at = clock_timestamp() where c.id = v_command.id;
end
$$;

-- Deferred: fires at the end of GoTrue's transaction, after all its updates.
-- Only GoTrue (supabase_auth_admin) is bound to commands; changes by the
-- database owner (seed files, maintenance) are outside the application.
create function app_private.auth_users_after_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user <> 'supabase_auth_admin' then
    return null;
  end if;
  if tg_op = 'INSERT' then
    perform app_private.complete_auth_command(new.id, 'insert');
  elsif new.encrypted_password is distinct from old.encrypted_password then
    perform app_private.complete_auth_command(new.id, 'password');
  end if;
  return null;
end
$$;

create constraint trigger mledu_complete_auth_command
  after insert or update on auth.users
  deferrable initially deferred
  for each row execute function app_private.auth_users_after_change();

-- The login email never changes through Auth (AUTH-07/08): email change
-- requests and confirmations are rejected before GoTrue stores them.
create function app_private.auth_users_guard_email()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user = 'supabase_auth_admin'
    and (new.email is distinct from old.email
      or (coalesce(new.email_change, '') <> '' and new.email_change is distinct from old.email_change))
  then
    raise exception using errcode = '42501', message = 'email_change_forbidden';
  end if;
  return new;
end
$$;

create trigger mledu_guard_email
  before update on auth.users
  for each row execute function app_private.auth_users_guard_email();

grant execute on function app_private.auth_users_after_change() to supabase_auth_admin;
grant execute on function app_private.auth_users_guard_email() to supabase_auth_admin;
grant execute on function app_private.complete_auth_command(uuid, text) to supabase_auth_admin;

-------------------------------------------------------------------------------
-- Prepare RPCs. The Worker calls these with the caller's JWT, then GoTrue.
-------------------------------------------------------------------------------

create function app_private.prepare_account_create(
  p_source text,
  p_actor app.account_profiles,
  p_operator text,
  p_email text,
  p_full_name text,
  p_account_type app.account_type,
  p_phone text,
  p_birth_date date
)
returns table (command_id uuid, account_id uuid)
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_email text := app_private.normalize_email(p_email);
  v_command app.auth_commands;
begin
  if exists (select 1 from app.account_profiles a where a.login_email_key = v_email)
    or exists (select 1 from auth.users u where lower(u.email) = v_email)
  then
    -- Includes soft-deleted accounts: their email stays theirs (AUTH-04).
    perform app_private.raise_api_error(409, 'email_taken');
  end if;

  insert into app.auth_commands (kind, source, actor_id, actor_session_id, operator, target_id, payload)
  values (
    'account.create',
    p_source,
    p_actor.id,
    case when p_source = 'app' then (auth.jwt() ->> 'session_id')::uuid end,
    p_operator,
    gen_random_uuid(),
    jsonb_build_object(
      'email', v_email,
      'full_name', app_private.normalize_name(p_full_name),
      'account_type', p_account_type,
      'phone', app_private.normalize_phone(p_phone),
      'birth_date', app_private.check_birth_date(p_birth_date)
    )
  )
  returning * into v_command;

  return query select v_command.id, v_command.target_id;
end
$$;

-- AUTH-07: accounts created in the application are always of type User.
create function api.prepare_account_create(
  p_email text,
  p_full_name text,
  p_phone text default null,
  p_birth_date date default null
)
returns table (command_id uuid, account_id uuid)
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  return query select * from app_private.prepare_account_create(
    'app', app_private.require_admin(), null, p_email, p_full_name, 'user', p_phone, p_birth_date);
end
$$;

-- AUTH-02: Admin issues a temporary password to a non-Admin account.
create function api.prepare_temporary_password(p_account_id uuid, p_expected_version bigint)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_admin();
  v_target app.account_profiles := app_private.lock_managed_account(p_account_id, p_expected_version);
  v_command_id uuid;
begin
  if v_target.deleted_at is not null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
  insert into app.auth_commands (kind, source, actor_id, actor_session_id, target_id, expected_version)
  values ('account.password.temporary', 'app', v_actor.id, (auth.jwt() ->> 'session_id')::uuid,
          v_target.id, v_target.row_version)
  returning id into v_command_id;
  return v_command_id;
end
$$;

-- AUTH-01/08: the caller changes its own password (also the forced first change).
create function api.prepare_password_change()
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_account(p_allow_password_change => true);
  v_command_id uuid;
begin
  insert into app.auth_commands (kind, source, actor_id, actor_session_id, target_id)
  values ('account.password.change', 'app', v_actor.id, (auth.jwt() ->> 'session_id')::uuid, v_actor.id)
  returning id into v_command_id;
  return v_command_id;
end
$$;

-- AUTH-02: called with the session the Worker obtained from the email link.
create function api.prepare_password_reset()
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_account(
    p_allow_password_change => true, p_allow_email_link => true);
  v_session_id uuid := (auth.jwt() ->> 'session_id')::uuid;
  v_recovery_sent_at timestamptz;
  v_session_created_at timestamptz;
  v_command_id uuid;
begin
  select u.recovery_sent_at into v_recovery_sent_at from auth.users u where u.id = v_actor.id;
  select s.created_at into v_session_created_at from auth.sessions s where s.id = v_session_id;
  -- The session must come from the latest link, issued after the last password change.
  if not app_private.is_email_link_session(v_session_id)
    or v_recovery_sent_at is null
    or v_recovery_sent_at <= coalesce(v_actor.credentials_changed_at, '-infinity')
    or v_session_created_at < v_recovery_sent_at
  then
    perform app_private.raise_api_error(400, 'reset_link_invalid');
  end if;
  insert into app.auth_commands (kind, source, actor_id, actor_session_id, target_id, payload)
  values ('account.password.reset', 'app', v_actor.id, v_session_id, v_actor.id,
          jsonb_build_object('link_issued_at', v_recovery_sent_at))
  returning id into v_command_id;
  return v_command_id;
end
$$;

-- Lets the Worker tell a lost GoTrue response from a failed change.
create function api.auth_command_status(p_command_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when c.consumed_at is not null then 'committed'
    when c.expires_at <= clock_timestamp() then 'expired'
    else 'pending'
  end
  from app.auth_commands c
  where c.id = p_command_id
$$;

grant execute on function api.prepare_account_create(text, text, text, date) to authenticated;
grant execute on function api.prepare_temporary_password(uuid, bigint) to authenticated;
grant execute on function api.prepare_password_change() to authenticated;
grant execute on function api.prepare_password_reset() to authenticated;
grant execute on function api.auth_command_status(uuid) to service_role;

-------------------------------------------------------------------------------
-- Account management without Auth changes (AUTH-03/04/05/07). Admin only.
-------------------------------------------------------------------------------

create function api.list_accounts(
  p_search text default null,
  p_status text default null,
  p_limit integer default 20,
  p_offset integer default 0
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_search text := nullif(lower(btrim(coalesce(p_search, ''))), '');
  v_result jsonb;
begin
  perform app_private.require_admin();
  if p_status is not null and p_status not in ('active', 'disabled', 'deleted') then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  if p_limit not between 1 and 100 or p_offset < 0 then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;

  with matching as (
    select a
      from app.account_profiles a
     where (v_search is null
            or strpos(lower(a.full_name), v_search) > 0
            or strpos(a.login_email_key, v_search) > 0)
       and (p_status is null or app_private.account_status(a) = p_status)
  )
  select jsonb_build_object(
    'total', (select count(*) from matching),
    'items', coalesce((
      select jsonb_agg(app_private.account_summary(p.a) order by (p.a).full_name, (p.a).id)
        from (select m.a from matching m order by (m.a).full_name, (m.a).id
              limit p_limit offset p_offset) p
    ), '[]')
  ) into v_result;
  return v_result;
end
$$;

create function api.get_account(p_account_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_account app.account_profiles;
begin
  perform app_private.require_admin();
  select * into v_account from app.account_profiles a where a.id = p_account_id;
  if not found then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  return app_private.account_summary(v_account);
end
$$;

-- AUTH-03. Sessions created before now stop working; re-enabling does not
-- bring them back.
create function api.set_account_enabled(
  p_account_id uuid,
  p_enabled boolean,
  p_expected_version bigint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_admin();
  v_before app.account_profiles := app_private.lock_managed_account(p_account_id, p_expected_version);
  v_after app.account_profiles;
begin
  if p_enabled is null then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  if v_before.deleted_at is not null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
  if v_before.is_enabled = p_enabled then
    return app_private.account_summary(v_before);
  end if;

  update app.account_profiles a
     set is_enabled = p_enabled,
         sessions_valid_after = clock_timestamp(),
         row_version = a.row_version + 1,
         updated_at = now()
   where a.id = p_account_id
  returning * into v_after;

  perform app_private.record_account_change(v_before, v_after, v_actor.id, 'app',
    case when p_enabled then 'account.enable' else 'account.disable' end);
  return app_private.account_summary(v_after);
end
$$;

-- AUTH-04. The account row, its email and every link to it are kept.
create function api.soft_delete_account(
  p_account_id uuid,
  p_reason text,
  p_expected_version bigint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_admin();
  v_before app.account_profiles := app_private.lock_managed_account(p_account_id, p_expected_version);
  v_reason text := app_private.normalize_reason(p_reason);
  v_after app.account_profiles;
begin
  if v_before.deleted_at is not null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
  -- GĐ 3 (CLASS-01) adds the teaching-assignment check here: reject while an
  -- assignment is in effect and cancel future ones in this same transaction.
  -- No assignment data exists before GĐ 3.

  update app.account_profiles a
     set deleted_at = now(),
         deleted_by = v_actor.id,
         deleted_reason = v_reason,
         sessions_valid_after = clock_timestamp(),
         row_version = a.row_version + 1,
         updated_at = now()
   where a.id = p_account_id
  returning * into v_after;

  perform app_private.record_account_change(v_before, v_after, v_actor.id, 'app',
    'account.soft_delete', null, v_reason);
  return app_private.account_summary(v_after);
end
$$;

-- AUTH-05. Restoring also enables the account; old sessions stay invalid.
create function api.restore_account(p_account_id uuid, p_expected_version bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_admin();
  v_before app.account_profiles := app_private.lock_managed_account(p_account_id, p_expected_version);
  v_after app.account_profiles;
begin
  if v_before.deleted_at is null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;

  update app.account_profiles a
     set deleted_at = null,
         deleted_by = null,
         deleted_reason = null,
         is_enabled = true,
         sessions_valid_after = clock_timestamp(),
         row_version = a.row_version + 1,
         updated_at = now()
   where a.id = p_account_id
  returning * into v_after;

  perform app_private.record_account_change(v_before, v_after, v_actor.id, 'app', 'account.restore');
  return app_private.account_summary(v_after);
end
$$;

-- AUTH-07. Only User <-> Receptionist; the new type applies to the next
-- request of every open session (require_account reads it each time).
create function api.set_account_type(
  p_account_id uuid,
  p_account_type text,
  p_expected_version bigint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_admin();
  v_before app.account_profiles;
  v_after app.account_profiles;
begin
  if p_account_type = 'admin' then
    perform app_private.raise_api_error(403, 'admin_account_forbidden');
  end if;
  if p_account_type is null or p_account_type not in ('user', 'receptionist') then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  v_before := app_private.lock_managed_account(p_account_id, p_expected_version);
  if v_before.deleted_at is not null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
  if v_before.account_type::text = p_account_type then
    return app_private.account_summary(v_before);
  end if;
  -- GĐ 3 (CLASS-01) adds the User -> Receptionist assignment check here:
  -- reject while any assignment is in effect, cancel future ones atomically.

  update app.account_profiles a
     set account_type = p_account_type::app.account_type,
         row_version = a.row_version + 1,
         updated_at = now()
   where a.id = p_account_id
  returning * into v_after;

  perform app_private.record_account_change(v_before, v_after, v_actor.id, 'app', 'account.type.change');
  return app_private.account_summary(v_after);
end
$$;

grant execute on function api.list_accounts(text, text, integer, integer) to authenticated;
grant execute on function api.get_account(uuid) to authenticated;
grant execute on function api.set_account_enabled(uuid, boolean, bigint) to authenticated;
grant execute on function api.soft_delete_account(uuid, text, bigint) to authenticated;
grant execute on function api.restore_account(uuid, bigint) to authenticated;
grant execute on function api.set_account_type(uuid, text, bigint) to authenticated;

-------------------------------------------------------------------------------
-- Operations tool (AUTH-06): Admin accounts are managed from inside, never
-- through application routes. Granted to service_role only; every change is
-- audited with source 'ops' and the operator's name.
-------------------------------------------------------------------------------

create function app_private.require_ops(p_operator text)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  v_operator text := btrim(coalesce(p_operator, ''));
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    perform app_private.raise_api_error(403, 'forbidden');
  end if;
  if char_length(v_operator) not between 1 and 200 then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  return v_operator;
end
$$;

create function api.ops_prepare_account_create(
  p_operator text,
  p_email text,
  p_full_name text,
  p_account_type text
)
returns table (command_id uuid, account_id uuid)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_operator text := app_private.require_ops(p_operator);
begin
  if p_account_type is null or p_account_type not in ('admin', 'receptionist', 'user') then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  return query select * from app_private.prepare_account_create(
    'ops', null, v_operator, p_email, p_full_name, p_account_type::app.account_type, null, null);
end
$$;

create function api.ops_prepare_temporary_password(p_operator text, p_account_id uuid)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_operator text := app_private.require_ops(p_operator);
  v_target app.account_profiles;
  v_command_id uuid;
begin
  select * into v_target from app.account_profiles a where a.id = p_account_id for update;
  if not found then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  if v_target.deleted_at is not null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
  insert into app.auth_commands (kind, source, operator, target_id, expected_version)
  values ('account.password.temporary', 'ops', v_operator, v_target.id, v_target.row_version)
  returning id into v_command_id;
  return v_command_id;
end
$$;

create function api.ops_set_account(
  p_operator text,
  p_account_id uuid,
  p_account_type text default null,
  p_enabled boolean default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_operator text := app_private.require_ops(p_operator);
  v_before app.account_profiles;
  v_after app.account_profiles;
begin
  if p_account_type is not null and p_account_type not in ('admin', 'receptionist', 'user') then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  select * into v_before from app.account_profiles a where a.id = p_account_id for update;
  if not found then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  if v_before.deleted_at is not null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
  if coalesce(p_account_type, v_before.account_type::text) = v_before.account_type::text
    and coalesce(p_enabled, v_before.is_enabled) = v_before.is_enabled
  then
    return app_private.account_summary(v_before);
  end if;

  update app.account_profiles a
     set account_type = coalesce(p_account_type::app.account_type, a.account_type),
         is_enabled = coalesce(p_enabled, a.is_enabled),
         sessions_valid_after = case
           when p_enabled is distinct from a.is_enabled and p_enabled is not null then clock_timestamp()
           else a.sessions_valid_after
         end,
         row_version = a.row_version + 1,
         updated_at = now()
   where a.id = p_account_id
  returning * into v_after;

  perform app_private.record_account_change(v_before, v_after, null, 'ops', 'account.ops.update',
    v_operator);
  return app_private.account_summary(v_after);
end
$$;

grant execute on function api.ops_prepare_account_create(text, text, text, text) to service_role;
grant execute on function api.ops_prepare_temporary_password(text, uuid) to service_role;
grant execute on function api.ops_set_account(text, uuid, text, boolean) to service_role;
