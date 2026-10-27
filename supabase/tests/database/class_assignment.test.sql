-- Classes (CLASS-03) and assignments (CLASS-01/02): date locks, overlap rules
-- with end events, request-time class rights, and the assignment rules of
-- AUTH-04/07. Dates are relative to today's business date.
begin;
create extension if not exists pgtap with schema extensions;
select plan(54);

-- Seed fixtures: 1 admin, 2 receptionist, 3 user, 4 user (pending change), 5 disabled.
-- Account 9 is an extra User created here (its Auth user row only satisfies the FK).
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, created_at, updated_at,
                        confirmation_token, recovery_token, email_change, email_change_token_new)
values ('00000000-0000-0000-0000-000000000000', '00000000-0000-4000-8000-000000000009', 'authenticated',
        'authenticated', 'assistant9@example.com', '', now(), now(), '', '', '', '');
insert into app.account_profiles (id, login_email_key, full_name, account_type, must_change_password)
values ('00000000-0000-4000-8000-000000000009', 'assistant9@example.com', 'Trợ giảng Chín', 'user', false);

insert into auth.sessions (id, user_id, created_at, updated_at)
select format('20000000-0000-4000-8000-%s', lpad(n::text, 12, '0'))::uuid,
       format('00000000-0000-4000-8000-%s', lpad(n::text, 12, '0'))::uuid,
       now() - interval '1 minute', now()
  from unnest(array[1, 2, 3, 9]) n;
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

create function pg_temp.acct(p_user int)
returns uuid
language sql
immutable
as $$ select format('00000000-0000-4000-8000-%s', lpad(p_user::text, 12, '0'))::uuid $$;
grant execute on function pg_temp.acct(int) to authenticated;

create function pg_temp.audits(p_action text)
returns bigint
language sql
as $$ select count(*) from app.audit_events where action = p_action and created_at = now() $$;

create function pg_temp.error_of(p_sql text)
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
grant execute on function pg_temp.error_of(text) to authenticated;

create temp table ids (key text primary key, id uuid, version bigint);
grant all on ids to authenticated;
create temp table today as select app_private.business_date(now()) as d;
grant select on today to authenticated;

-------------------------------------------------------------------------------
-- Business time helpers.
-------------------------------------------------------------------------------
select is(app_private.dated_period('2026-01-01', '2026-01-31', null),
  tstzrange('2026-01-01 00:00+07', '2026-02-01 00:00+07', '[)'),
  'a dated interval runs from 00:00 of the first day to the end of the last day (Asia/Ho_Chi_Minh)');
select is(app_private.dated_period('2026-01-01', '2026-01-31', '2026-01-10 14:30+07'),
  tstzrange('2026-01-01 00:00+07', '2026-01-10 14:30+07', '[)'),
  'an end event in the middle of a day ends the interval at that instant');
select ok(isempty(app_private.dated_period('2026-03-01', '2026-03-31', '2026-02-15 09:00+07')),
  'an interval cancelled before it starts is empty');

-------------------------------------------------------------------------------
-- Classes (CLASS-03).
-------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user(3);
select throws_ok($$select api.create_class('Lớp X', '10000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000011', current_date, current_date + 30)$$,
  'PT403', 'forbidden', 'a User cannot create classes');
select pg_temp.as_user(2);
select throws_ok($$select api.create_class('Lớp X', '10000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000011', current_date, current_date - 1)$$,
  'PT400', 'validation_failed', 'the end date cannot be before the opening date');
select throws_ok($$select api.create_class('Lớp X', '10000000-0000-4000-8000-000000000011',
    '10000000-0000-4000-8000-000000000011', current_date, current_date + 30)$$,
  'PT400', 'validation_failed', 'the subject must be a subject entry');

-- A running class (started 20 days ago) and an upcoming one.
insert into ids select 'running', (c ->> 'id')::uuid, (c ->> 'rowVersion')::bigint
  from (select api.create_class('Toán 8 Thử', '10000000-0000-4000-8000-000000000001',
          '10000000-0000-4000-8000-000000000013', (select d from today) - 20, (select d from today) + 100,
          'Lớp thử nghiệm') as c) x;
insert into ids select 'upcoming', (c ->> 'id')::uuid, (c ->> 'rowVersion')::bigint
  from (select api.create_class('Văn 9 Sắp mở', '10000000-0000-4000-8000-000000000002',
          '10000000-0000-4000-8000-000000000014', (select d from today) + 10, (select d from today) + 60) as c) x;
select is((select api.get_class(id) ->> 'period' from ids where key = 'running'), 'running',
  'a class between its dates is running');
select is((select api.get_class(id) ->> 'adminState' from ids where key = 'upcoming'), 'open',
  'new classes are open');

select is((select api.update_class(id, 'Văn 9 Sắp mở', '10000000-0000-4000-8000-000000000002',
             '10000000-0000-4000-8000-000000000014', (select d from today) + 5, (select d from today) + 90,
             null, 1) ->> 'startDate' from ids where key = 'upcoming'),
  ((select d from today) + 5)::text, 'before any activity the opening date can change');
select throws_ok(format($$select api.update_class(%L, 'Toán 8 Thử', '10000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000013', %L, %L, 'Lớp thử nghiệm', 1)$$,
    (select id from ids where key = 'running'), (select d from today) - 19, (select d from today) + 100),
  'PT409', 'class_dates_locked', 'after the class started its opening date is locked');
select throws_ok(format($$select api.update_class(%L, 'Toán 8 Thử', '10000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000013', %L, %L, 'Lớp thử nghiệm', 1)$$,
    (select id from ids where key = 'running'), (select d from today) - 20, (select d from today) - 1),
  'PT409', 'class_dates_locked', 'the end date is never moved into the past');
select is((select api.update_class(id, 'Toán 8 Thử', '10000000-0000-4000-8000-000000000001',
             '10000000-0000-4000-8000-000000000013', (select d from today) - 20, (select d from today) + 120,
             'Lớp thử nghiệm', 1) ->> 'rowVersion' from ids where key = 'running'),
  '2', 'a started class can be extended');
select is((select api.update_class(id, 'Toán 8 Thử', '10000000-0000-4000-8000-000000000001',
             '10000000-0000-4000-8000-000000000013', (select d from today) - 20, (select d from today) + 120,
             'Lớp thử nghiệm', 2) ->> 'rowVersion' from ids where key = 'running'),
  '2', 'an unchanged edit creates no new version');
reset role;
select is(pg_temp.audits('class.update'), 2::bigint, 'only real class changes are audited');

-- An archived subject stays on the class; new classes cannot pick it.
update app.catalog_entries set deleted_at = now(), deleted_by = pg_temp.acct(1), deleted_reason = 'Thử'
 where id = '10000000-0000-4000-8000-000000000002';
set local role authenticated;
select pg_temp.as_user(2);
select is((select api.get_class(id) #>> '{subject,archived}' from ids where key = 'upcoming'), 'true',
  'a class keeps showing its archived subject');
select lives_ok(format($$select api.update_class(%L, 'Văn 9 Đổi tên', '10000000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000014', %L, %L, null, 2)$$, (select id from ids where key = 'upcoming'),
    (select d from today) + 5, (select d from today) + 90),
  'an unchanged archived subject does not block other edits');
select throws_ok($$select api.create_class('Văn mới', '10000000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000014', current_date, current_date + 30)$$,
  'PT400', 'validation_failed', 'new classes cannot use an archived subject');

-------------------------------------------------------------------------------
-- Assignments (CLASS-01/02).
-------------------------------------------------------------------------------
insert into ids select 'teacher3', (a ->> 'id')::uuid, (a ->> 'rowVersion')::bigint
  from (select api.create_class_assignment((select id from ids where key = 'running'), pg_temp.acct(3),
          'teacher', (select d from today) - 10, (select d from today) + 5, 'Đại số') as a) x;
select is((select api.list_class_assignments(id) -> 0 ->> 'status' from ids where key = 'running'), 'active',
  'an assignment between its dates is in effect');
select is(pg_temp.error_of(format($$select api.create_class_assignment(%L, %L, 'assistant', %L, %L)$$,
    (select id from ids where key = 'running'), pg_temp.acct(3), (select d from today) + 5, (select d from today) + 30)),
  'assignment_overlap ', 'one person has one role per class at a time');
insert into ids select 'assistant3_later', (a ->> 'id')::uuid, (a ->> 'rowVersion')::bigint
  from (select api.create_class_assignment((select id from ids where key = 'running'), pg_temp.acct(3),
          'assistant', (select d from today) + 6, (select d from today) + 30) as a) x;
select ok((select id from ids where key = 'assistant3_later') is not null,
  'the same person may take another role after the first one ends');
select is(pg_temp.error_of(format($$select api.create_class_assignment(%L, %L, 'teacher', %L, %L)$$,
    (select id from ids where key = 'running'), pg_temp.acct(2), (select d from today), (select d from today) + 5)),
  'account_not_assignable ', 'Receptionist accounts cannot be assigned');
select is(pg_temp.error_of(format($$select api.create_class_assignment(%L, %L, 'teacher', %L, %L)$$,
    (select id from ids where key = 'running'), pg_temp.acct(5), (select d from today), (select d from today) + 5)),
  'account_not_assignable ', 'disabled accounts cannot be assigned');
select is(pg_temp.error_of(format($$select api.create_class_assignment(%L, %L, 'teacher', %L, %L)$$,
    (select id from ids where key = 'running'), pg_temp.acct(1), (select d from today) - 30, (select d from today))),
  'outside_class_dates ', 'assignments stay within the class dates at creation');

-- CLASS-02: two teachers and two assistants with overlapping dates.
select lives_ok(format($$select api.create_class_assignment(%L, %L, 'teacher', %L, %L)$$,
    (select id from ids where key = 'running'), pg_temp.acct(1), (select d from today) - 5, (select d from today) + 50),
  'an Admin can be a second teacher');
insert into ids select 'assistant4', (a ->> 'id')::uuid, (a ->> 'rowVersion')::bigint
  from (select api.create_class_assignment((select id from ids where key = 'running'), pg_temp.acct(4),
          'assistant', (select d from today) - 5, (select d from today) + 50) as a) x;
insert into ids select 'assistant9', (a ->> 'id')::uuid, (a ->> 'rowVersion')::bigint
  from (select api.create_class_assignment((select id from ids where key = 'running'), pg_temp.acct(9),
          'assistant', (select d from today) - 5, (select d from today) + 50) as a) x;
select is((select jsonb_array_length(api.get_class(id) -> 'currentStaff') from ids where key = 'running'), 4,
  'two teachers and two assistants are in effect together');
reset role;

select is(app_private.class_role(pg_temp.acct(3), (select id from ids where key = 'running')), 'teacher',
  'the User teaches the class now');
select is(app_private.class_role(pg_temp.acct(3), (select id from ids where key = 'upcoming')), null,
  'no rights in a class without an assignment');

-- Rights are read at request time.
set local role authenticated;
select pg_temp.as_user(3);
select is((api.list_classes() -> 'items' -> 0 ->> 'name'), 'Toán 8 Thử',
  'a User lists only the classes it currently teaches');
select throws_ok(format($$select api.get_class(%L)$$, (select id from ids where key = 'upcoming')),
  'PT404', 'not_found', 'a User cannot open another class');
select is((select api.get_class(id) ->> 'myRole' from ids where key = 'running'), 'teacher',
  'the class tells the User its current role');
select throws_ok(format($$select api.end_class_assignment(%L, 'Thử', 1)$$, (select id from ids where key = 'assistant9')),
  'PT403', 'forbidden', 'teachers do not manage assignments');

-- Edits after the start keep role and start date; end dates never go back.
select pg_temp.as_user(2);
select is(pg_temp.error_of(format($$select api.update_class_assignment(%L, 'assistant', %L, %L, null, 1)$$,
    (select id from ids where key = 'teacher3'), (select d from today) - 10, (select d from today) + 5)),
  'assignment_locked ', 'the role of a started assignment is history');
select is(pg_temp.error_of(format($$select api.update_class_assignment(%L, 'teacher', %L, %L, null, 1)$$,
    (select id from ids where key = 'teacher3'), (select d from today) - 10, (select d from today) - 1)),
  'assignment_locked ', 'a started assignment cannot be cut into the past');
select is(pg_temp.error_of(format($$select api.update_class_assignment(%L, 'teacher', %L, %L, null, 1)$$,
    (select id from ids where key = 'teacher3'), (select d from today) - 10, (select d from today) + 10)),
  'assignment_overlap ', 'extending into the same person''s next assignment is refused');
select is((select api.update_class_assignment(id, 'teacher', (select d from today) - 10, (select d from today) + 5,
             'Hình học', 1) ->> 'subjectNote' from ids where key = 'teacher3'),
  'Hình học', 'the teaching speciality stays editable');

-- Ending one assignment early leaves the others untouched (CLASS-02).
select is((select api.end_class_assignment(id, 'Nghỉ dạy', 2) ->> 'status' from ids where key = 'teacher3'),
  'ended', 'Receptionist ends an assignment early');
select is((select api.end_class_assignment(id, 'Không cần nữa', 1) ->> 'status'
             from ids where key = 'assistant3_later'),
  'cancelled', 'a future assignment is cancelled instead');
select is((select jsonb_array_length(api.get_class(id) -> 'currentStaff') from ids where key = 'running'), 3,
  'other staff keep their assignments');
select throws_ok(format($$select api.update_class_assignment(%L, 'teacher', %L, %L, null, 3)$$,
    (select id from ids where key = 'teacher3'), (select d from today) - 10, (select d from today) + 20),
  'PT409', 'invalid_state', 'an ended assignment never comes back by moving its end date');
reset role;
select is(app_private.class_role(pg_temp.acct(3), (select id from ids where key = 'running')), null,
  'the early end removes the class rights at once');
select is((select count(*) from app.business_entity_versions
            where entity_kind = 'class_assignment' and entity_id = (select id from ids where key = 'teacher3')),
  3::bigint, 'assignment history is kept');

-------------------------------------------------------------------------------
-- AUTH-04/07.
-------------------------------------------------------------------------------
-- Account 9 assists now and has another future assignment in the upcoming class.
set local role authenticated;
select pg_temp.as_user(2);
insert into ids select 'future9', (a ->> 'id')::uuid, (a ->> 'rowVersion')::bigint
  from (select api.create_class_assignment((select id from ids where key = 'upcoming'), pg_temp.acct(9),
          'teacher', (select d from today) + 6, (select d from today) + 40) as a) x;
select pg_temp.as_user(1);
select is(pg_temp.error_of(format($$select api.soft_delete_account(%L, 'Nghỉ việc', 1)$$, pg_temp.acct(9))),
  'assignment_in_effect Toán 8 Thử', 'an account with an assignment in effect cannot be deleted');
select is(pg_temp.error_of(format($$select api.set_account_type(%L, 'receptionist', 1)$$, pg_temp.acct(9))),
  'assignment_in_effect Toán 8 Thử', 'nor become a Receptionist');
select is((select api.list_class_assignments(id) -> 0 ->> 'status' from ids where key = 'upcoming'),
  'not_started', 'a refused command does not cancel future assignments');

select pg_temp.as_user(2);
select lives_ok(format($$select api.end_class_assignment(%L, 'Chuyển công tác', 1)$$,
    (select id from ids where key = 'assistant9')), 'the assignment in effect is ended first');
select pg_temp.as_user(1);
select is(api.soft_delete_account(pg_temp.acct(9), 'Nghỉ việc', 1) ->> 'status', 'deleted',
  'with only a future assignment left, the account is deleted');
select is((select a ->> 'endKind' from jsonb_array_elements(
             (select api.list_class_assignments(id) from ids where key = 'upcoming')) a), 'cancelled_account_deleted',
  'its future assignment is cancelled in the same command');
select is(api.restore_account(pg_temp.acct(9), 2) ->> 'status', 'active', 'restoring the account works');
select is((select a ->> 'status' from jsonb_array_elements(
             (select api.list_class_assignments(id) from ids where key = 'upcoming')) a), 'cancelled',
  'restoring the account does not restore cancelled assignments');

-- AUTH-07: the pending User (4) assists now; ending it allows the change.
select pg_temp.as_user(2);
select lives_ok(format($$select api.end_class_assignment(%L, 'Đổi vị trí', 1)$$,
    (select id from ids where key = 'assistant4')), 'ending the current assignment of account 4');
select pg_temp.as_user(1);
select is(api.set_account_type(pg_temp.acct(4), 'receptionist', 1) ->> 'accountType', 'receptionist',
  'User -> Receptionist once no assignment is in effect');
reset role;
select is(pg_temp.audits('class.assignment.auto_cancel'), 1::bigint,
  'automatic cancellations are audited with the account command');

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
select pg_temp.as_user(2);
select throws_ok(format($$select api.create_class_assignment(%L, %L, 'teacher', %L, %L)$$,
    (select id from ids where key = 'upcoming'), pg_temp.acct(3), (select d from today) + 41, (select d from today) + 45),
  'P0001', 'injected audit failure', 'audit failure aborts the assignment');
reset role;
select is((select count(*) from app.class_assignments
            where class_id = (select id from ids where key = 'upcoming') and account_id = pg_temp.acct(3)),
  0::bigint, 'no assignment is left behind');

select * from finish();
rollback;
