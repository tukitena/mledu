-- Results of a test per student (TEST-01/04/05): roster by participation on
-- the test day, typed values on the test's snapshot, computed totals, Absent, the publication lock, history and audit.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Seed fixtures: 1 admin, 2 receptionist, 3 user.
insert into auth.sessions (id, user_id, created_at, updated_at)
select format('27000000-0000-4000-8000-%s', lpad(n::text, 12, '0'))::uuid,
       format('00000000-0000-4000-8000-%s', lpad(n::text, 12, '0'))::uuid,
       now() - interval '1 minute', now()
  from generate_series(1, 3) n;
insert into auth.mfa_amr_claims (id, session_id, created_at, updated_at, authentication_method)
select gen_random_uuid(), s.id, now(), now(), 'password'
  from auth.sessions s where s.id::text like '27000000%';

create function pg_temp.actor(p_user int)
returns void
language sql
as $$
  select set_config('request.jwt.claims', json_build_object(
    'sub', format('00000000-0000-4000-8000-%s', lpad(p_user::text, 12, '0')),
    'session_id', format('27000000-0000-4000-8000-%s', lpad(p_user::text, 12, '0')),
    'role', 'authenticated')::text, true);
$$;

create temp table ids (key text primary key, id uuid, version bigint);
create function pg_temp.id(p_key text) returns uuid language sql as $$ select id from ids where key = p_key $$;
create function pg_temp.keep(p_key text, p_dto jsonb) returns jsonb language sql as $$
  insert into ids values (p_key, (p_dto ->> 'id')::uuid, (p_dto ->> 'rowVersion')::bigint)
  on conflict (key) do update set id = excluded.id, version = excluded.version
  returning p_dto
$$;
-- Current configuration of a test, and the result of a student in it.
create function pg_temp.config(p_test text) returns uuid language sql as $$
  select current_config_id from app.tests where id = pg_temp.id(p_test) $$;
create function pg_temp.result(p_test text, p_student text) returns jsonb language sql as $$
  select x -> 'result' from jsonb_array_elements(api.get_test_results(pg_temp.id(p_test)) -> 'students') x
   where (x ->> 'studentId')::uuid = pg_temp.id(p_student) $$;
create function pg_temp.save(p_test text, p_student text, p_version bigint, p_entry jsonb)
returns jsonb language sql as $$
  select api.save_test_results(pg_temp.id(p_test), pg_temp.config(p_test),
    jsonb_build_array(jsonb_build_object('studentId', pg_temp.id(p_student),
      'expectedVersion', p_version, 'entry', p_entry)))
$$;

-------------------------------------------------------------------------------
-- Privileges.
-------------------------------------------------------------------------------
select ok(not has_table_privilege('authenticated', 'app.test_results', 'select')
       and not has_table_privilege('authenticated', 'app.component_results', 'insert')
       and not has_table_privilege('anon', 'app.test_results', 'select'),
  'result tables are not exposed to clients');
select ok(not has_function_privilege('anon', 'api.save_test_results(uuid, uuid, jsonb)', 'execute')
       and not has_function_privilege('anon', 'api.get_test_results(uuid)', 'execute')
       and has_function_privilege('authenticated', 'api.save_test_results(uuid, uuid, jsonb)', 'execute'),
  'anon cannot call result RPCs');

-------------------------------------------------------------------------------
-- Fixture: class A (user 3 teacher), class B (user 3 assistant); students
-- on (joined before), left (last day before the test day), later (joins after).
-------------------------------------------------------------------------------
select pg_temp.actor(1);
create temp table day as select app_private.business_date(now()) d;
select pg_temp.keep(k, api.create_class('Kết quả ' || k, '10000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000011', d - 20, d + 20))
  from day, unnest(array['A', 'B']) k;
select api.create_class_assignment(pg_temp.id('A'), '00000000-0000-4000-8000-000000000003', 'teacher',
    d - 1, d + 10, null) from day;
select api.create_class_assignment(pg_temp.id('B'), '00000000-0000-4000-8000-000000000003', 'assistant',
    d - 1, d + 10, null) from day;
select pg_temp.keep(k, api.create_student('Kết quả học sinh ' || k))
  from unnest(array['on', 'absent', 'left', 'later']) k;
select api.enroll_student(pg_temp.id('A'), pg_temp.id('on'), d - 15) from day;
select api.enroll_student(pg_temp.id('A'), pg_temp.id('absent'), d - 15) from day;
select api.enroll_student(pg_temp.id('A'), pg_temp.id('left'), d - 15, d - 2) from day;
select api.enroll_student(pg_temp.id('A'), pg_temp.id('later'), d + 5) from day;
select api.enroll_student(pg_temp.id('B'), pg_temp.id('on'), d - 15) from day;

select pg_temp.keep('parts', api.create_test(pg_temp.id('A'), 'Theo phần', d, null,
  '{"scaleKind":"numeric","inputMode":"components","maxScore":7,"showComponents":false,
    "components":[{"name":"Nghe","maxScore":3},{"name":"Viết","maxScore":4}]}', null)) from day;
select pg_temp.keep('direct', api.create_test(pg_temp.id('A'), 'Trực tiếp', d, null,
  '{"scaleKind":"numeric","inputMode":"direct","maxScore":10}', null)) from day;
select pg_temp.keep('fraction', api.create_test(pg_temp.id('A'), 'Phân số', d, null,
  '{"scaleKind":"fraction","inputMode":"components","totalQuestions":90,"showComponents":false,
    "components":[{"name":"P1","totalQuestions":30},{"name":"P2","totalQuestions":30},
                  {"name":"P3","totalQuestions":30}]}', null)) from day;
select pg_temp.keep('fdirect', api.create_test(pg_temp.id('A'), 'Phân số trực tiếp', d, null,
  '{"scaleKind":"fraction","inputMode":"direct","totalQuestions":40}', null)) from day;
select pg_temp.keep('letter', api.create_test(pg_temp.id('A'), 'Chữ', d, null,
  '{"scaleKind":"letter","inputMode":"direct","levels":[{"label":"Chưa đạt"},{"label":"Đạt"}]}', null)) from day;
select pg_temp.keep('past', api.create_test(pg_temp.id('A'), 'Tuần trước', d - 5, null,
  '{"scaleKind":"numeric","inputMode":"direct","maxScore":10}', null)) from day;
select pg_temp.keep('ielts', api.create_test(pg_temp.id('A'), 'IELTS', d, null,
  '{"scaleKind":"ielts","showComponents":false,"skills":[{"code":"L","inputMode":"direct"}]}', null)) from day;
select pg_temp.keep('assist', api.create_test(pg_temp.id('B'), 'Lớp trợ giảng', d, null,
  '{"scaleKind":"numeric","inputMode":"direct","maxScore":10}', null)) from day;

-------------------------------------------------------------------------------
-- Roster by participation on the test day (TEST-05).
-------------------------------------------------------------------------------
select is((select jsonb_agg(x ->> 'fullName' order by x ->> 'fullName')
             from jsonb_array_elements(api.get_test_results(pg_temp.id('parts')) -> 'students') x),
  '["Kết quả học sinh absent","Kết quả học sinh on"]'::jsonb,
  'the roster holds students whose participation meets the test day only');
select is((select jsonb_agg(x ->> 'fullName' order by x ->> 'fullName')
             from jsonb_array_elements(api.get_test_results(pg_temp.id('past')) -> 'students') x),
  '["Kết quả học sinh absent","Kết quả học sinh left","Kết quả học sinh on"]'::jsonb,
  'an earlier test day includes a student who has left since');
select is(pg_temp.result('parts', 'on'), 'null'::jsonb, 'no result yet');
select is((api.get_test_results(pg_temp.id('parts')) ->> 'canEdit')::boolean, true, 'Admin may enter results');

-------------------------------------------------------------------------------
-- Components: partial total, missing is not 0, exact sums (TEST-04).
-------------------------------------------------------------------------------
select pg_temp.save('parts', 'on', null, '{"absent":false,"components":{"c1":1.25}}');
select is(pg_temp.result('parts', 'on') - 'id' - 'updatedAt' - 'publishedAt' - 'publishedByName',
  '{"absent":false,"score":1.25,"correctAnswers":null,"level":null,"components":{"c1":1.25},"ielts":null,"overallBand":null,
    "complete":false,"published":false,"rowVersion":1,"updatedByName":"Quản trị Thử nghiệm"}'::jsonb,
  'one component keeps a partial total and the result is incomplete');
select pg_temp.save('parts', 'on', 1, '{"absent":false,"components":{"c1":1.25,"c2":2.10}}');
select is(pg_temp.result('parts', 'on') ->> 'score', '3.35', '1,25 + 2,10 gives exactly 3,35');
select is((pg_temp.result('parts', 'on') ->> 'complete')::boolean, true, 'every component entered completes it');
select is((select count(*)::int from app.business_entity_versions
            where entity_kind = 'test_result' and entity_id = (pg_temp.result('parts', 'on') ->> 'id')::uuid), 2,
  'each change keeps a business version');
select is((select count(*)::int from app.audit_events where action = 'test_result.save'), 2,
  'each save writes one audit');
select pg_temp.save('parts', 'on', 2, '{"absent":false,"components":{"c1":1.25,"c2":2.1}}');
select is((pg_temp.result('parts', 'on') ->> 'rowVersion')::int, 2, 'unchanged content writes no version');
select is((select count(*)::int from app.audit_events where action = 'test_result.save'), 2,
  'unchanged content writes no audit');
select throws_ok($$select pg_temp.save('parts', 'on', 1, '{"absent":false,"components":{"c1":0}}')$$,
  'PT409', 'version_conflict', 'a stale version is refused');
select throws_ok($$select pg_temp.save('parts', 'on', null, '{"absent":false,"components":{"c1":0}}')$$,
  'PT409', 'version_conflict', 'an existing result needs its version');
select pg_temp.save('parts', 'on', 2, '{"absent":false,"components":{"c1":0,"c2":4}}');
select is(pg_temp.result('parts', 'on') -> 'components', '{"c1":0,"c2":4}'::jsonb,
  'an entered 0 is a value; the maximum is accepted');
select throws_ok($$select pg_temp.save('parts', 'on', 3, '{"absent":false,"components":{"c1":3.5}}')$$,
  'PT400', 'validation_failed', 'a component above its own maximum is refused');
select throws_ok($$select pg_temp.save('parts', 'on', 3, '{"absent":false,"components":{"c1":1.255}}')$$,
  'PT400', 'validation_failed', 'more than two decimals are refused, not rounded');
select throws_ok($$select pg_temp.save('parts', 'on', 3, '{"absent":false,"components":{"c1":-1}}')$$,
  'PT400', 'validation_failed', 'a negative value is refused');
select throws_ok($$select pg_temp.save('parts', 'on', 3, '{"absent":false,"components":{"c9":1}}')$$,
  'PT400', 'validation_failed', 'a code outside the snapshot is refused');
select throws_ok($$select pg_temp.save('parts', 'on', 3, '{"absent":false,"components":{"c1":"1"}}')$$,
  'PT400', 'validation_failed', 'values are JSON numbers');
select throws_ok($$select pg_temp.save('parts', 'on', 3, '{"absent":false,"score":7}')$$,
  'PT400', 'validation_failed', 'a total cannot be entered over components');
select throws_ok($$select pg_temp.save('parts', 'on', 3, '{"absent":false,"components":{}}')$$,
  'PT400', 'validation_failed', 'a result needs at least one value; clearing uses null');
select throws_ok($$select pg_temp.save('parts', 'later', null, '{"absent":true}')$$,
  'PT400', 'validation_failed', 'a student outside the test day cannot get a result');
select throws_ok($$select api.save_test_results(pg_temp.id('parts'), pg_temp.config('direct'),
    jsonb_build_array(jsonb_build_object('studentId', pg_temp.id('on'), 'expectedVersion', 3,
      'entry', '{"absent":true}'::jsonb)))$$,
  'PT409', 'version_conflict', 'entries made on another configuration are refused');

-------------------------------------------------------------------------------
-- Direct numeric, fraction and letter (TEST-01).
-------------------------------------------------------------------------------
select pg_temp.save('direct', 'on', null, '{"absent":false,"score":10}');
select is(pg_temp.result('direct', 'on') ->> 'score', '10', 'the maximum is accepted');
select pg_temp.save('direct', 'absent', null, '{"absent":false,"score":0}');
select is(pg_temp.result('direct', 'absent') ->> 'score', '0', 'zero is accepted');
select throws_ok($$select pg_temp.save('direct', 'on', 1, '{"absent":false,"score":10.5}')$$,
  'PT400', 'validation_failed', 'a score above the maximum is refused');
select throws_ok($$select pg_temp.save('direct', 'on', 1, '{"absent":false,"score":8.255}')$$,
  'PT400', 'validation_failed', 'a direct score with three decimals is refused');
select pg_temp.save('direct', 'on', 1, '{"absent":false,"score":8.25}');
select is(pg_temp.result('direct', 'on') ->> 'score', '8.25', '8,25 is stored as entered');

select pg_temp.save('fraction', 'on', null, '{"absent":false,"components":{"c1":20}}');
select is(pg_temp.result('fraction', 'on') ->> 'correctAnswers', '20',
  'a partial fraction keeps the answers entered (shown over the whole 90)');
select is((pg_temp.result('fraction', 'on') ->> 'complete')::boolean, false, 'two parts are still missing');
select throws_ok($$select pg_temp.save('fraction', 'on', 1, '{"absent":false,"components":{"c1":31}}')$$,
  'PT400', 'validation_failed', 'answers above the part total are refused');
select throws_ok($$select pg_temp.save('fdirect', 'on', null, '{"absent":false,"correctAnswers":1.5}')$$,
  'PT400', 'validation_failed', 'answers are whole numbers');
select throws_ok($$select pg_temp.save('fdirect', 'on', null, '{"absent":false,"correctAnswers":41}')$$,
  'PT400', 'validation_failed', 'answers above the total are refused');
select pg_temp.save('fdirect', 'on', null, '{"absent":false,"correctAnswers":40}');
select is(pg_temp.result('fdirect', 'on') ->> 'correctAnswers', '40', 'all answers right is accepted');

select pg_temp.save('letter', 'on', null, '{"absent":false,"level":"l2"}');
select is(pg_temp.result('letter', 'on') ->> 'level', 'l2', 'a level of the test is stored');
select throws_ok($$select pg_temp.save('letter', 'absent', null, '{"absent":false,"level":"l9"}')$$,
  'PT400', 'validation_failed', 'a level outside the test is refused');
select lives_ok($$select pg_temp.save('ielts', 'on', null, '{"absent":true}')$$,
  'IELTS results use the same command (details in ielts_results.test.sql)');

-------------------------------------------------------------------------------
-- Absent and clearing.
-------------------------------------------------------------------------------
select pg_temp.save('parts', 'absent', null, '{"absent":true}');
select is(pg_temp.result('parts', 'absent') - 'id' - 'updatedAt' - 'updatedByName' - 'publishedAt'
            - 'publishedByName',
  '{"absent":true,"score":null,"correctAnswers":null,"level":null,"components":{},"ielts":null,"overallBand":null,
    "complete":true,"published":false,"rowVersion":1}'::jsonb,
  'Absent is its own complete state, not a 0 and without components');
select throws_ok($$select pg_temp.save('parts', 'absent', 1, '{"absent":true,"components":{"c1":0}}')$$,
  'PT400', 'validation_failed', 'Absent carries no values');
select throws_ok($$insert into app.test_results (student_id, test_id, config_id, result_kind, numeric_score,
    created_by, updated_by) values (pg_temp.id('later'), pg_temp.id('direct'), pg_temp.config('direct'),
    'absent', 0, '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000001')$$,
  '23514', null, 'the table refuses a score on Absent');

select pg_temp.save('direct', 'absent', 1, null);
select is(pg_temp.result('direct', 'absent'), 'null'::jsonb, 'clearing removes the result in use');
select is((select x.deleted_at is not null from app.test_results x
            where x.test_id = pg_temp.id('direct') and x.student_id = pg_temp.id('absent')), true,
  'the row is kept, cleared');
select pg_temp.save('direct', 'absent', 2, '{"absent":false,"score":6}');
select is((pg_temp.result('direct', 'absent') ->> 'rowVersion')::int, 3,
  'entering again reuses the same result with a new version');
select is((select count(*)::int from app.test_results
            where test_id = pg_temp.id('direct') and student_id = pg_temp.id('absent')), 1,
  'one result per student and test');
select pg_temp.save('letter', 'on', 1, null);
select lives_ok($$select pg_temp.save('letter', 'on', null, '{"absent":false,"level":"l1"}')$$,
  'a cleared result is entered again without knowing its old version');
select is((pg_temp.result('letter', 'on') ->> 'rowVersion')::int, 3, 'the cleared row is reused');
select is((api.get_test(pg_temp.id('direct')) ->> 'resultCount')::int, 2, 'the test counts results in use');

-------------------------------------------------------------------------------
-- Rights.
-------------------------------------------------------------------------------
select pg_temp.actor(2);
select throws_ok($$select api.get_test_results(pg_temp.id('parts'))$$, 'PT403', 'forbidden',
  'receptionists cannot read results');
select throws_ok($$select pg_temp.save('parts', 'on', 3, '{"absent":true}')$$, 'PT403', 'forbidden',
  'receptionists cannot enter results');
select pg_temp.actor(3);
select lives_ok($$select pg_temp.save('assist', 'on', null, '{"absent":false,"score":7}')$$,
  'an assistant enters results in their class');
select lives_ok($$select pg_temp.save('letter', 'absent', null, '{"absent":true}')$$,
  'a teacher enters results in their class');

-------------------------------------------------------------------------------
-- Publication lock (ACAD-01).
-------------------------------------------------------------------------------
select pg_temp.actor(1);
update app.test_results set published_at = now(), published_by = '00000000-0000-4000-8000-000000000001'
 where test_id = pg_temp.id('parts') and student_id = pg_temp.id('on');
select throws_ok($$select pg_temp.save('parts', 'on', 3, '{"absent":false,"components":{"c1":1}}')$$,
  'PT409', 'result_published', 'a published result cannot be changed');
select throws_ok($$select pg_temp.save('parts', 'on', 3, null)$$,
  'PT409', 'result_published', 'a published result cannot be cleared');
update app.test_results set published_at = null, published_by = null
 where test_id = pg_temp.id('parts') and student_id = pg_temp.id('on');

-------------------------------------------------------------------------------
-- Test date and participation (TEST-05).
-------------------------------------------------------------------------------
select pg_temp.save('past', 'left', null, '{"absent":false,"score":5}');
select throws_ok($$select api.update_test(pg_temp.id('past'), 'Tuần trước', d, null, row_version)
    from app.tests, day where id = pg_temp.id('past')$$,
  'PT409', 'test_date_excludes_results', 'a new date cannot leave out a student with a result');
create function pg_temp.date_error() returns text language plpgsql as $$
declare v_detail text;
begin
  perform api.update_test(pg_temp.id('past'), 'Tuần trước', d, null, row_version)
     from app.tests, day where id = pg_temp.id('past');
  return null;
exception when others then
  get stacked diagnostics v_detail = pg_exception_detail;
  return v_detail;
end $$;
select is(pg_temp.date_error()::jsonb, '[{"path":"studentName","message":"Kết quả học sinh left"}]'::jsonb,
  'the refusal names the students left out');
select is((select test_on from app.tests where id = pg_temp.id('past')), (select d - 5 from day),
  'the date is unchanged');
select lives_ok($$select api.update_test(pg_temp.id('past'), 'Tuần trước', d - 4, null, row_version)
    from app.tests, day where id = pg_temp.id('past')$$,
  'a date still within every participation is accepted');

-------------------------------------------------------------------------------
-- Atomicity and revoked rights.
-------------------------------------------------------------------------------
create function pg_temp.fail_audit() returns trigger language plpgsql as $$
begin raise exception 'audit_failure'; end $$;
create trigger zz_result_fail_audit before insert on app.audit_events
  for each row execute function pg_temp.fail_audit();
select throws_ok($$select pg_temp.save('fdirect', 'absent', null, '{"absent":true}')$$,
  'P0001', 'audit_failure', 'audit failure aborts the save');
drop trigger zz_result_fail_audit on app.audit_events;
select is(pg_temp.result('fdirect', 'absent'), 'null'::jsonb, 'no result is left behind by the failed save');

select api.end_class_assignment(id, 'Thu hồi', row_version) from app.class_assignments
 where account_id = '00000000-0000-4000-8000-000000000003' and class_id = pg_temp.id('B');
select pg_temp.actor(3);
select throws_ok($$select pg_temp.save('assist', 'on', 1, '{"absent":true}')$$,
  'PT404', 'not_found', 'a revoked assignment stops entering results');

select * from finish();
rollback;
