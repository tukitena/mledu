-- Class records and participations (STU-03), transfer/re-enrollment
-- (CLASS-04), soft delete of students/records/classes ending participations
-- by event (STU-01, XLS-02, CLASS-05 base) and date extension rules (CLASS-03).
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Fixtures: 1 admin, 2 receptionist, 3 user; students S1–S3 from the seed.
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

create temp table today as select app_private.business_date(now()) as d;
create temp table ids (key text primary key, id uuid);
grant select on today to authenticated;
grant all on ids to authenticated;

-- Last participation of a student in a class, as the API returns it.
create function pg_temp.last_part(p_class text, p_student text)
returns jsonb
language sql
as $$
  select r -> 'participations' -> -1
    from jsonb_array_elements(api.list_class_students((select id from ids where key = p_class), true)) r
   where r #>> '{student,id}' = (select id::text from ids where key = p_student)
     and r ->> 'deleted' = 'false'
$$;
grant execute on function pg_temp.last_part(text, text) to authenticated;

insert into ids values
  ('s1', '13000000-0000-4000-8000-000000000001'),
  ('s2', '13000000-0000-4000-8000-000000000002'),
  ('s3', '13000000-0000-4000-8000-000000000003');

-------------------------------------------------------------------------------
-- Interval rules.
-------------------------------------------------------------------------------
select is(app_private.participation_period('2026-03-01', '2026-03-10', '2026-05-31', null, null),
  tstzrange('2026-03-01 00:00+07', '2026-03-10 00:00+07', '[)'),
  'the leave date is excluded from 00:00');
select is(app_private.participation_period('2026-03-01', null, '2026-05-31', null, null),
  tstzrange('2026-03-01 00:00+07', '2026-06-01 00:00+07', '[)'),
  'without a leave date the participation runs to the end of the class end date');
select is(app_private.participation_period('2026-03-01', null, '2026-05-31', null, '2026-04-02 15:00+07'),
  tstzrange('2026-03-01 00:00+07', '2026-04-02 15:00+07', '[)'),
  'an end event in the middle of a day ends it at that instant');
select is(app_private.participation_period('2026-04-02', null, '2026-05-31', '2026-04-02 15:00+07', null),
  tstzrange('2026-04-02 15:00+07', '2026-06-01 00:00+07', '[)'),
  'a re-added record starts no earlier than the deletion of the old one');

-------------------------------------------------------------------------------
-- Enrollment (STU-03).
-------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user(2);
insert into ids select 'math', (api.create_class('Toán TG', '10000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000011', (select d from today) - 30, (select d from today) + 60) ->> 'id')::uuid;
insert into ids select 'english', (api.create_class('Anh TG', '10000000-0000-4000-8000-000000000003',
  '10000000-0000-4000-8000-000000000012', (select d from today) - 30, (select d from today) + 60) ->> 'id')::uuid;

select is(api.enroll_student((select id from ids where key = 'math'), (select id from ids where key = 's1'),
            (select d from today) + 3) #>> '{participations,0,status}', 'not_started',
  'a future enrollment is not active early');
select is(api.enroll_student((select id from ids where key = 'math'), (select id from ids where key = 's2'),
            (select d from today) - 20, (select d from today) - 10) #>> '{participations,0,status}', 'ended',
  'a participation whose leave date passed has ended');
select is(api.enroll_student((select id from ids where key = 'math'), (select id from ids where key = 's3'),
            (select d from today) - 5, null, 'Học tốt') #>> '{participations,0,status}', 'active',
  'a participation between its dates is active');
select throws_ok(format($$select api.enroll_student(%L, %L, %L)$$, (select id from ids where key = 'math'),
    (select id from ids where key = 's3'), (select d from today) + 10),
  'PT409', 'participation_overlap', 'participations of one record never overlap');
select throws_ok(format($$select api.enroll_student(%L, %L, %L)$$, (select id from ids where key = 'english'),
    (select id from ids where key = 's3'), (select d from today) - 31),
  'PT409', 'outside_class_dates', 'the join date is not before the class opening date');
select throws_ok(format($$select api.enroll_student(%L, %L, %L, %L)$$, (select id from ids where key = 'english'),
    (select id from ids where key = 's3'), (select d from today), (select d from today)),
  'PT400', 'validation_failed', 'the leave date must be after the join date');

-- Re-enrollment in the same record after leaving (CLASS-04).
insert into ids select 's2_record', (r ->> 'id')::uuid
  from jsonb_array_elements(api.list_class_students((select id from ids where key = 'math'))) r
 where r #>> '{student,id}' = (select id::text from ids where key = 's2');
select is((select count(*)::int from jsonb_array_elements(
             api.enroll_student((select id from ids where key = 'math'), (select id from ids where key = 's2'),
               (select d from today) - 2) -> 'participations')), 2,
  're-enrolling adds a participation to the existing record');
select is((select count(*)::int from jsonb_array_elements(api.list_class_students((select id from ids where key = 'math'))) r
            where r #>> '{student,id}' = (select id::text from ids where key = 's2')), 1,
  'no second record is created for a re-enrollment');

-- Leave date: written once.
select is(api.set_participation_leave_date((pg_temp.last_part('math', 's3') ->> 'id')::uuid,
            (select d from today) + 20, 1) #>> '{participations,0,leaveDate}', ((select d from today) + 20)::text,
  'the first leave date is recorded');
select throws_ok(format($$select api.set_participation_leave_date(%L, %L, 2)$$,
    pg_temp.last_part('math', 's3') ->> 'id', (select d from today) + 25),
  'PT409', 'participation_dates_locked', 'a recorded leave date cannot be changed');
select is(api.set_participation_note((pg_temp.last_part('math', 's3') ->> 'id')::uuid, 'Cần kèm thêm', 2)
          #>> '{participations,0,note}', 'Cần kèm thêm', 'the class note stays editable');

-- Cancelling a future participation keeps it.
select throws_ok(format($$select api.cancel_participation(%L, 'Thử', 3)$$, pg_temp.last_part('math', 's3') ->> 'id'),
  'PT409', 'invalid_state', 'a started participation cannot be cancelled');
select is(api.cancel_participation((pg_temp.last_part('math', 's1') ->> 'id')::uuid, 'Đổi ý', 1)
          #>> '{participations,0,status}', 'cancelled', 'a future participation is cancelled, not deleted');

-- Users read/edit only assigned classes; management stays restricted.
select pg_temp.as_user(3);
select throws_ok(format($$select api.list_class_students(%L)$$, (select id from ids where key = 'math')),
  'PT404', 'not_found', 'a User without an assignment cannot read the class students');
select throws_ok(format($$select api.enroll_student(%L, %L, %L)$$, (select id from ids where key = 'english'),
    (select id from ids where key = 's1'), (select d from today)),
  'PT403', 'forbidden', 'a User cannot enroll students');
select pg_temp.as_user(2);
select lives_ok(format($$select api.create_class_assignment(%L, '00000000-0000-4000-8000-000000000003',
    'assistant', %L, %L)$$, (select id from ids where key = 'math'), (select d from today) - 1, (select d from today) + 30),
  'the User becomes an assistant of the class');
select pg_temp.as_user(3);
select is(jsonb_array_length(api.list_class_students((select id from ids where key = 'math'))), 3,
  'an assistant in effect reads the class students');
select lives_ok(format($$select api.set_participation_note(%L, 'Cần kèm thêm', 3)$$,
    pg_temp.last_part('math', 's3') ->> 'id'),
  'an assigned assistant may save the participation note (unchanged here)');
reset role;

-------------------------------------------------------------------------------
-- Class dates follow open participations only (CLASS-03).
-------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user(2);
select lives_ok(format($$select api.update_class(%L, 'Toán TG', '10000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000011', %L, %L, null, 1)$$, (select id from ids where key = 'math'),
    (select d from today) - 30, (select d from today) + 90), 'the class is extended');
reset role;
select is((select class_end_date from app.participations p
            join app.class_students r on r.id = p.class_student_id
           where r.class_id = (select id from ids where key = 'math') and r.student_id = (select id from ids where key = 's2')
             and p.leave_date is null), (select d from today) + 90,
  'an open participation follows the new end date');
select is((select class_end_date from app.participations p
            join app.class_students r on r.id = p.class_student_id
           where r.class_id = (select id from ids where key = 'math') and r.student_id = (select id from ids where key = 's2')
             and p.leave_date = (select d from today) - 10), (select d from today) + 60,
  'an ended participation keeps the end date it had');
set local role authenticated;
select pg_temp.as_user(2);
select lives_ok(format($$select api.enroll_student(%L, %L, %L)$$, (select id from ids where key = 'english'),
    (select id from ids where key = 's1'), (select d from today) + 40), 'a future enrollment in the other class');
select throws_ok(format($$select api.update_class(%L, 'Anh TG', '10000000-0000-4000-8000-000000000003',
    '10000000-0000-4000-8000-000000000012', %L, %L, null, 1)$$, (select id from ids where key = 'english'),
    (select d from today) - 30, (select d from today) + 30),
  'PT409', 'participations_outside_dates', 'shortening cannot leave a stored join date outside the class');
reset role;

-------------------------------------------------------------------------------
-- Removing from the class and adding again the same day (XLS-02, D07).
-------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user(2);
select is(api.soft_delete_class_student((select id from ids where key = 's2_record'), 'Nhập sai', 1)
          #>> '{participations,1,status}', 'ended', 'removing from the class ends the current participation now');
select is((select api.enroll_student((select id from ids where key = 'math'), (select id from ids where key = 's2'),
             (select d from today)) ->> 'id') <> (select id::text from ids where key = 's2_record'), true,
  'adding the student again creates a new record');
reset role;
select ok((select lower(p.effective_period) >= r_old.deleted_at
             from app.participations p
             join app.class_students r on r.id = p.class_student_id and r.deleted_at is null
             join app.class_students r_old on r_old.id = (select id from ids where key = 's2_record')
            where r.class_id = (select id from ids where key = 'math') and r.student_id = (select id from ids where key = 's2')),
  'the new record starts no earlier than the deletion of the old one, on the same day');
select is((select count(*)::int from app.class_students
            where class_id = (select id from ids where key = 'math') and student_id = (select id from ids where key = 's2')), 2,
  'the old record is kept for history');
select is(pg_temp.audits('class.student.soft_delete'), 1::bigint, 'removing from the class is audited once');

-------------------------------------------------------------------------------
-- Transfer (CLASS-04).
-------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user(2);
-- Target closed: nothing changes at the source.
select lives_ok(format($$select api.close_class(%L, 'Tạm dừng', 1)$$, (select id from ids where key = 'english')),
  'the target class is closed');
select throws_ok(format($$select api.transfer_student(%L, %L, %L, %L, null, %s)$$,
    pg_temp.last_part('math', 's2') ->> 'id', (select id from ids where key = 'english'),
    (select d from today) + 5, (select d from today) + 5, pg_temp.last_part('math', 's2') ->> 'rowVersion'),
  'PT409', 'class_closed', 'a closed class takes no new participations');
select is(pg_temp.last_part('math', 's2') ->> 'leaveDate', null,
  'a failed transfer leaves the source untouched');
select is(api.set_participation_note((pg_temp.last_part('english', 's1') ->> 'id')::uuid, 'Lớp đóng vẫn ghi chú', 1)
          #>> '{participations,0,note}', 'Lớp đóng vẫn ghi chú', 'notes stay editable while the class is closed');
select lives_ok(format($$select api.reopen_class(%L, 2)$$, (select id from ids where key = 'english')),
  'the class is reopened');
select is((api.transfer_student((pg_temp.last_part('math', 's2') ->> 'id')::uuid,
             (select id from ids where key = 'english'), (select d from today) + 5, (select d from today) + 5,
             'Chuyển từ Toán', (pg_temp.last_part('math', 's2') ->> 'rowVersion')::bigint) ->> 'className'),
  'Anh TG', 'the transfer adds the participation at the target');
select is(pg_temp.last_part('math', 's2') ->> 'leaveDate', ((select d from today) + 5)::text,
  'and records the leave date at the source in the same command');
reset role;
select is(pg_temp.audits('class.student.transfer'), 1::bigint, 'a transfer is one audited command');

-------------------------------------------------------------------------------
-- Student soft delete (STU-01) and restore (STU-02).
-------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user(2);
select lives_ok(format($$select api.enroll_student(%L, %L, %L)$$, (select id from ids where key = 'english'),
    (select id from ids where key = 's3'), (select d from today) + 50), 'S3 also has a future enrollment');
select is(api.student_delete_impact((select id from ids where key = 's3')) ->> 'activeParticipations', '1',
  'the impact lists the participation that ends');
select is(api.student_delete_impact((select id from ids where key = 's3')) ->> 'futureParticipations', '1',
  'and the future one that is cancelled');
select lives_ok(format($$select api.soft_delete_student(%L, 'Nghỉ hẳn', 1)$$, (select id from ids where key = 's3')),
  'the student is soft-deleted');
select is(pg_temp.last_part('math', 's3') ->> 'status', 'ended', 'its current participation ended now');
select is(pg_temp.last_part('english', 's3') ->> 'status', 'cancelled', 'its future participation is cancelled');
select is(pg_temp.last_part('english', 's3') ->> 'endKind', 'student_deleted', 'with the student deletion as cause');
select is((select count(*)::int from jsonb_array_elements(api.list_student_classes((select id from ids where key = 's3'))) r
            where r ->> 'deleted' = 'false'), 2, 'class records are kept, not deleted');
select throws_ok(format($$select api.enroll_student(%L, %L, %L)$$, (select id from ids where key = 'english'),
    (select id from ids where key = 's3'), (select d from today) + 52),
  'PT409', 'student_deleted', 'a deleted student cannot be enrolled');
select lives_ok(format($$select api.restore_student(%L, 'Nguyen Van An', 'Lê Thị Dung', array['0900000003'],
    '{}', null, null, null, 2)$$, (select id from ids where key = 's3')), 'the student is restored');
select is(pg_temp.last_part('math', 's3') ->> 'status', 'ended', 'restoring reopens no participation');
select is((select count(*)::int from jsonb_array_elements(
             api.enroll_student((select id from ids where key = 'english'), (select id from ids where key = 's3'),
               (select d from today) + 52) -> 'participations')), 2,
  'continuing needs a new participation in the kept record');
reset role;

-------------------------------------------------------------------------------
-- Class soft delete and restore (CLASS-05 base).
-------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user(2);
select lives_ok(format($$select api.soft_delete_class(%L, 'Gộp lớp', 2)$$, (select id from ids where key = 'math')),
  'the class is soft-deleted');
select is(pg_temp.last_part('math', 's2') ->> 'endKind', 'class_deleted', 'its open participations end with the deletion');
select pg_temp.as_user(3);
select throws_ok(format($$select api.list_class_students(%L)$$, (select id from ids where key = 'math')),
  'PT404', 'not_found', 'the assistant loses access to the deleted class at once');
select pg_temp.as_user(2);
select is(api.restore_class((select id from ids where key = 'math'), 3) ->> 'adminState', 'closed',
  'a restored class comes back closed');
select is(pg_temp.last_part('math', 's2') ->> 'status', 'cancelled',
  'restoring revives no participation (created and ended at the same transaction instant)');
select is(jsonb_array_length(api.list_class_students((select id from ids where key = 'math'), true)), 4,
  'every record of the class is kept');
reset role;

-------------------------------------------------------------------------------
-- Audit failure rolls the whole command back.
-------------------------------------------------------------------------------
-- A cancelled registration is still participation history: opening date locked.
set local role authenticated;
select pg_temp.as_user(2);
insert into ids select 'future', (api.create_class('Future history', '10000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000011', (select d from today) + 10, (select d from today) + 60) ->> 'id')::uuid;
select lives_ok(format($$select api.enroll_student(%L, %L, %L)$$,
  (select id from ids where key = 'future'), (select id from ids where key = 's1'), (select d from today) + 15),
  'register before class opening');
select lives_ok(format($$select api.cancel_participation(%L, 'Changed plan', 1)$$,
  pg_temp.last_part('future', 's1') ->> 'id'), 'cancel registration before class opening');
select throws_ok(format($$select api.update_class(%L, 'Future history', '10000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000011', %L, %L, null, 1)$$,
  (select id from ids where key = 'future'), (select d from today) + 11, (select d from today) + 60),
  'PT409', 'class_dates_locked', 'participation history locks the opening date, even if cancelled');

-- Extending an ended class never revives a participation.
insert into ids select 'past', (api.create_class('Past class', '10000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000011', (select d from today) - 20, (select d from today) - 1) ->> 'id')::uuid;
select lives_ok(format($$select api.enroll_student(%L, %L, %L)$$,
  (select id from ids where key = 'past'), (select id from ids where key = 's1'), (select d from today) - 10), 'record past participation');
select lives_ok(format($$select api.update_class(%L, 'Past class', '10000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000011', %L, %L, null, 1)$$,
  (select id from ids where key = 'past'), (select d from today) - 20, (select d from today) + 30), 'extend the class');
select is(pg_temp.last_part('past', 's1') ->> 'status', 'ended', 'extension preserves the ended interval');
select is(pg_temp.last_part('past', 's1') ->> 'classEndDate', ((select d from today) - 1)::text,
  'the participation retains its original class end date');
reset role;

-- Every participation in a re-added record observes its historical floor.
-- The first has ended; a backdated second one must not reach before deletion.
set local role authenticated;
select pg_temp.as_user(2);
select lives_ok(format($$select api.reopen_class(%L, 4)$$, (select id from ids where key = 'math')), 'reopen for historical-floor check');
select ok((api.enroll_student((select id from ids where key = 'math'), (select id from ids where key = 's2'),
  (select d from today) - 2) #>> '{participations,0,effectiveFrom}')::timestamptz >= now(),
  'a later backdated participation in a re-added record cannot predate its old record deletion');
reset role;

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
select throws_ok(format($$select api.soft_delete_class(%L, 'Thử', 3)$$, (select id from ids where key = 'english')),
  'P0001', 'injected audit failure', 'audit failure aborts the class deletion');
reset role;
select is((select count(*)::int from app.participations p
            join app.class_students r on r.id = p.class_student_id
           where r.class_id = (select id from ids where key = 'english') and p.end_kind = 'class_deleted'), 0,
  'no participation is ended when the deletion fails');

set local role authenticated;
select pg_temp.as_user(2);
select throws_ok(format($$select api.transfer_student(%L, %L, %L, %L, null, %s)$$,
  pg_temp.last_part('english', 's1') ->> 'id', (select id from ids where key = 'past'),
  (select d from today) + 41, (select d from today) + 1, pg_temp.last_part('english', 's1') ->> 'rowVersion'),
  'P0001', 'injected audit failure', 'audit failure rolls back transfer at both classes');
select is(pg_temp.last_part('english', 's1') ->> 'leaveDate', null, 'audit failure preserves source dates');
select is(jsonb_array_length((select r -> 'participations' from jsonb_array_elements(api.list_class_students(
  (select id from ids where key = 'past'))) r where r #>> '{student,id}' = (select id::text from ids where key = 's1'))),
  1, 'audit failure creates no target participation');
reset role;

select * from finish();
rollback;
