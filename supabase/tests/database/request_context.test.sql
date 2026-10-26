-- The caller is resolved from live Auth sessions and current account state on
-- every request, never from role claims in the JWT (techstack §4.2, AUTH-03/07).
begin;
create extension if not exists pgtap with schema extensions;
select plan(11);

-- Seed fixtures: 1 admin, 2 receptionist, 3 user, 4 pending password change, 5 disabled.
insert into auth.sessions (id, user_id, created_at, updated_at)
values
  ('10000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000001', now(), now()),
  ('10000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-000000000003', now() - interval '1 hour', now()),
  ('10000000-0000-4000-8000-000000000004', '00000000-0000-4000-8000-000000000004', now(), now()),
  ('10000000-0000-4000-8000-000000000005', '00000000-0000-4000-8000-000000000005', now(), now());

create function pg_temp.as_user(p_user uuid, p_session uuid, p_role text default 'authenticated')
returns void
language sql
as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'session_id', p_session, 'role', p_role)::text, true);
$$;
grant execute on function pg_temp.as_user(uuid, uuid, text) to authenticated;

set local role authenticated;

select pg_temp.as_user('00000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001');
select results_eq(
  'select account_id, account_type, must_change_password from api.current_session()',
  $$values ('00000000-0000-4000-8000-000000000001'::uuid, 'admin'::text, false)$$,
  'a live session of an enabled account resolves to its current type'
);

-- A JWT that claims admin for a user account does not grant admin.
select set_config('request.jwt.claims', json_build_object(
  'sub', '00000000-0000-4000-8000-000000000003',
  'session_id', '10000000-0000-4000-8000-000000000003',
  'role', 'authenticated', 'app_metadata', json_build_object('account_type', 'admin'))::text, true);
select is((select account_type from api.current_session()), 'user', 'JWT claims do not change the account type');

select set_config('request.jwt.claims', '{"role": "authenticated"}', true);
select throws_ok('select * from api.current_session()', 'PT401', 'unauthenticated', 'missing subject is rejected');

select pg_temp.as_user('00000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-0000000000ff');
select throws_ok('select * from api.current_session()', 'PT401', 'session_invalid', 'unknown or logged-out session is rejected');

select pg_temp.as_user('00000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000003');
select throws_ok('select * from api.current_session()', 'PT401', 'session_invalid', 'a session of another user is rejected');

select pg_temp.as_user('00000000-0000-4000-8000-000000000005', '10000000-0000-4000-8000-000000000005');
select throws_ok('select * from api.current_session()', 'PT401', 'account_disabled', 'disabled account is rejected with a live session');

select pg_temp.as_user('00000000-0000-4000-8000-000000000004', '10000000-0000-4000-8000-000000000004');
select throws_ok('select * from api.current_session()', 'PT403', 'password_change_required', 'business calls wait for the password change');
select is((select must_change_password from api.current_session(true)), true, 'password-change flows may still identify the caller');

reset role;

-- Changes made by Admin/ops apply to the very next request of an existing session.
update app.account_profiles set account_type = 'receptionist' where id = '00000000-0000-4000-8000-000000000003';
update auth.sessions set not_after = now() - interval '1 second' where id = '10000000-0000-4000-8000-000000000004';

set local role authenticated;
select pg_temp.as_user('00000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000003');
select is((select account_type from api.current_session()), 'receptionist', 'type change applies without signing in again');

select pg_temp.as_user('00000000-0000-4000-8000-000000000004', '10000000-0000-4000-8000-000000000004');
select throws_ok('select * from api.current_session(true)', 'PT401', 'session_invalid', 'expired session (not_after) is rejected');
reset role;

-- Sessions created before the revocation mark stop working even if Auth still has them.
update app.account_profiles set sessions_valid_after = now() where id = '00000000-0000-4000-8000-000000000003';

set local role authenticated;
select pg_temp.as_user('00000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000003');
select throws_ok('select * from api.current_session()', 'PT401', 'session_invalid', 'sessions older than the revocation mark are rejected');
reset role;

select * from finish();
rollback;
