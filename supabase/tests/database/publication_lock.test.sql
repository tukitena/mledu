-- Publication of results (ACAD-01, TEST-01/04): rights, one student or the
-- whole class, only complete results or Absent, missing list, the lock on
-- published results, independence between tests, history and audit.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Seed fixtures: 1 admin, 2 receptionist, 3 user (teacher in A, assistant in B).
insert into auth.sessions (id, user_id, created_at, updated_at)
select format('28000000-0000-4000-8000-%s', lpad(n::text, 12, '0'))::uuid,
       format('00000000-0000-4000-8000-%s', lpad(n::text, 12, '0'))::uuid,
       now() - interval '1 minute', now()
  from generate_series(1, 3) n;
insert into auth.mfa_amr_claims (id, session_id, created_at, updated_at, authentication_method)
select gen_random_uuid(), s.id, now(), now(), 'password'
  from auth.sessions s where s.id::text like '28000000%';

create function pg_temp.actor(p_user int)
returns void
language sql
as $$
  select set_config('request.jwt.claims', json_build_object(
    'sub', format('00000000-0000-4000-8000-%s', lpad(p_user::text, 12, '0')),
    'session_id', format('28000000-0000-4000-8000-%s', lpad(p_user::text, 12, '0')),
    'role', 'authenticated')::text, true);
$$;

create temp table ids (key text primary key, id uuid);
create function pg_temp.id(p_key text) returns uuid language sql as $$ select id from ids where key = p_key $$;
create function pg_temp.keep(p_key text, p_dto jsonb) returns jsonb language sql as $$
  insert into ids values (p_key, (p_dto ->> 'id')::uuid)
  on conflict (key) do update set id = excluded.id
  returning p_dto
$$;
create function pg_temp.config(p_test text) returns uuid language sql as $$
  select current_config_id from app.tests where id = pg_temp.id(p_test) $$;
create function pg_temp.result(p_test text, p_student text) returns jsonb language sql as $$
  select x -> 'result' from jsonb_array_elements(api.get_test_results(pg_temp.id(p_test)) -> 'students') x
   where (x ->> 'studentId')::uuid = pg_temp.id(p_student) $$;
create function pg_temp.version(p_test text, p_student text) returns bigint language sql as $$
  select row_version from app.test_results
   where test_id = pg_temp.id(p_test) and student_id = pg_temp.id(p_student) and deleted_at is null $$;
create function pg_temp.save(p_test text, p_student text, p_entry jsonb) returns jsonb language sql as $$
  select api.save_test_results(pg_temp.id(p_test), pg_temp.config(p_test),
    jsonb_build_array(jsonb_build_object('studentId', pg_temp.id(p_student),
      'expectedVersion', pg_temp.version(p_test, p_student), 'entry', p_entry)))
$$;
create function pg_temp.publish(p_test text, p_student text, p_publish boolean) returns jsonb
language sql as $$
  select api.publish_test_results(pg_temp.id(p_test), pg_temp.id(p_student), p_publish) $$;
create function pg_temp.published(p_test text, p_student text) returns boolean language sql as $$
  select (pg_temp.result(p_test, p_student) ->> 'published')::boolean $$;

select ok(not has_function_privilege('anon', 'api.publish_test_results(uuid, uuid, boolean)', 'execute')
       and has_function_privilege('authenticated', 'api.publish_test_results(uuid, uuid, boolean)', 'execute'),
  'anon cannot publish');

-------------------------------------------------------------------------------
-- Fixture.
-------------------------------------------------------------------------------
select pg_temp.actor(1);
create temp table day as select app_private.business_date(now()) d;
select pg_temp.keep(k, api.create_class('Công bố ' || k, '10000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000011', d - 20, d + 20))
  from day, unnest(array['A', 'B']) k;
select api.create_class_assignment(pg_temp.id('A'), '00000000-0000-4000-8000-000000000003', 'teacher',
    d - 1, d + 10, null) from day;
select api.create_class_assignment(pg_temp.id('B'), '00000000-0000-4000-8000-000000000003', 'assistant',
    d - 1, d + 10, null) from day;
select pg_temp.keep(k, api.create_student('Công bố học sinh ' || k))
  from unnest(array['a_full', 'b_part', 'c_absent', 'd_none']) k;
select api.enroll_student(pg_temp.id('A'), pg_temp.id(k), d - 15)
  from day, unnest(array['a_full', 'b_part', 'c_absent', 'd_none']) k;
select api.enroll_student(pg_temp.id('B'), pg_temp.id('a_full'), d - 15) from day;

select pg_temp.keep('parts', api.create_test(pg_temp.id('A'), 'Theo phần', d, null,
  '{"scaleKind":"numeric","inputMode":"components","maxScore":7,"showComponents":true,
    "components":[{"name":"Nghe","maxScore":3},{"name":"Viết","maxScore":4}]}', null)) from day;
select pg_temp.keep('other', api.create_test(pg_temp.id('A'), 'Bài khác', d, null,
  '{"scaleKind":"numeric","inputMode":"direct","maxScore":10}', null)) from day;
select pg_temp.keep('empty', api.create_test(pg_temp.id('A'), 'Chưa nhập', d, null,
  '{"scaleKind":"numeric","inputMode":"direct","maxScore":10}', null)) from day;
select pg_temp.keep('assist', api.create_test(pg_temp.id('B'), 'Trợ giảng', d, null,
  '{"scaleKind":"numeric","inputMode":"direct","maxScore":10}', null)) from day;

select pg_temp.save('parts', 'a_full', '{"absent":false,"components":{"c1":3,"c2":4}}');
select pg_temp.save('parts', 'b_part', '{"absent":false,"components":{"c1":2}}');
select pg_temp.save('parts', 'c_absent', '{"absent":true}');
select pg_temp.save('other', 'a_full', '{"absent":false,"score":8}');
select pg_temp.save('assist', 'a_full', '{"absent":false,"score":5}');

-------------------------------------------------------------------------------
-- Rights: Admin and teachers publish; assistants and receptionists cannot.
-------------------------------------------------------------------------------
select is((api.get_test_results(pg_temp.id('parts')) ->> 'canPublish')::boolean, true, 'Admin may publish');
select pg_temp.actor(2);
select throws_ok($$select pg_temp.publish('parts', 'a_full', true)$$, 'PT403', 'forbidden',
  'receptionists cannot publish');
select pg_temp.actor(3);
select is((api.get_test_results(pg_temp.id('assist')) ->> 'canPublish')::boolean, false,
  'an assistant is told they cannot publish');
select throws_ok($$select pg_temp.publish('assist', 'a_full', true)$$, 'PT403', 'forbidden',
  'an assistant cannot publish one student');
select throws_ok($$select api.publish_test_results(pg_temp.id('assist'), null, true)$$, 'PT403', 'forbidden',
  'an assistant cannot publish the class');
select is((api.get_test_results(pg_temp.id('parts')) ->> 'canPublish')::boolean, true,
  'a teacher may publish in their class');

-------------------------------------------------------------------------------
-- One student.
-------------------------------------------------------------------------------
select throws_ok($$select pg_temp.publish('parts', 'b_part', true)$$, 'PT409', 'result_incomplete',
  'a result with a missing component cannot be published, even through the API');
select throws_ok($$select pg_temp.publish('parts', 'd_none', true)$$, 'PT409', 'result_incomplete',
  'a student without a result cannot be published');
select lives_ok($$select pg_temp.publish('parts', 'c_absent', true)$$, 'Absent can be published');
select is(pg_temp.published('parts', 'c_absent'), true, 'Absent is now published');
select is(pg_temp.published('parts', 'a_full'), false, 'other students of the test are unchanged');
select is((pg_temp.result('parts', 'c_absent') ->> 'publishedByName'), 'Giáo viên Thử nghiệm',
  'the publisher is recorded');
select is((select count(*)::int from app.audit_events where action = 'test_result.publish'), 1,
  'publishing writes one audit');
select lives_ok($$select pg_temp.publish('parts', 'c_absent', true)$$, 'publishing again is harmless');
select is((select count(*)::int from app.audit_events where action = 'test_result.publish'), 1,
  'publishing again writes nothing');

-------------------------------------------------------------------------------
-- Lock: no change, clear or Absent switch while published (ACAD-01).
-------------------------------------------------------------------------------
select throws_ok($$select pg_temp.save('parts', 'c_absent', '{"absent":false,"components":{"c1":1}}')$$,
  'PT409', 'result_published', 'Absent cannot be switched to a score while published');
select throws_ok($$select pg_temp.save('parts', 'c_absent', null)$$,
  'PT409', 'result_published', 'a published result cannot be cleared');
select throws_ok($$select api.save_test_results(pg_temp.id('parts'), pg_temp.config('parts'),
    jsonb_build_array(jsonb_build_object('studentId', pg_temp.id('c_absent'), 'expectedVersion', 1,
      'entry', '{"absent":true}'::jsonb)))$$,
  'PT409', 'version_conflict', 'publishing gives the result a new version, so a stale grid conflicts');

-------------------------------------------------------------------------------
-- Whole class: complete results and Absent only, missing students listed.
-------------------------------------------------------------------------------
create temp table outcome as
  select api.publish_test_results(pg_temp.id('parts'), null, true) o;
select is((select (o ->> 'changed')::int from outcome), 1,
  'the class publish changes only the complete result not yet published');
select is((select jsonb_agg(x ->> 'fullName' order by x ->> 'fullName') from outcome,
             jsonb_array_elements(o -> 'missing') x),
  '["Công bố học sinh b_part","Công bố học sinh d_none"]'::jsonb,
  'students with a missing component or no result are listed, not published');
select is(pg_temp.published('parts', 'a_full'), true, 'the complete student is published');
select is(pg_temp.published('parts', 'b_part'), false, 'the incomplete student stays unpublished');
select is(pg_temp.result('parts', 'd_none'), 'null'::jsonb, 'no result is created for a missing student');
select is(pg_temp.published('other', 'a_full'), false, 'another test of the class is unchanged');
select is((select (api.get_test(pg_temp.id('parts')) ->> 'publishedCount')::int), 2,
  'the test counts published results');

select pg_temp.save('parts', 'b_part', '{"absent":false,"components":{"c1":2,"c2":1}}');
select is(pg_temp.published('parts', 'b_part'), false, 'completing a skipped result does not publish it');

select throws_ok($$select api.publish_test_results(pg_temp.id('empty'), null, true)$$,
  'PT409', 'nothing_eligible', 'a class publish without any complete result is refused');
select is((select count(*)::int from app.audit_events
            where action = 'test_result.publish' and entity_refs ->> 'test_id' = pg_temp.id('empty')::text), 0,
  'the refused class publish writes no audit');

-------------------------------------------------------------------------------
-- Display option and unpublish.
-------------------------------------------------------------------------------
select lives_ok($$select api.set_test_show_components(pg_temp.id('parts'), false, row_version)
    from app.tests where id = pg_temp.id('parts')$$,
  'the display option changes while results are published (TEST-04)');
select is(pg_temp.published('parts', 'a_full'), true, 'changing the display keeps the publication');

select pg_temp.actor(3);
select lives_ok($$select pg_temp.publish('parts', 'a_full', false)$$, 'a teacher unpublishes one student');
select is(pg_temp.published('parts', 'a_full'), false, 'the student is unpublished');
select is(pg_temp.published('parts', 'c_absent'), true, 'other students keep their publication');
select lives_ok($$select pg_temp.save('parts', 'a_full', '{"absent":false,"components":{"c1":2,"c2":4}}')$$,
  'an unpublished result can be changed');
select is(pg_temp.published('parts', 'a_full'), false, 'a change after unpublishing does not publish again');

select is((select (api.publish_test_results(pg_temp.id('parts'), null, false) ->> 'changed')::int), 1,
  'unpublishing the class changes every published result');
select is((select count(*)::int from app.test_results
            where test_id = pg_temp.id('parts') and published_at is not null), 0, 'nothing stays published');
select is((select (before_after -> 'after' ->> 'published')::boolean from app.audit_events
            where action = 'test_result.unpublish' order by created_at desc, id desc limit 1), false,
  'the unpublish audit has before/after');
select is((select v.sanitized_snapshot ->> 'published_at' is not null from app.business_entity_versions v
            where v.entity_kind = 'test_result'
              and v.entity_id = (pg_temp.result('parts', 'c_absent') ->> 'id')::uuid
            order by v.revision desc offset 1 limit 1), true,
  'the publication state is kept in the result history');

-------------------------------------------------------------------------------
-- Atomicity and revoked rights.
-------------------------------------------------------------------------------
select pg_temp.actor(1);
create function pg_temp.fail_audit() returns trigger language plpgsql as $$
begin raise exception 'audit_failure'; end $$;
create trigger zz_publish_fail_audit before insert on app.audit_events
  for each row execute function pg_temp.fail_audit();
select throws_ok($$select pg_temp.publish('other', 'a_full', true)$$, 'P0001', 'audit_failure',
  'audit failure aborts the publication');
drop trigger zz_publish_fail_audit on app.audit_events;
select is(pg_temp.published('other', 'a_full'), false, 'nothing was published by the failed command');

select api.end_class_assignment(id, 'Thu hồi', row_version) from app.class_assignments
 where account_id = '00000000-0000-4000-8000-000000000003' and class_id = pg_temp.id('A');
select pg_temp.actor(3);
select throws_ok($$select pg_temp.publish('other', 'a_full', true)$$, 'PT404', 'not_found',
  'a revoked assignment stops publishing');

select * from finish();
rollback;
