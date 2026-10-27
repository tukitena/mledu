-- Catalogs: subjects/grades (CAT-01), sites (SCHED-03) and rooms (SCHED-02/05),
-- lookup keys (STU-04), permissions, archive/restore and audit atomicity.
begin;
create extension if not exists pgtap with schema extensions;
select plan(44);

-- Seed fixtures: 1 admin, 2 receptionist, 3 user.
insert into auth.sessions (id, user_id, created_at, updated_at)
select format('20000000-0000-4000-8000-%s', lpad(n::text, 12, '0'))::uuid,
       format('00000000-0000-4000-8000-%s', lpad(n::text, 12, '0'))::uuid,
       now() - interval '1 minute', now()
  from generate_series(1, 3) n;
insert into auth.mfa_amr_claims (id, session_id, created_at, updated_at, authentication_method)
select gen_random_uuid(), s.id, now(), now(), 'password'
  from auth.sessions s where s.id::text like '20000000-0000-4000-8000-00000000000_';

create function pg_temp.as_user(p_user int)
returns void
language sql
as $$
  select set_config('request.jwt.claims', json_build_object(
    'sub', format('00000000-0000-4000-8000-%s', lpad(p_user::text, 12, '0')),
    'session_id', format('20000000-0000-4000-8000-%s', lpad(p_user::text, 12, '0')),
    'role', 'authenticated')::text, true);
$$;
grant execute on function pg_temp.as_user(int) to authenticated;

create function pg_temp.audits(p_action text)
returns bigint
language sql
as $$ select count(*) from app.audit_events where action = p_action and created_at = now() $$;

-- Values carried between steps (the role switch hides app tables).
create temp table ids (key text primary key, id uuid, version bigint);
grant all on ids to authenticated;

-------------------------------------------------------------------------------
-- Privileges and lookup keys.
-------------------------------------------------------------------------------
select ok(not has_table_privilege('authenticated', 'app.catalog_entries', 'select')
       and not has_table_privilege('authenticated', 'app.rooms', 'select')
       and not has_table_privilege('anon', 'app.sites', 'select'),
  'catalog tables are not exposed to clients');
select ok(not has_function_privilege('anon', 'api.create_site(text, text)', 'execute')
       and not has_function_privilege('anon', 'api.list_catalog_entries(text, boolean)', 'execute'),
  'anon cannot call catalog RPCs');
select is(app_private.name_key('  Đặng  Thị Ánh '), 'dang thi anh',
  'name key removes accents, maps đ to d and collapses whitespace');
select is(app_private.name_key('Nguyễn Văn Ước, Jr.'), 'nguyen van uoc, jr.',
  'name key keeps punctuation');

-------------------------------------------------------------------------------
-- Subjects and grades (CAT-01): Admin writes, everyone reads active entries.
-------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user(2);
select throws_ok($$select api.create_catalog_entry('subject', 'Vật lý')$$, 'PT403', 'forbidden',
  'a Receptionist cannot create subjects');
select pg_temp.as_user(3);
select throws_ok($$select api.create_catalog_entry('grade', 'Lớp 10')$$, 'PT403', 'forbidden',
  'a User cannot create grades');
select ok(jsonb_array_length(api.list_catalog_entries('subject')) >= 3, 'a User reads active subjects');
select throws_ok($$select api.list_catalog_entries('subject', true)$$, 'PT403', 'forbidden',
  'only Admin lists archived subjects');

select pg_temp.as_user(1);
insert into ids select 'physics', (e ->> 'id')::uuid, (e ->> 'rowVersion')::bigint
  from (select api.create_catalog_entry('subject', '  Vật   lý ') as e) c;
select is((select (api.list_catalog_entries('subject') -> -1 ->> 'name')
             from ids where key = 'physics') is not null, true, 'Admin creates a subject');
select throws_ok($$select api.create_catalog_entry('subject', 'VAT LY')$$, 'PT409', 'duplicate_name',
  'a name with the same key is refused');
select lives_ok($$select api.create_catalog_entry('grade', 'Vật lý')$$,
  'keys are unique per kind only');
select throws_ok($$select api.create_catalog_entry('subject', repeat('a', 101))$$, 'PT400',
  'validation_failed', 'names are limited to 100 characters');
select throws_ok($$select api.create_catalog_entry('teacher', 'Ai đó')$$, 'PT400',
  'validation_failed', 'unknown catalog kinds are refused');
select throws_ok($$select api.rename_catalog_entry((select id from ids where key = 'physics'), 'Lý', 9)$$,
  'PT409', 'version_conflict', 'stale versions are refused');
select is(api.rename_catalog_entry((select id from ids where key = 'physics'), 'Vật lí', 1) ->> 'name',
  'Vật lí', 'Admin renames a subject');
select throws_ok($$select api.archive_catalog_entry((select id from ids where key = 'physics'), ' ', 2)$$,
  'PT400', 'validation_failed', 'archiving needs a reason');
select is(api.archive_catalog_entry((select id from ids where key = 'physics'), 'Không mở nữa', 2)
          ->> 'archived', 'true', 'Admin archives a subject');
select ok(not exists (select 1 from jsonb_array_elements(api.list_catalog_entries('subject')) e
                       where (e ->> 'id')::uuid = (select id from ids where key = 'physics')),
  'archived subjects are not offered for new classes');
select throws_ok($$select api.create_catalog_entry('subject', 'vat li')$$, 'PT409', 'archived_duplicate',
  'creating an archived name asks for restoring it');
select is(api.restore_catalog_entry((select id from ids where key = 'physics'), 3) ->> 'id',
  (select id::text from ids where key = 'physics'), 'restoring reuses the identifier');
reset role;

select is(pg_temp.audits('catalog.subject.create') + pg_temp.audits('catalog.subject.rename')
        + pg_temp.audits('catalog.subject.archive') + pg_temp.audits('catalog.subject.restore'), 4::bigint,
  'every subject change has one audit row');
select is((select count(*) from app.business_entity_versions
            where entity_kind = 'catalog_entry' and entity_id = (select id from ids where key = 'physics')),
  4::bigint, 'every subject change keeps a version');
select is((select before_after #>> '{before,name}' from app.audit_events
            where action = 'catalog.subject.rename' and created_at = now()), 'Vật   lý',
  'audit keeps the value before the change');

-------------------------------------------------------------------------------
-- Sites (SCHED-03) and rooms (SCHED-02): Admin and Receptionist write.
-------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user(3);
select throws_ok($$select api.create_site('Tòa C', '3 Đường Thử nghiệm')$$, 'PT403', 'forbidden',
  'a User cannot create sites');
select ok(jsonb_array_length(api.list_rooms()) >= 3, 'a User reads active rooms');
select throws_ok($$select api.list_sites(true)$$, 'PT403', 'forbidden', 'a User cannot list archived sites');

select pg_temp.as_user(2);
insert into ids select 'site_c', (s ->> 'id')::uuid, (s ->> 'rowVersion')::bigint
  from (select api.create_site('Tòa C', '3 Đường Thử nghiệm') as s) c;
select throws_ok($$select api.create_site('toa c', 'Địa chỉ khác')$$, 'PT409', 'duplicate_name',
  'site names are unique by key');
select throws_ok($$select api.create_site('Tòa D', repeat('x', 501))$$, 'PT400', 'validation_failed',
  'addresses are limited to 500 characters');
insert into ids select 'room_c1', (r ->> 'id')::uuid, (r ->> 'rowVersion')::bigint
  from (select api.create_room((select id from ids where key = 'site_c'), 'P101') as r) c;
select is((select count(*)::int from jsonb_array_elements(api.list_rooms()) r where r ->> 'name' = 'P101'), 3,
  'the same room name exists at three sites as three rooms');
select throws_ok($$select api.create_room((select id from ids where key = 'site_c'), ' p101 ')$$,
  'PT409', 'duplicate_name', 'room names are unique within a site');
insert into ids select 'room_c2', (r ->> 'id')::uuid, (r ->> 'rowVersion')::bigint
  from (select api.create_room((select id from ids where key = 'site_c'), 'P202') as r) c;
select is(api.update_room((select id from ids where key = 'room_c2'),
            '11000000-0000-4000-8000-000000000001', 'P202', 1) ->> 'siteName', 'Tòa A',
  'a room moves to another active site');
select is(api.archive_room((select id from ids where key = 'room_c2'), 'Sửa chữa', 2) ->> 'archived',
  'true', 'Receptionist archives a room');
select is(api.restore_room((select id from ids where key = 'room_c2'), 3) ->> 'archived', 'false',
  'Receptionist restores a room');
reset role;

-------------------------------------------------------------------------------
-- Archiving a site archives its rooms in the same command (SCHED-05).
-------------------------------------------------------------------------------
create table app_private.test_fail_audit (on_ boolean);
create function app_private.test_fail_audit() returns trigger language plpgsql set search_path = '' as $$
begin
  if exists (select 1 from app_private.test_fail_audit) then
    raise exception 'injected audit failure';
  end if;
  return new;
end
$$;
create trigger zz_test_fail before insert on app.audit_events
  for each row execute function app_private.test_fail_audit();
insert into app_private.test_fail_audit values (true);

set local role authenticated;
select pg_temp.as_user(2);
select throws_ok($$select api.archive_site((select id from ids where key = 'site_c'), 'Đóng cơ sở', 1)$$,
  'P0001', 'injected audit failure', 'audit failure aborts archiving the site');
reset role;
delete from app_private.test_fail_audit;
select is((select count(*)::int from app.rooms
            where site_id = (select id from ids where key = 'site_c') and deleted_at is null), 1,
  'no room is archived when the site command fails');

set local role authenticated;
select pg_temp.as_user(2);
select is(api.archive_site((select id from ids where key = 'site_c'), 'Đóng cơ sở', 1) ->> 'activeRoomCount',
  '0', 'archiving a site archives its rooms');
select throws_ok($$select api.create_room((select id from ids where key = 'site_c'), 'P303')$$,
  'PT409', 'site_archived', 'no new room at an archived site');
select throws_ok($$select api.restore_room((select id from ids where key = 'room_c1'), 2)$$,
  'PT409', 'site_archived', 'a room cannot come back into an archived site');
select is(api.restore_site((select id from ids where key = 'site_c'), 2) ->> 'activeRoomCount', '0',
  'restoring a site does not restore its rooms');
select is(api.restore_room((select id from ids where key = 'room_c1'), 2) ->> 'archived', 'false',
  'rooms are restored one by one with their identifier');
select ok(exists (select 1 from jsonb_array_elements(api.list_sites(true)) s
                   where s ->> 'name' = 'Tòa C' and s ->> 'archived' = 'false'),
  'Receptionist lists sites including archived ones');
reset role;

select is(pg_temp.audits('site.archive'), 1::bigint, 'archiving a site writes one audit row');
select is((select jsonb_array_length(before_after -> 'archived_room_ids') from app.audit_events
            where action = 'site.archive' and created_at = now()), 1,
  'the site audit lists the rooms archived with it');
select is((select count(*) from app.business_entity_versions
            where entity_kind = 'room' and entity_id = (select id from ids where key = 'room_c1')),
  3::bigint, 'room versions include the archive done by the site command');

select * from finish();
rollback;
