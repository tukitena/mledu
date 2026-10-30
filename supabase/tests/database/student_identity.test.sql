-- Student master records (STU-04/01/02): normalization, duplicate rules
-- (same name key + shared parent phone, active or archived), parent phone
-- requirement, permissions, soft delete/restore and audit atomicity.
begin;
create extension if not exists pgtap with schema extensions;
select plan(45);

-- Seed fixtures: 1 admin, 2 receptionist, 3 user; students HS000001–3.
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

create temp table ids (key text primary key, id uuid, code text);
grant all on ids to authenticated;

-- Error detail (codes of the conflicting students) raised by a statement.
create function pg_temp.conflict_detail(p_sql text)
returns text
language plpgsql
as $$
declare
  v_message text;
  v_detail text;
begin
  execute p_sql;
  return null;
exception when others then
  get stacked diagnostics v_message = message_text, v_detail = pg_exception_detail;
  return v_message || ' ' || coalesce((select string_agg(e ->> 'message', ',')
                                         from jsonb_array_elements(nullif(v_detail, '')::jsonb) e), '');
end
$$;
grant execute on function pg_temp.conflict_detail(text) to authenticated;

-------------------------------------------------------------------------------
-- Phone and name keys (STU-04).
-------------------------------------------------------------------------------
select is(app_private.phone_key('0912 345 678'), app_private.phone_key('+84 912345678'),
  '0912 345 678 and +84 912345678 have the same key');
select is(app_private.phone_key('0084 (912) 345-678'), '0912345678', '0084 and separators are normalized');
select is(app_private.phone_key('+44 20.7946.0958'), '+442079460958', 'foreign numbers keep + and digits');
select is(app_private.phone_key('02812345678'), '02812345678', '11-digit Vietnamese numbers are accepted');
select throws_ok($$select app_private.phone_key('09l2345678')$$, 'PT400', 'validation_failed',
  'letters are never turned into digits');
select throws_ok($$select app_private.phone_key('091234')$$, 'PT400', 'validation_failed',
  'too short numbers are refused');
select is(app_private.phone_keys(array['0911 111 111', '+84911111111', ' ', '0922222222']),
  array['0911111111', '0922222222'], 'duplicate numbers in one list are kept once, blanks dropped');

-------------------------------------------------------------------------------
-- Permissions and lookup.
-------------------------------------------------------------------------------
select ok(not has_table_privilege('authenticated', 'app.students', 'select')
       and not has_table_privilege('anon', 'app.student_contacts', 'select'),
  'student tables are not exposed to clients');

set local role authenticated;
select pg_temp.as_user(3);
select throws_ok($$select api.create_student('Học sinh Mới')$$, 'PT403', 'forbidden',
  'a User cannot create students');
select is(api.list_students('NGUYEN VAN AN') ->> 'total', '2',
  'every internal account searches names without accents or case');
select is(api.list_students('+84 900 000 001') #>> '{items,0,code}', 'HS000001',
  'phone search uses the phone key');
select is(api.list_students('hs000002') ->> 'total', '0',
  'student codes are internal identifiers, not search keys');
select throws_ok($$select api.list_students(null, 'deleted')$$, 'PT403', 'forbidden',
  'a User cannot list archived students');

-------------------------------------------------------------------------------
-- Duplicate rules.
-------------------------------------------------------------------------------
select pg_temp.as_user(2);
insert into ids select 'minh', (s ->> 'id')::uuid, s ->> 'code'
  from (select api.create_student('Phạm  Minh') as s) c;
select ok((select code from ids where key = 'minh') ~ '^HS[0-9]{6}$',
  'a unique name is created without any phone and gets a code');
select is(pg_temp.conflict_detail($$select api.create_student('nguyen van an')$$),
  'parent_phone_required HS000001,HS000003',
  'an existing name key requires a parent phone and names the other records');
select is(pg_temp.conflict_detail(
  $$select api.create_student('Nguyễn Văn An', p_parent_phones => array['+84 900 000 001'])$$),
  'duplicate_student HS000001', 'same name key and shared parent phone is refused');
select is(pg_temp.conflict_detail(
  $$select api.create_student('Nguyễn Văn An', p_student_phones => array['0900000001'])$$),
  'parent_phone_required HS000001,HS000003', 'a student phone does not replace the parent phone');
insert into ids select 'an3', (s ->> 'id')::uuid, s ->> 'code'
  from (select api.create_student('NGUYỄN văn an', p_parent_phones => array['0900000009']) as s) c;
select ok((select id from ids where key = 'an3') is not null,
  'same name with a different parent phone is a different student');
select lives_ok($$select api.create_student('Trần Văn Khác', p_parent_phones => array['0900000001'])$$,
  'different names may share a parent phone');
select is(jsonb_array_length(api.create_student('Đỗ Hạnh',
            p_parent_phones => array['0911 111 111', '+84911111111']) -> 'parentPhones'), 1,
  'duplicate phones of one student are stored once');

-- A record created without phones while unique stays valid after a namesake arrives.
insert into ids select 'minh2', (s ->> 'id')::uuid, s ->> 'code'
  from (select api.create_student('Pham Minh', p_parent_phones => array['0933333333']) as s) c;
select is(api.update_student((select id from ids where key = 'minh'), 'Phạm  Minh', null, '{}', '{}',
            null, 'THCS Mới', null, 1) ->> 'school', 'THCS Mới',
  'the original phoneless record keeps being edited without adding a phone');
select is(jsonb_array_length(api.update_student((select id from ids where key = 'minh'), 'Phạm  Minh', null,
            array['0944444444'], '{}', null, 'THCS Mới', null, 2) -> 'parentPhones'), 1,
  'a parent phone can be added later');
select is(pg_temp.conflict_detail(format($$select api.update_student(%L, 'Phạm  Minh', null, '{}', '{}',
            null, 'THCS Mới', null, 3)$$, (select id from ids where key = 'minh'))),
  'parent_phone_required ' || (select code from ids where key = 'minh2'),
  'the last parent phone cannot be removed while a namesake exists');
select is(pg_temp.conflict_detail(format($$select api.update_student(%L, 'Pham Minh', null,
            array['0933333333'], '{}', null, null, null, 3)$$, (select id from ids where key = 'minh'))),
  'duplicate_student ' || (select code from ids where key = 'minh2'),
  'an edit cannot take a namesake''s parent phone');
select is(pg_temp.conflict_detail(format($$select api.update_student(%L, 'Trần Thị Bích', null, '{}', '{}',
            null, null, null, 1)$$, (select id from ids where key = 'an3'))),
  'parent_phone_required HS000002', 'renaming to an existing name key needs a parent phone');
select throws_ok(format($$select api.update_student(%L, 'X', null, '{}', '{}', null, null, null, 9)$$,
    (select id from ids where key = 'an3')), 'PT409', 'version_conflict', 'stale versions are refused');
select throws_ok($$select api.create_student('Tương Lai', p_birth_date => current_date + 400)$$,
  'PT400', 'validation_failed', 'birth dates cannot be in the future');
select throws_ok($$select api.create_student('Ghi chú dài', p_general_note => repeat('a', 1001))$$,
  'PT400', 'validation_failed', 'general notes are limited to 1,000 characters');
reset role;

select is((select count(*) from app.business_entity_versions
            where entity_kind = 'student' and entity_id = (select id from ids where key = 'minh')),
  3::bigint, 'each successful change keeps a version');

-- An edit that changes nothing writes neither a version nor an audit row.
set local role authenticated;
select pg_temp.as_user(2);
select is(api.update_student((select id from ids where key = 'minh'), 'Phạm  Minh', null,
            array['0944444444'], '{}', null, 'THCS Mới', null, 3) ->> 'rowVersion', '3',
  'an unchanged edit returns the current version');
reset role;
select is(pg_temp.audits('student.update'), 2::bigint, 'only real edits are audited');

-------------------------------------------------------------------------------
-- Soft delete (STU-01) and restore (STU-02).
-------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user(2);
select throws_ok(format($$select api.soft_delete_student(%L, '  ', 1)$$, (select id from ids where key = 'an3')),
  'PT400', 'validation_failed', 'soft delete needs a reason');
select is(api.soft_delete_student((select id from ids where key = 'an3'), 'Chuyển trường', 1) ->> 'status',
  'deleted', 'Receptionist soft-deletes a student');
select is(pg_temp.conflict_detail(
  $$select api.create_student('Nguyen Van An', p_parent_phones => array['0900000009'])$$),
  'duplicate_student_archived ' || (select code from ids where key = 'an3'),
  'matching an archived student points to restoring it');
select ok(not exists (select 1 from jsonb_array_elements(api.list_students('nguyen van an') -> 'items') i
                       where i ->> 'id' = (select id::text from ids where key = 'an3')),
  'archived students leave the active list');
select is(api.list_students('nguyen van an', 'deleted') #>> '{items,0,code}',
  (select code from ids where key = 'an3'), 'Receptionist lists archived students');
select pg_temp.as_user(3);
select throws_ok(format($$select api.get_student(%L)$$, (select id from ids where key = 'an3')),
  'PT404', 'not_found', 'a User cannot open archived students');
select pg_temp.as_user(2);
select is(pg_temp.conflict_detail(format($$select api.restore_student(%L, 'Nguyễn Văn An', null,
            array['0900000001'], '{}', null, null, null, 2)$$, (select id from ids where key = 'an3'))),
  'duplicate_student HS000001', 'restore runs the duplicate checks on the data being restored');
select is(api.restore_student((select id from ids where key = 'an3'), 'Nguyễn Văn An', null,
            array['0900000009'], '{}', null, null, null, 2) ->> 'code',
  (select code from ids where key = 'an3'), 'restore keeps the student code');
reset role;

select is((select count(*) from app.students where name_key = 'nguyen van an'), 3::bigint,
  'restore creates no new student');
select is(pg_temp.audits('student.soft_delete') + pg_temp.audits('student.restore'), 2::bigint,
  'soft delete and restore are audited');

-------------------------------------------------------------------------------
-- Audit failure rolls the command back.
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
select pg_temp.as_user(1);
select throws_ok($$select api.create_student('Không Được Lưu', p_parent_phones => array['0955555555'])$$,
  'P0001', 'injected audit failure', 'audit failure aborts creating a student');
select throws_ok(format($$select api.soft_delete_student(%L, 'Thử', 3)$$, (select id from ids where key = 'an3')),
  'P0001', 'injected audit failure', 'audit failure aborts the soft delete');
reset role;
select is((select count(*) from app.students s where s.name_key = 'khong duoc luu'), 0::bigint,
  'no student or contact is left behind');
select is((select deleted_at is null from app.students where id = (select id from ids where key = 'an3')),
  true, 'the student stays active when its soft delete fails');

select * from finish();
rollback;
