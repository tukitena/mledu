-- Archiving and restoring a whole test (TEST-06): rights, automatic
-- unpublishing of scores and test comments, kept data and history, restore
-- unpublished with the same ids, other tests/batches untouched, atomicity.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.sessions (id, user_id, created_at, updated_at)
select format('2b000000-0000-4000-8000-%s', lpad(n::text, 12, '0'))::uuid,
       format('00000000-0000-4000-8000-%s', lpad(n::text, 12, '0'))::uuid,
       now() - interval '1 minute', now()
  from generate_series(1, 3) n;
insert into auth.mfa_amr_claims (id, session_id, created_at, updated_at, authentication_method)
select gen_random_uuid(), s.id, now(), now(), 'password'
  from auth.sessions s where s.id::text like '2b000000%';

create function pg_temp.actor(p_user int)
returns void
language sql
as $$
  select set_config('request.jwt.claims', json_build_object(
    'sub', format('00000000-0000-4000-8000-%s', lpad(p_user::text, 12, '0')),
    'session_id', format('2b000000-0000-4000-8000-%s', lpad(p_user::text, 12, '0')),
    'role', 'authenticated')::text, true);
$$;

create temp table ids (key text primary key, id uuid);
create function pg_temp.id(p_key text) returns uuid language sql as $$ select id from ids where key = p_key $$;
create function pg_temp.keep(p_key text, p_dto jsonb) returns jsonb language sql as $$
  insert into ids values (p_key, (p_dto ->> 'id')::uuid)
  on conflict (key) do update set id = excluded.id
  returning p_dto
$$;
create function pg_temp.v(p_test text) returns bigint language sql as $$
  select row_version from app.tests where id = pg_temp.id(p_test) $$;
create function pg_temp.save(p_test text, p_student text, p_entry jsonb) returns jsonb language sql as $$
  select api.save_test_results(pg_temp.id(p_test),
    (select current_config_id from app.tests where id = pg_temp.id(p_test)),
    jsonb_build_array(jsonb_build_object('studentId', pg_temp.id(p_student), 'expectedVersion',
      (select row_version from app.test_results where test_id = pg_temp.id(p_test)
          and student_id = pg_temp.id(p_student) and deleted_at is null),
      'entry', p_entry)))
$$;

select ok(not has_function_privilege('anon', 'api.archive_test(uuid, text, bigint)', 'execute')
       and has_function_privilege('authenticated', 'api.restore_test(uuid, bigint)', 'execute'),
  'anon cannot archive or restore tests');

-------------------------------------------------------------------------------
-- Fixture: class A (user 3 teacher), class B (user 3 assistant).
-------------------------------------------------------------------------------
select pg_temp.actor(1);
create temp table day as select app_private.business_date(now()) d;
select pg_temp.keep(k, api.create_class('Xóa bài ' || k, '10000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000011', d - 20, d + 20))
  from day, unnest(array['A', 'B']) k;
select api.create_class_assignment(pg_temp.id('A'), '00000000-0000-4000-8000-000000000003', 'teacher',
    d - 1, d + 10, null) from day;
select api.create_class_assignment(pg_temp.id('B'), '00000000-0000-4000-8000-000000000003', 'assistant',
    d - 1, d + 10, null) from day;
select pg_temp.keep(k, api.create_student('Xóa bài học sinh ' || k)) from unnest(array['an', 'binh']) k;
select api.enroll_student(c, pg_temp.id(k), d - 15)
  from day, unnest(array['an', 'binh']) k, unnest(array[pg_temp.id('A'), pg_temp.id('B')]) c;

select pg_temp.keep('t', api.create_test(pg_temp.id('A'), 'Giữa kỳ', d, null,
  '{"scaleKind":"numeric","inputMode":"components","maxScore":7,"showComponents":true,
    "components":[{"name":"Nghe","maxScore":3},{"name":"Viết","maxScore":4}]}', null)) from day;
select pg_temp.keep('other', api.create_test(pg_temp.id('A'), 'Bài khác', d, null,
  '{"scaleKind":"numeric","inputMode":"direct","maxScore":10}', null)) from day;
select pg_temp.keep('assist', api.create_test(pg_temp.id('B'), 'Lớp trợ giảng', d, null,
  '{"scaleKind":"numeric","inputMode":"direct","maxScore":10}', null)) from day;
select pg_temp.keep('batch', api.create_comment_batch(pg_temp.id('A'), 'Tuần 1'));

select pg_temp.save('t', 'an', '{"absent":false,"components":{"c1":3,"c2":4}}');
select pg_temp.save('t', 'binh', '{"absent":true}');
select pg_temp.save('other', 'an', '{"absent":false,"score":9}');
select api.save_comments('test', pg_temp.id('t'), jsonb_build_array(
  jsonb_build_object('studentId', pg_temp.id('an'), 'expectedVersion', null, 'body', 'Tốt')));
select api.save_comments('batch', pg_temp.id('batch'), jsonb_build_array(
  jsonb_build_object('studentId', pg_temp.id('an'), 'expectedVersion', null, 'body', 'Chăm')));
select api.publish_test_results(pg_temp.id('t'), null, true);
select api.publish_test_results(pg_temp.id('other'), null, true);
select api.publish_comments('test', pg_temp.id('t'), null, true);
select api.publish_comments('batch', pg_temp.id('batch'), null, true);

select is((select jsonb_build_object('r', o ->> 'resultCount', 'p', o ->> 'publishedCount',
                                     'c', o ->> 'commentCount', 'pc', o ->> 'publishedCommentCount')
             from (select api.get_test(pg_temp.id('t')) o) x),
  '{"r":"2","p":"2","c":"1","pc":"1"}'::jsonb, 'the test shows what archiving affects');

-------------------------------------------------------------------------------
-- Rights.
-------------------------------------------------------------------------------
select pg_temp.actor(2);
select throws_ok($$select api.archive_test(pg_temp.id('t'), 'Lễ tân', pg_temp.v('t'))$$,
  'PT403', 'forbidden', 'receptionists cannot archive a test');
select pg_temp.actor(3);
select throws_ok($$select api.archive_test(pg_temp.id('assist'), 'Trợ giảng', pg_temp.v('assist'))$$,
  'PT403', 'forbidden', 'an assistant cannot archive a test, even without results');
select is((api.list_class_tests(pg_temp.id('B')) ->> 'canArchive')::boolean, false,
  'an assistant is told they cannot archive');
select throws_ok($$select api.archive_test(pg_temp.id('t'), '  ', pg_temp.v('t'))$$,
  'PT400', 'validation_failed', 'a reason is required');
select throws_ok($$select api.archive_test(pg_temp.id('t'), 'Cũ', pg_temp.v('t') - 1)$$,
  'PT409', 'version_conflict', 'a stale version is refused');

-------------------------------------------------------------------------------
-- Archive: automatic unpublishing, data kept (ACAD-01 exception).
-------------------------------------------------------------------------------
select lives_ok($$select api.archive_test(pg_temp.id('t'), 'Nhập nhầm bài', pg_temp.v('t'))$$,
  'a teacher archives a test with published scores and comments');
select is((select count(*)::int from app.test_results where test_id = pg_temp.id('t') and published_at is not null),
  0, 'every score of the test is unpublished');
select is((select count(*)::int from app.comments where test_id = pg_temp.id('t') and published_at is not null),
  0, 'every comment of the test is unpublished');
select is((select count(*)::int from app.test_results where test_id = pg_temp.id('t') and deleted_at is null),
  2, 'scores and Absent are kept');
select is((select count(*)::int from app.component_results x join app.test_results r on r.id = x.result_id
            where r.test_id = pg_temp.id('t')), 2, 'component values are kept');
select is((select body from app.comments where test_id = pg_temp.id('t')), 'Tốt', 'the comment text is kept');
select is((select count(*)::int from app.test_results where test_id = pg_temp.id('other') and published_at is not null),
  1, 'another test keeps its publication');
select is((select count(*)::int from app.comments where batch_id = pg_temp.id('batch') and published_at is not null),
  1, 'a comment batch keeps its publication');
select is((select v.sanitized_snapshot ->> 'published_at' is not null from app.business_entity_versions v
            join app.test_results r on r.id = v.entity_id
           where v.entity_kind = 'test_result' and r.test_id = pg_temp.id('t') and r.student_id = pg_temp.id('an')
           order by v.revision desc offset 1 limit 1), true, 'the publication before archiving stays in history');
select is((select jsonb_array_length(before_after -> 'unpublished_results') from app.audit_events
            where action = 'test.archive'), 2, 'one audit lists the unpublished scores');
select is((select jsonb_array_length(api.list_class_tests(pg_temp.id('A')) -> 'items')), 1,
  'an archived test leaves the list');
select is((select jsonb_array_length(api.list_class_tests(pg_temp.id('A'), true) -> 'items')), 2,
  'archived tests can be listed');
select is((api.get_test_results(pg_temp.id('t')) ->> 'canEdit')::boolean, false,
  'the history of an archived test is read-only');
select throws_ok($$select pg_temp.save('t', 'an', '{"absent":true}')$$, 'PT409', 'invalid_state',
  'no result is entered on an archived test');
select throws_ok($$select api.publish_test_results(pg_temp.id('t'), null, true)$$, 'PT409', 'invalid_state',
  'an archived test cannot be published');
select throws_ok($$select api.save_comments('test', pg_temp.id('t'), jsonb_build_array(
    jsonb_build_object('studentId', pg_temp.id('binh'), 'expectedVersion', null, 'body', 'x')))$$,
  'PT409', 'invalid_state', 'no comment is written on an archived test');

-------------------------------------------------------------------------------
-- Restore: same ids, everything unpublished.
-------------------------------------------------------------------------------
select pg_temp.actor(2);
select throws_ok($$select api.restore_test(pg_temp.id('t'), pg_temp.v('t'))$$, 'PT403', 'forbidden',
  'receptionists cannot restore a test');
select pg_temp.actor(1);
create temp table before_ids as select id from app.test_results where test_id = pg_temp.id('t');
select lives_ok($$select api.restore_test(pg_temp.id('t'), pg_temp.v('t'))$$, 'Admin restores the test');
select is((select count(*)::int from app.test_results r join before_ids b using (id)
            where r.test_id = pg_temp.id('t') and r.published_at is null), 2,
  'the same results come back unpublished');
select is((select count(*)::int from app.comments where test_id = pg_temp.id('t') and published_at is null
             and body = 'Tốt'), 1, 'the comment comes back unpublished');
select throws_ok($$select api.restore_test(pg_temp.id('t'), pg_temp.v('t'))$$, 'PT409', 'invalid_state',
  'a test in use cannot be restored');

-------------------------------------------------------------------------------
-- Atomicity.
-------------------------------------------------------------------------------
select api.publish_test_results(pg_temp.id('t'), null, true);
create function pg_temp.fail_audit() returns trigger language plpgsql as $$
begin raise exception 'audit_failure'; end $$;
create trigger zz_archive_fail_audit before insert on app.audit_events
  for each row execute function pg_temp.fail_audit();
select throws_ok($$select api.archive_test(pg_temp.id('t'), 'Lỗi', pg_temp.v('t'))$$,
  'P0001', 'audit_failure', 'audit failure aborts the archive');
drop trigger zz_archive_fail_audit on app.audit_events;
select is((select deleted_at from app.tests where id = pg_temp.id('t')), null, 'the test is not archived');
select is((select count(*)::int from app.test_results where test_id = pg_temp.id('t') and published_at is not null),
  2, 'the publication is unchanged by the failed archive');

select * from finish();
rollback;
