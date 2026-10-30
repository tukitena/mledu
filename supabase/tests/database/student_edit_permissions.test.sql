-- STU-04/STU-03 decision 2026-10-28: assignment-scoped edits, never management.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.sessions (id, user_id, created_at, updated_at)
select format('21000000-0000-4000-8000-%s', lpad(n::text, 12, '0'))::uuid,
       format('00000000-0000-4000-8000-%s', lpad(n::text, 12, '0'))::uuid,
       now() - interval '1 minute', now() from generate_series(1, 3) n;
insert into auth.mfa_amr_claims (id, session_id, created_at, updated_at, authentication_method)
select gen_random_uuid(), id, now(), now(), 'password'
  from auth.sessions where id::text like '21000000-0000-4000-8000-%';
create function pg_temp.as_user(n int) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object(
    'sub', format('00000000-0000-4000-8000-%s', lpad(n::text, 12, '0')),
    'session_id', format('21000000-0000-4000-8000-%s', lpad(n::text, 12, '0')),
    'role', 'authenticated')::text, true);
$$;
create temp table data (key text primary key, value jsonb);
grant all on data to authenticated;
create function pg_temp.today() returns date language sql as $$
  select (now() at time zone 'Asia/Ho_Chi_Minh')::date;
$$;
grant execute on function pg_temp.today() to authenticated;
create function pg_temp.id(key_ text) returns uuid language sql as $$
  select (value ->> 'id')::uuid from data where key = key_;
$$;
create function pg_temp.part(key_ text) returns uuid language sql as $$
  select (value #>> '{participations,0,id}')::uuid from data where key = key_;
$$;
create function pg_temp.edit(note_ text) returns jsonb language sql as $$
  select api.update_student(pg_temp.id('student'), 'Học sinh chung', 'Phụ huynh',
    array['+84 912 345 678'], array['0987654321'], date '2014-01-02', 'Trường mới', note_,
    (api.get_student(pg_temp.id('student')) ->> 'rowVersion')::bigint);
$$;
grant execute on function pg_temp.as_user(int), pg_temp.id(text), pg_temp.part(text), pg_temp.edit(text)
  to authenticated;

set local role authenticated;
select pg_temp.as_user(2);
insert into data values ('student', api.create_student('Học sinh gốc'));
insert into data values ('outside', api.create_student('Học sinh ngoài phạm vi'));
insert into data
select role_, api.create_class('Quyền sửa ' || role_,
  '10000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000011',
  pg_temp.today() - 30, pg_temp.today() + 60) from unnest(array['teacher','assistant','other']) role_;
insert into data
select role_ || '_record', api.enroll_student(pg_temp.id(role_), pg_temp.id('student'), pg_temp.today() - 5)
  from unnest(array['teacher','assistant','other']) role_;
insert into data
select role_ || '_assignment', api.create_class_assignment(pg_temp.id(role_),
  '00000000-0000-4000-8000-000000000003', role_, pg_temp.today() - 2, pg_temp.today() + 30)
  from unnest(array['teacher','assistant']) role_;

select pg_temp.as_user(3);
select is(api.get_student(pg_temp.id('student')) ->> 'canEdit', 'true', 'assigned User can edit shared profile');
select is(api.get_student(pg_temp.id('outside')) ->> 'canEdit', 'false', 'lookup alone gives no edit right');
select is(api.list_students('Học sinh gốc') #>> '{items,0,canEdit}', 'true', 'list exposes edit capability');
select is(api.list_class_students(pg_temp.id('teacher')) #>> '{0,canEdit}', 'true', 'teacher can edit this class record');
select is(api.list_class_students(pg_temp.id('assistant')) #>> '{0,canEdit}', 'true', 'assistant can edit this class record');
select lives_ok($$select pg_temp.edit('Sửa dùng chung')$$, 'teacher/assistant edits all shared fields');
select is(api.get_student(pg_temp.id('student')) ->> 'school', 'Trường mới', 'shared school is updated');
select is(api.get_student(pg_temp.id('student')) #>> '{parentPhones,0}', '0912345678', 'User edit uses phone normalization');
select lives_ok($$select api.set_participation_note(pg_temp.part('teacher_record'), 'Ghi chú GV', 1)$$,
  'teacher edits participation note');
select lives_ok($$select api.set_participation_note(pg_temp.part('assistant_record'), 'Ghi chú TG', 1)$$,
  'assistant edits participation note');
select throws_ok($$select api.set_participation_note(pg_temp.part('other_record'), 'Ngoài lớp', 1)$$,
  'PT403', 'forbidden', 'same student does not grant edits in another class');
select throws_ok($$select api.set_participation_leave_date(pg_temp.part('other_record'), pg_temp.today() + 2, 1)$$,
  'PT403', 'forbidden', 'same student does not grant leave date in another class');
select throws_ok($$select api.update_student(pg_temp.id('outside'), 'Ngoài phạm vi', null,
  '{}', '{}', null, null, null, 1)$$, 'PT403', 'forbidden', 'outside shared profile edit is refused');
select lives_ok($$select api.set_participation_leave_date(pg_temp.part('teacher_record'), pg_temp.today() + 2, 2)$$,
  'teacher writes the first leave date');
select lives_ok($$select api.set_participation_leave_date(pg_temp.part('assistant_record'), pg_temp.today() + 2, 2)$$,
  'assistant writes the first leave date');
select throws_ok($$select api.set_participation_note(pg_temp.part('teacher_record'), 'Stale', 1)$$,
  'PT409', 'version_conflict', 'stale participation version cannot overwrite newer data');
select throws_ok($$select api.update_student(pg_temp.id('student'), 'Stale', null,
  '{}', '{}', null, null, null, 1)$$, 'PT409', 'version_conflict', 'stale shared profile version is rejected');
select throws_ok($$select api.update_student(pg_temp.id('student'), 'Nguyễn Văn An', null,
  array['0900000001'], '{}', null, null, null, 2)$$,
  'PT409', 'duplicate_student', 'User edits preserve duplicate detection');

-- Management remains forbidden, including on records the User can edit.
select throws_ok($$select api.create_student('User creates')$$, 'PT403', 'forbidden', 'User cannot create student');
select throws_ok($$select api.soft_delete_student(pg_temp.id('student'), 'Xóa', 2)$$,
  'PT403', 'forbidden', 'User cannot delete student');
select throws_ok($$select api.restore_student(pg_temp.id('student'), 'Học sinh chung', null,
  '{}', '{}', null, null, null, 2)$$, 'PT403', 'forbidden', 'User cannot restore student');
select throws_ok($$select api.enroll_student(pg_temp.id('teacher'), pg_temp.id('outside'), pg_temp.today())$$,
  'PT403', 'forbidden', 'User cannot enroll another student');
select throws_ok($$select api.enroll_student(pg_temp.id('teacher'), pg_temp.id('student'), pg_temp.today() + 3)$$,
  'PT403', 'forbidden', 'User cannot re-enroll an editable student');
select throws_ok($$select api.soft_delete_class_student(pg_temp.id('teacher_record'), 'Xóa', 1)$$,
  'PT403', 'forbidden', 'User cannot archive class record');
select throws_ok($$select api.cancel_participation(pg_temp.part('teacher_record'), 'Hủy', 3)$$,
  'PT403', 'forbidden', 'User cannot cancel participation');
select throws_ok($$select api.transfer_student(pg_temp.part('teacher_record'), pg_temp.id('other'),
  pg_temp.today() + 2, pg_temp.today() + 3, null, 3)$$,
  'PT403', 'forbidden', 'User cannot transfer');

-- Every account type observes the same saved-date locks.
select throws_ok($$select api.set_participation_leave_date(pg_temp.part('teacher_record'), pg_temp.today() + 3, 3)$$,
  'PT409', 'participation_dates_locked', 'User cannot change saved leave date');
select throws_ok($$select api.set_participation_leave_date(pg_temp.part('teacher_record'), null, 3)$$,
  'PT409', 'participation_dates_locked', 'User cannot clear saved leave date');
select pg_temp.as_user(2);
select throws_ok($$select api.set_participation_leave_date(pg_temp.part('teacher_record'), pg_temp.today() + 3, 3)$$,
  'PT409', 'participation_dates_locked', 'Receptionist cannot change saved leave date');
select pg_temp.as_user(1);
select throws_ok($$select api.set_participation_leave_date(pg_temp.part('teacher_record'), pg_temp.today() + 3, 3)$$,
  'PT409', 'participation_dates_locked', 'Admin cannot change saved leave date');
select is(api.get_student(pg_temp.id('student')) ->> 'generalNote', 'Sửa dùng chung', 'manager sees the same master edit');
select is(api.list_class_students(pg_temp.id('other')) #>> '{0,student,fullName}', 'Học sinh chung',
  'unassigned class references the same master record');

-- Closed class still allows edits. Removing one assignment leaves the other valid.
select lives_ok($$select api.close_class(pg_temp.id('teacher'), 'Tạm đóng', 1)$$, 'close class');
select pg_temp.as_user(3);
select lives_ok($$select api.set_participation_note(pg_temp.part('teacher_record'), 'Lớp đóng', 3)$$,
  'closed class note remains editable');
select pg_temp.as_user(2);
select lives_ok($$select api.end_class_assignment(pg_temp.id('teacher_assignment'), 'Thu hồi', 1)$$, 'revoke teacher assignment');
select pg_temp.as_user(3);
select throws_ok($$select api.set_participation_note(pg_temp.part('teacher_record'), 'Token cũ', 4)$$,
  'PT403', 'forbidden', 'old JWT cannot edit after assignment revocation');
select lives_ok($$select pg_temp.edit('Trợ giảng vẫn sửa')$$, 'assistant alone can edit shared profile');
select pg_temp.as_user(2);
insert into data values ('audit_leave', api.enroll_student(pg_temp.id('assistant'), pg_temp.id('outside'), pg_temp.today() - 1));
reset role;

-- Audit failure must roll back values, contacts, versions and history for User writes.
create function app_private.test_student_edit_audit_failure() returns trigger language plpgsql as $$
begin raise exception 'injected audit failure'; end $$;
create trigger zz_student_edit_audit_failure before insert on app.audit_events
  for each row execute function app_private.test_student_edit_audit_failure();
create temp table saved_history as select count(*) n from app.business_entity_versions;
set local role authenticated;
select pg_temp.as_user(3);
select throws_ok($$select api.update_student(pg_temp.id('student'), 'Tên không được lưu', 'PH không lưu',
  array['0991234567'], array['0981234567'], '2015-02-03', 'Trường không lưu', 'Không được lưu', 3)$$,
  'P0001', 'injected audit failure', 'shared fields and contacts are atomic with audit');
select throws_ok($$select api.set_participation_note(pg_temp.part('assistant_record'), 'Không lưu', 3)$$,
  'P0001', 'injected audit failure', 'participation note is atomic with audit');
select throws_ok($$select api.set_participation_leave_date(pg_temp.part('audit_leave'), pg_temp.today() + 1, 1)$$,
  'P0001', 'injected audit failure', 'first leave date is atomic with audit');
select is(api.get_student(pg_temp.id('student')) ->> 'generalNote', 'Trợ giảng vẫn sửa', 'master note rolls back');
select is(api.get_student(pg_temp.id('student')) ->> 'rowVersion', '3', 'master version rolls back');
select is(api.get_student(pg_temp.id('student')) ->> 'fullName', 'Học sinh chung', 'master name rolls back');
select is(api.get_student(pg_temp.id('student')) #>> '{parentPhones,0}', '0912345678', 'parent contacts roll back');
select is(api.get_student(pg_temp.id('student')) #>> '{studentPhones,0}', '0987654321', 'student contacts roll back');
select is(api.list_class_students(pg_temp.id('assistant')) #>> '{0,participations,0,note}', 'Ghi chú TG', 'participation note rolls back');
reset role;
select is((select count(*) from app.business_entity_versions), (select n from saved_history), 'no history left by failed edits');
select is((select leave_date from app.participations where id = pg_temp.part('audit_leave')), null::date,
  'failed leave date remains unset');
select is((select row_version from app.participations where id = pg_temp.part('audit_leave')), 1::bigint,
  'failed leave date keeps its version');
drop trigger zz_student_edit_audit_failure on app.audit_events;

-- Current account status, expired/future assignments and revoked sessions are
-- evaluated at the write, irrespective of the old JWT's role claims.
update app.account_profiles set is_enabled = false where id = '00000000-0000-4000-8000-000000000003';
set local role authenticated;
select pg_temp.as_user(3);
select throws_ok($$select pg_temp.edit('Disabled')$$, 'PT401', 'account_disabled', 'disabled editor cannot write');
reset role;
update app.account_profiles set is_enabled = true where id = '00000000-0000-4000-8000-000000000003';
savepoint expired_assignment;
update app.class_assignments set end_date = pg_temp.today() - 1,
  effective_period = app_private.dated_period(start_date, pg_temp.today() - 1, ended_at)
where id = pg_temp.id('assistant_assignment');
set local role authenticated;
select pg_temp.as_user(3);
select is(api.get_student(pg_temp.id('student')) ->> 'canEdit', 'false', 'expired assignment gives no edit capability');
select throws_ok($$select pg_temp.edit('Expired')$$, 'PT403', 'forbidden', 'expired assignment cannot edit master');
select throws_ok($$select api.set_participation_note(pg_temp.part('assistant_record'), 'Expired', 3)$$,
  'PT403', 'forbidden', 'expired assignment cannot edit participation');
reset role;
rollback to expired_assignment;
savepoint future_assignment;
update app.class_assignments set start_date = pg_temp.today() + 1,
  effective_period = app_private.dated_period(pg_temp.today() + 1, end_date, ended_at)
where id = pg_temp.id('assistant_assignment');
set local role authenticated;
select pg_temp.as_user(3);
select throws_ok($$select pg_temp.edit('Future')$$, 'PT403', 'forbidden', 'future assignment cannot edit master');
reset role;
rollback to future_assignment;
savepoint revoked_session;
delete from auth.sessions where id = '21000000-0000-4000-8000-000000000003';
set local role authenticated;
select pg_temp.as_user(3);
select throws_ok($$select pg_temp.edit('Revoked')$$, 'PT401', 'session_invalid', 'revoked session cannot edit master');
select throws_ok($$select api.set_participation_note(pg_temp.part('assistant_record'), 'Revoked', 3)$$,
  'PT401', 'session_invalid', 'revoked session cannot edit participation');
reset role;
rollback to revoked_session;

-- Archived links, students and classes never confer edit rights.
set local role authenticated;
select pg_temp.as_user(2);
select lives_ok($$select api.soft_delete_class_student(pg_temp.id('assistant_record'), 'Lưu trữ', 1)$$, 'archive last assigned class record');
select pg_temp.as_user(3);
select is(api.get_student(pg_temp.id('student')) ->> 'canEdit', 'false', 'archived link confers no master edit');
select throws_ok($$select pg_temp.edit('Qua lưu trữ')$$, 'PT403', 'forbidden', 'archived link blocks master edit');
select throws_ok($$select api.set_participation_note(pg_temp.part('assistant_record'), 'Qua lưu trữ', 4)$$,
  'PT403', 'forbidden', 'archived class record cannot be edited by User');
select pg_temp.as_user(2);
insert into data values ('replacement', api.enroll_student(pg_temp.id('assistant'), pg_temp.id('student'), pg_temp.today()));
select lives_ok($$select api.soft_delete_student(pg_temp.id('student'), 'Lưu trữ tổng', 3)$$, 'archive master');
select pg_temp.as_user(3);
select throws_ok($$select api.set_participation_note(pg_temp.part('replacement'), 'Qua tổng đã xóa', 2)$$,
  'PT403', 'forbidden', 'archived master blocks participation edits');
select pg_temp.as_user(2);
select throws_ok($$select api.set_participation_note(pg_temp.part('replacement'), 'Qua tổng đã xóa', 2)$$,
  'PT409', 'invalid_state', 'manager also cannot edit participation of archived master');
select lives_ok($$select api.restore_student(pg_temp.id('student'), 'Học sinh chung', 'Phụ huynh',
  array['0912345678'], array['0987654321'], '2014-01-02', 'Trường mới', 'Trợ giảng vẫn sửa', 4)$$, 'restore master');
select lives_ok($$select api.soft_delete_class(pg_temp.id('assistant'), 'Xóa lớp', 1)$$, 'archive assigned class');
select pg_temp.as_user(3);
select is(api.get_student(pg_temp.id('student')) ->> 'canEdit', 'false', 'deleted class confers no master edit');
select throws_ok($$select pg_temp.edit('Qua lớp đã xóa')$$, 'PT403', 'forbidden', 'deleted class blocks writes');
reset role;

select * from finish();
rollback;
