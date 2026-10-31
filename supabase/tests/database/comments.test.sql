-- Comments (COMMENT-01-03) and their publication (ACAD-01): plain text up to
-- 1,000 characters per student and test/batch, independent publication from
-- scores and other targets, lock while published, batch archive/restore.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.sessions (id, user_id, created_at, updated_at)
select format('2a000000-0000-4000-8000-%s', lpad(n::text, 12, '0'))::uuid,
       format('00000000-0000-4000-8000-%s', lpad(n::text, 12, '0'))::uuid,
       now() - interval '1 minute', now()
  from generate_series(1, 3) n;
insert into auth.mfa_amr_claims (id, session_id, created_at, updated_at, authentication_method)
select gen_random_uuid(), s.id, now(), now(), 'password'
  from auth.sessions s where s.id::text like '2a000000%';

create function pg_temp.actor(p_user int)
returns void
language sql
as $$
  select set_config('request.jwt.claims', json_build_object(
    'sub', format('00000000-0000-4000-8000-%s', lpad(p_user::text, 12, '0')),
    'session_id', format('2a000000-0000-4000-8000-%s', lpad(p_user::text, 12, '0')),
    'role', 'authenticated')::text, true);
$$;

create temp table ids (key text primary key, id uuid);
create function pg_temp.id(p_key text) returns uuid language sql as $$ select id from ids where key = p_key $$;
create function pg_temp.keep(p_key text, p_dto jsonb) returns jsonb language sql as $$
  insert into ids values (p_key, (p_dto ->> 'id')::uuid)
  on conflict (key) do update set id = excluded.id
  returning p_dto
$$;
create function pg_temp.kind(p_target text) returns text language sql as $$
  select case when exists (select 1 from app.tests where id = pg_temp.id(p_target)) then 'test' else 'batch' end $$;
create function pg_temp.comment(p_target text, p_student text) returns jsonb language sql as $$
  select x -> 'comment' from jsonb_array_elements(
      api.get_comments(pg_temp.kind(p_target), pg_temp.id(p_target)) -> 'students') x
   where (x ->> 'studentId')::uuid = pg_temp.id(p_student) $$;
create function pg_temp.version(p_target text, p_student text) returns bigint language sql as $$
  select row_version from app.comments
   where student_id = pg_temp.id(p_student) and body is not null
     and (test_id = pg_temp.id(p_target) or batch_id = pg_temp.id(p_target)) $$;
create function pg_temp.save(p_target text, p_student text, p_body text) returns jsonb language sql as $$
  select api.save_comments(pg_temp.kind(p_target), pg_temp.id(p_target),
    jsonb_build_array(jsonb_build_object('studentId', pg_temp.id(p_student),
      'expectedVersion', pg_temp.version(p_target, p_student), 'body', p_body)))
$$;
create function pg_temp.publish(p_target text, p_student text, p_publish boolean) returns jsonb
language sql as $$
  select api.publish_comments(pg_temp.kind(p_target), pg_temp.id(p_target), pg_temp.id(p_student), p_publish) $$;
create function pg_temp.published(p_target text, p_student text) returns boolean language sql as $$
  select (pg_temp.comment(p_target, p_student) ->> 'published')::boolean $$;
create function pg_temp.batch_version(p_batch text) returns bigint language sql as $$
  select row_version from app.comment_batches where id = pg_temp.id(p_batch) $$;

select ok(not has_table_privilege('authenticated', 'app.comments', 'select')
       and not has_table_privilege('authenticated', 'app.comment_batches', 'insert')
       and not has_function_privilege('anon', 'api.save_comments(text, uuid, jsonb)', 'execute')
       and has_function_privilege('authenticated', 'api.publish_comments(text, uuid, uuid, boolean)', 'execute'),
  'comment tables are not exposed and anon cannot call comment RPCs');

-------------------------------------------------------------------------------
-- Fixture: class A (user 3 teacher), class B (user 3 assistant).
-------------------------------------------------------------------------------
select pg_temp.actor(1);
create temp table day as select app_private.business_date(now()) d;
select pg_temp.keep(k, api.create_class('Nhận xét ' || k, '10000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000011', d - 20, d + 20))
  from day, unnest(array['A', 'B']) k;
select api.create_class_assignment(pg_temp.id('A'), '00000000-0000-4000-8000-000000000003', 'teacher',
    d - 1, d + 10, null) from day;
select api.create_class_assignment(pg_temp.id('B'), '00000000-0000-4000-8000-000000000003', 'assistant',
    d - 1, d + 10, null) from day;
select pg_temp.keep(k, api.create_student('Nhận xét học sinh ' || k))
  from unnest(array['an', 'binh', 'left', 'later']) k;
select api.enroll_student(pg_temp.id('A'), pg_temp.id('an'), d - 15) from day;
select api.enroll_student(pg_temp.id('A'), pg_temp.id('binh'), d - 15) from day;
select api.enroll_student(pg_temp.id('A'), pg_temp.id('left'), d - 15, d - 3) from day;
select api.enroll_student(pg_temp.id('A'), pg_temp.id('later'), d + 5) from day;
select api.enroll_student(pg_temp.id('B'), pg_temp.id('an'), d - 15) from day;

select pg_temp.keep('test', api.create_test(pg_temp.id('A'), 'Giữa kỳ', d - 5, null,
  '{"scaleKind":"numeric","inputMode":"direct","maxScore":10}', null)) from day;
select pg_temp.keep('other', api.create_test(pg_temp.id('A'), 'Bài khác', d, null,
  '{"scaleKind":"numeric","inputMode":"direct","maxScore":10}', null)) from day;

-------------------------------------------------------------------------------
-- Batches (COMMENT-02): a name only, duplicates allowed.
-------------------------------------------------------------------------------
select throws_ok($$select api.create_comment_batch(pg_temp.id('A'), '   ')$$,
  'PT400', 'validation_failed', 'a batch needs a name');
select pg_temp.keep('week', api.create_comment_batch(pg_temp.id('A'), '  Tuần 1  '));
select pg_temp.keep('month', api.create_comment_batch(pg_temp.id('A'), 'Tuần 1'));
select is((select name from app.comment_batches where id = pg_temp.id('week')), 'Tuần 1',
  'the name is trimmed and duplicate names are allowed');
select is((select count(*)::int from app.audit_events where action = 'comment_batch.create'), 2,
  'creating a batch writes one audit');

-------------------------------------------------------------------------------
-- Rosters and text rules (COMMENT-01).
-------------------------------------------------------------------------------
select is((select jsonb_agg(x ->> 'fullName' order by x ->> 'fullName')
             from jsonb_array_elements(api.get_comments('test', pg_temp.id('test')) -> 'students') x),
  '["Nhận xét học sinh an","Nhận xét học sinh binh","Nhận xét học sinh left"]'::jsonb,
  'a test lists the students of its day, including one who has left since');
select is((select jsonb_agg(x ->> 'fullName' order by x ->> 'fullName')
             from jsonb_array_elements(api.get_comments('batch', pg_temp.id('week')) -> 'students') x),
  '["Nhận xét học sinh an","Nhận xét học sinh binh"]'::jsonb,
  'a batch lists the students in the class now');

select lives_ok($$select pg_temp.save('test', 'an', repeat('é', 1000))$$, '1,000 characters are accepted');
select throws_ok($$select pg_temp.save('test', 'binh', repeat('a', 1001))$$,
  'PT400', 'validation_failed', '1,001 characters are refused, never cut');
select is(char_length(pg_temp.comment('test', 'an') ->> 'body'), 1000, 'the text is kept whole');
select pg_temp.save('test', 'an', '<b>Tiến bộ</b>' || chr(10) || 'Cố gắng hơn');
select is(pg_temp.comment('test', 'an') ->> 'body', '<b>Tiến bộ</b>' || chr(10) || 'Cố gắng hơn',
  'markup is kept as plain text, lines included');
select is((pg_temp.comment('test', 'an') ->> 'rowVersion')::int, 2, 'editing gives a new version');
select is((select count(*)::int from app.business_entity_versions where entity_kind = 'comment'), 2,
  'each change keeps a comment version');
select pg_temp.save('test', 'an', '<b>Tiến bộ</b>' || chr(10) || 'Cố gắng hơn');
select is((pg_temp.comment('test', 'an') ->> 'rowVersion')::int, 2, 'unchanged text writes nothing');
select throws_ok($$select pg_temp.save('test', 'later', 'Không có mặt')$$,
  'PT400', 'validation_failed', 'a student outside the test day cannot get a comment');
select throws_ok($$select api.save_comments('test', pg_temp.id('test'),
    jsonb_build_array(jsonb_build_object('studentId', pg_temp.id('an'), 'expectedVersion', 1, 'body', 'x')))$$,
  'PT409', 'version_conflict', 'a stale version is refused');
select pg_temp.save('week', 'an', 'Chăm chỉ');
select pg_temp.save('week', 'binh', 'Cần tập trung');
select pg_temp.save('month', 'an', 'Đợt khác');
select is(pg_temp.comment('week', 'an') ->> 'body', 'Chăm chỉ', 'one comment per student and batch');
select is(pg_temp.comment('month', 'an') ->> 'body', 'Đợt khác', 'another batch keeps its own comment');

create temp table first_time as
  select commented_at from app.comments where batch_id = pg_temp.id('week') and student_id = pg_temp.id('an');
select pg_temp.save('week', 'an', 'Chăm chỉ, tiến bộ');
select is((select commented_at from app.comments where batch_id = pg_temp.id('week')
            and student_id = pg_temp.id('an')), (select commented_at from first_time),
  'editing keeps the time the comment was first written');

-------------------------------------------------------------------------------
-- Publication (ACAD-01): independent of scores, students and targets.
-------------------------------------------------------------------------------
select pg_temp.actor(3);
select api.save_test_results(pg_temp.id('test'), (select current_config_id from app.tests where id = pg_temp.id('test')),
  jsonb_build_array(jsonb_build_object('studentId', pg_temp.id('an'), 'expectedVersion', null,
    'entry', '{"absent":false,"score":8}'::jsonb)));
select api.publish_test_results(pg_temp.id('test'), pg_temp.id('an'), true);
select is(pg_temp.published('test', 'an'), false, 'publishing a score does not publish the comment');
select lives_ok($$select pg_temp.publish('test', 'an', true)$$, 'a teacher publishes one comment');
select is(pg_temp.published('test', 'an'), true, 'the comment is published');
select is((pg_temp.comment('test', 'an') ->> 'publishedByName'), 'Giáo viên Thử nghiệm', 'the publisher is kept');
select lives_ok($$select api.publish_test_results(pg_temp.id('test'), pg_temp.id('an'), false)$$,
  'unpublishing the score');
select is(pg_temp.published('test', 'an'), true, 'unpublishing a score keeps the comment published');
select throws_ok($$select pg_temp.save('test', 'an', 'Sửa')$$, 'PT409', 'comment_published',
  'a published comment cannot be changed');
select throws_ok($$select pg_temp.save('test', 'an', null)$$, 'PT409', 'comment_published',
  'a published comment cannot be cleared');
select throws_ok($$select pg_temp.publish('test', 'binh', true)$$, 'PT409', 'nothing_eligible',
  'a student without a comment cannot be published');

create temp table outcome as select api.publish_comments('batch', pg_temp.id('week'), null, true) o;
select is((select (o ->> 'changed')::int from outcome), 2, 'the batch publish takes every comment');
select is(pg_temp.published('month', 'an'), false, 'another batch is unchanged');
select is(pg_temp.published('week', 'an'), true, 'the batch comment is published');
select is((select (o -> 'missing')::jsonb from outcome), '[]'::jsonb, 'nobody is missing in that batch');
select is((select (api.publish_comments('test', pg_temp.id('test'), null, true) -> 'missing') -> 0 ->> 'fullName'),
  'Nhận xét học sinh binh', 'the class publish of a test lists students without a comment');
select is((select (o ->> 'changed')::int from (select api.publish_comments('test', pg_temp.id('other'), null, false) o) x),
  0, 'unpublishing an empty target changes nothing');
select throws_ok($$select api.publish_comments('test', pg_temp.id('other'), null, true)$$,
  'PT409', 'nothing_eligible', 'a class publish without any comment is refused');

select pg_temp.actor(1);
select lives_ok($$select api.update_comment_batch(pg_temp.id('week'), 'Tuần 1 (sửa)', pg_temp.batch_version('week'))$$,
  'the batch name changes while comments are published');
select is(pg_temp.published('week', 'an'), true, 'renaming keeps the publication');

-------------------------------------------------------------------------------
-- Rights.
-------------------------------------------------------------------------------
select pg_temp.actor(2);
select throws_ok($$select api.get_comments('test', pg_temp.id('test'))$$, 'PT403', 'forbidden',
  'receptionists cannot read comments');
select throws_ok($$select api.create_comment_batch(pg_temp.id('A'), 'Lễ tân')$$, 'PT403', 'forbidden',
  'receptionists cannot create batches');
select pg_temp.actor(3);
select pg_temp.keep('assist', api.create_comment_batch(pg_temp.id('B'), 'Trợ giảng'));
select lives_ok($$select pg_temp.save('assist', 'an', 'Ghi bởi trợ giảng')$$, 'an assistant enters comments');
select throws_ok($$select pg_temp.publish('assist', 'an', true)$$, 'PT403', 'forbidden',
  'an assistant cannot publish comments');
select throws_ok($$select api.archive_comment_batch(pg_temp.id('assist'), 'Không cần', pg_temp.batch_version('assist'))$$,
  'PT403', 'forbidden', 'an assistant cannot archive a batch');
select is((api.list_comment_batches(pg_temp.id('B'), false) ->> 'canManage')::boolean, false,
  'an assistant is told they cannot manage batches');

-------------------------------------------------------------------------------
-- Archive and restore (COMMENT-03).
-------------------------------------------------------------------------------
select pg_temp.actor(3);
select api.archive_comment_batch(pg_temp.id('week'), 'Tạo nhầm', pg_temp.batch_version('week'));
select is((select count(*)::int from app.comments where batch_id = pg_temp.id('week') and published_at is not null),
  0, 'archiving unpublishes every comment of the batch');
select is((select count(*)::int from app.comments where batch_id = pg_temp.id('week') and body is not null),
  2, 'the texts are kept');
select is((select count(*)::int from app.comments where test_id = pg_temp.id('test') and published_at is not null),
  1, 'comments of a test are not touched');
select is((select v.sanitized_snapshot ->> 'published_at' is not null from app.business_entity_versions v
            join app.comments c on c.id = v.entity_id
           where v.entity_kind = 'comment' and c.batch_id = pg_temp.id('week') and c.student_id = pg_temp.id('an')
           order by v.revision desc offset 1 limit 1), true, 'the state before archiving stays in history');
select is((select jsonb_array_length(api.list_comment_batches(pg_temp.id('A'), false) -> 'items')), 1,
  'an archived batch leaves the list');
select is((select jsonb_array_length(api.list_comment_batches(pg_temp.id('A'), true) -> 'items')), 2,
  'archived batches can be listed');
select throws_ok($$select pg_temp.save('week', 'an', 'Sau khi xóa')$$, 'PT409', 'invalid_state',
  'an archived batch cannot be written');
select lives_ok($$select api.restore_comment_batch(pg_temp.id('week'), pg_temp.batch_version('week'))$$,
  'a teacher restores the batch');
select is((select count(*)::int from app.comments where batch_id = pg_temp.id('week') and body is not null
             and published_at is null), 2, 'restored comments come back unpublished with the same ids');
select is((select count(*)::int from app.comments where batch_id = pg_temp.id('week')), 2,
  'no duplicate per student and batch');

-------------------------------------------------------------------------------
-- Test date (TEST-05), atomicity and revoked rights.
-------------------------------------------------------------------------------
select pg_temp.actor(1);
select pg_temp.save('test', 'left', 'Đã nghỉ sau bài này');
select throws_ok($$select api.update_test(pg_temp.id('test'), 'Giữa kỳ', d, null, row_version)
    from app.tests, day where id = pg_temp.id('test')$$,
  'PT409', 'test_date_excludes_results', 'a new date cannot leave out a student with a comment');

create function pg_temp.fail_audit() returns trigger language plpgsql as $$
begin raise exception 'audit_failure'; end $$;
create trigger zz_comment_fail_audit before insert on app.audit_events
  for each row execute function pg_temp.fail_audit();
select throws_ok($$select pg_temp.save('month', 'binh', 'Không lưu')$$, 'P0001', 'audit_failure',
  'audit failure aborts the save');
select throws_ok($$select api.archive_comment_batch(pg_temp.id('month'), 'Lỗi', pg_temp.batch_version('month'))$$,
  'P0001', 'audit_failure', 'audit failure aborts the archive');
drop trigger zz_comment_fail_audit on app.audit_events;
select is(pg_temp.comment('month', 'binh'), 'null'::jsonb, 'no comment is left behind');
select is((select deleted_at from app.comment_batches where id = pg_temp.id('month')), null,
  'the batch is not archived by the failed command');

select api.end_class_assignment(id, 'Thu hồi', row_version) from app.class_assignments
 where account_id = '00000000-0000-4000-8000-000000000003' and class_id = pg_temp.id('B');
select pg_temp.actor(3);
select throws_ok($$select pg_temp.save('assist', 'an', 'Sau khi thu hồi')$$, 'PT404', 'not_found',
  'a revoked assignment stops entering comments');

select * from finish();
rollback;
