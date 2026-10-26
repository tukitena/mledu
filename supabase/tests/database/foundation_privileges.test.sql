-- Only designed RPCs in `api` are reachable by client roles; tables and helpers are not.
begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

select has_schema('app');
select has_schema('app_private');
select has_schema('api');

select is(
  (select count(*)::int
     from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'app' and c.relkind = 'r' and not c.relrowsecurity),
  0,
  'every table in app has RLS enabled'
);

select is(
  (select count(*)::int
     from information_schema.role_table_grants g
    where g.table_schema in ('app', 'app_private', 'api')
      and g.grantee in ('anon', 'authenticated', 'PUBLIC')),
  0,
  'anon/authenticated have no table privileges in app, app_private or api'
);

select is(
  (select count(*)::int
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('app', 'app_private')
      and (has_function_privilege('anon', p.oid, 'execute')
        or has_function_privilege('authenticated', p.oid, 'execute'))),
  0,
  'client roles cannot execute helpers in app/app_private'
);

select ok(not has_schema_privilege('anon', 'app', 'usage'), 'anon has no usage on app');
select ok(not has_schema_privilege('authenticated', 'app_private', 'usage'),
  'authenticated has no usage on app_private');

select ok(has_function_privilege('anon', 'api.health_check()', 'execute'),
  'anon may call the health probe');
select ok(not has_function_privilege('anon', 'api.current_session(boolean)', 'execute'),
  'anon cannot resolve a session');
select ok(has_function_privilege('authenticated', 'api.current_session(boolean)', 'execute'),
  'authenticated may resolve its own session');

-- Every function exposed in api pins its search_path.
select is(
  (select count(*)::int
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('api', 'app_private')
      and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')),
  0,
  'api/app_private functions set search_path'
);

set local role anon;
select throws_ok(
  'select count(*) from app.account_profiles',
  '42501', null, 'anon cannot read account profiles directly'
);
reset role;

set local role authenticated;
select throws_ok(
  'select count(*) from app.audit_events',
  '42501', null, 'authenticated cannot read audit directly'
);
reset role;

select * from finish();
rollback;
