-- GĐ 1 foundation: schema layout and default privileges.
--
--   app          business tables. Not exposed through the Data API; no grants to
--                anon/authenticated. RLS is still enabled on every table.
--   app_private  helpers used by commands (permission checks, audit, outbox).
--   api          the only schema exposed through the Data API (supabase/config.toml).
--                Each function is a designed command/query with explicit checks.

create schema app;
create schema app_private;
create schema api;

revoke all on schema app, app_private, api from public;
grant usage on schema api to anon, authenticated, service_role;

-- Functions are executable by PUBLIC by default. Per-schema default privileges
-- cannot remove that global default, so revoke it for objects created by the
-- migration role; every grant below is then explicit.
alter default privileges for role postgres revoke execute on functions from public;

-- Business dates use Asia/Ho_Chi_Minh regardless of the session time zone.
create function app_private.business_date(p_at timestamptz)
returns date
language sql
immutable
parallel safe
set search_path = ''
as $$
  select (p_at at time zone 'Asia/Ho_Chi_Minh')::date
$$;

comment on function app_private.business_date(timestamptz) is
  'Calendar date of an instant in Asia/Ho_Chi_Minh (plans.md A.3).';

-- Raises an error that PostgREST maps to an HTTP status (PTxyz -> xyz). The
-- message is an ErrorCode from packages/contracts/src/common.ts.
create function app_private.raise_api_error(p_status integer, p_code text)
returns void
language plpgsql
set search_path = ''
as $$
begin
  raise exception using errcode = 'PT' || p_status::text, message = p_code;
end
$$;

-- Read-only health probe used by GET /v1/health/ready. Returns no data.
create function api.health_check()
returns boolean
language sql
stable
set search_path = ''
as $$
  select true
$$;

grant execute on function api.health_check() to anon, authenticated, service_role;
