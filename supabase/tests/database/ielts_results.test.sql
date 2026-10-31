-- IELTS results (TEST-01): skills and modes of the snapshot, roundBand with
-- the 0,25/0,75 limits, Task rounding before the 1:2 Writing weight, L/R kept
-- as typed, missing input never 0, Overall only with four bands and publication
-- of one-to-three-skill tests.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.sessions (id, user_id, created_at, updated_at)
select format('29000000-0000-4000-8000-%s', lpad(n::text, 12, '0'))::uuid,
       format('00000000-0000-4000-8000-%s', lpad(n::text, 12, '0'))::uuid,
       now() - interval '1 minute', now()
  from generate_series(1, 3) n;
insert into auth.mfa_amr_claims (id, session_id, created_at, updated_at, authentication_method)
select gen_random_uuid(), s.id, now(), now(), 'password'
  from auth.sessions s where s.id::text like '29000000%';

create function pg_temp.actor(p_user int)
returns void
language sql
as $$
  select set_config('request.jwt.claims', json_build_object(
    'sub', format('00000000-0000-4000-8000-%s', lpad(p_user::text, 12, '0')),
    'session_id', format('29000000-0000-4000-8000-%s', lpad(p_user::text, 12, '0')),
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
create function pg_temp.skills(p_skills jsonb) returns jsonb language sql as $$
  select jsonb_build_object('absent', false, 'skills', p_skills) $$;

select ok(not has_table_privilege('authenticated', 'app.ielts_skill_results', 'select')
       and not has_table_privilege('authenticated', 'app.ielts_criterion_results', 'insert'),
  'IELTS result tables are not exposed to clients');

-------------------------------------------------------------------------------
-- roundBand (TEST-01 acceptance values).
-------------------------------------------------------------------------------
select is(app_private.round_band(6.125), 6::numeric, '6,125 -> 6,0');
select is(app_private.round_band(6.25), 6.5, '6,25 -> 6,5');
select is(app_private.round_band(6.75), 7::numeric, '6,75 -> 7,0');
select is(app_private.round_band(6.7499), 6.5, 'just below 0,75 stays at the half band');

-------------------------------------------------------------------------------
-- Fixture.
-------------------------------------------------------------------------------
select pg_temp.actor(1);
create temp table day as select app_private.business_date(now()) d;
select pg_temp.keep('A', api.create_class('IELTS lớp', '10000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000011', d - 20, d + 20)) from day;
select api.create_class_assignment(pg_temp.id('A'), '00000000-0000-4000-8000-000000000003', 'assistant',
    d - 1, d + 10, null) from day;
select pg_temp.keep(k, api.create_student('IELTS học sinh ' || k))
  from unnest(array['p', 'q', 'r']) k;
select api.enroll_student(pg_temp.id('A'), pg_temp.id(k), d - 15)
  from day, unnest(array['p', 'q', 'r']) k;

select pg_temp.keep('full', api.create_test(pg_temp.id('A'), 'IELTS đủ', d, null,
  '{"scaleKind":"ielts","showComponents":true,"skills":[
     {"code":"L","inputMode":"detailed","maxQuestions":40},{"code":"R","inputMode":"direct"},
     {"code":"W","inputMode":"detailed"},{"code":"S","inputMode":"detailed"}]}', null)) from day;
select pg_temp.keep('lr', api.create_test(pg_temp.id('A'), 'IELTS L/R', d, null,
  '{"scaleKind":"ielts","showComponents":false,"skills":[
     {"code":"L","inputMode":"detailed","maxQuestions":40},{"code":"R","inputMode":"direct"}]}', null)) from day;

-------------------------------------------------------------------------------
-- Writing: Task rounded first, then 1:2 (6,0 and 6,5 give 6,5).
-------------------------------------------------------------------------------
select pg_temp.save('full', 'p', pg_temp.skills('{"W":{"criteria":{
  "t1_ta":6,"t1_cc":6,"t1_lr":6,"t1_gra":6.5,"t2_tr":6,"t2_cc":6,"t2_lr":6.5,"t2_gra":6.5}}}'));
select is(pg_temp.result('full', 'p') -> 'ielts' -> 'W' ->> 'task1Band', '6', 'Task 1 6;6;6;6,5 gives 6,0');
select is(pg_temp.result('full', 'p') -> 'ielts' -> 'W' ->> 'task2Band', '6.5', 'Task 2 6;6;6,5;6,5 gives 6,5');
select is(pg_temp.result('full', 'p') -> 'ielts' -> 'W' ->> 'band', '6.5',
  'Writing = roundBand((6,0 + 2 x 6,5) / 3) = 6,5');
select is((pg_temp.result('full', 'p') ->> 'complete')::boolean, false, 'other skills are still missing');
select is(pg_temp.result('full', 'p') ->> 'overallBand', null, 'no Overall while a band is missing');

-------------------------------------------------------------------------------
-- L/R: typed values kept, no conversion; missing input is not 0.
-------------------------------------------------------------------------------
select pg_temp.save('full', 'p', pg_temp.skills('{"L":{"correctAnswers":30,"band":6.5},"R":{"band":7},
  "W":{"criteria":{"t1_ta":6,"t1_cc":6,"t1_lr":6,"t1_gra":6.5,"t2_tr":6,"t2_cc":6,"t2_lr":6.5,"t2_gra":6.5}},
  "S":{"criteria":{"fc":7,"lr":6.5,"gra":6.5}}}'));
select is(pg_temp.result('full', 'p') -> 'ielts' -> 'L',
  '{"band":6.5,"criteria":{},"inputBand":6.5,"task1Band":null,"task2Band":null,"correctAnswers":30}'::jsonb,
  '30 answers and band 6,5 are kept as typed');
select is(pg_temp.result('full', 'p') -> 'ielts' -> 'S' ->> 'band', null,
  'Speaking with three criteria has no band (a missing criterion is not 0)');
select is((pg_temp.result('full', 'p') ->> 'complete')::boolean, false, 'a missing criterion leaves it incomplete');
select throws_ok($$select api.publish_test_results(pg_temp.id('full'), pg_temp.id('p'), true)$$,
  'PT409', 'result_incomplete', 'a four-skill test missing S cannot be published');

select pg_temp.save('full', 'p', pg_temp.skills('{"L":{"correctAnswers":30,"band":6.5},"R":{"band":7},
  "W":{"criteria":{"t1_ta":6,"t1_cc":6,"t1_lr":6,"t1_gra":6.5,"t2_tr":6,"t2_cc":6,"t2_lr":6.5,"t2_gra":6.5}},
  "S":{"criteria":{"fc":7,"lr":6.5,"gra":6.5,"pronunciation":7}}}'));
select is(pg_temp.result('full', 'p') -> 'ielts' -> 'S' ->> 'band', '7', 'Speaking 6,75 rounds to 7,0');
select is(pg_temp.result('full', 'p') ->> 'overallBand', '7', 'Overall = roundBand((6,5 + 7 + 6,5 + 7) / 4)');
select is((pg_temp.result('full', 'p') ->> 'complete')::boolean, true, 'four complete skills complete the result');
select lives_ok($$select api.publish_test_results(pg_temp.id('full'), pg_temp.id('p'), true)$$,
  'a complete four-skill result is published');
select throws_ok($$select pg_temp.save('full', 'p', pg_temp.skills('{"R":{"band":8}}'))$$,
  'PT409', 'result_published', 'a published IELTS result is locked');
select api.publish_test_results(pg_temp.id('full'), pg_temp.id('p'), false);

-------------------------------------------------------------------------------
-- One to three skills: no Overall, publishable once the chosen skills are complete.
-------------------------------------------------------------------------------
select pg_temp.save('lr', 'p', pg_temp.skills('{"L":{"correctAnswers":30},"R":{"band":7}}'));
select is((pg_temp.result('lr', 'p') ->> 'complete')::boolean, false,
  'L in detail needs both the answers and the band');
select pg_temp.save('lr', 'p', pg_temp.skills('{"L":{"correctAnswers":30,"band":6.5},"R":{"band":7}}'));
select is((pg_temp.result('lr', 'p') ->> 'complete')::boolean, true, 'L/R complete');
select is(pg_temp.result('lr', 'p') ->> 'overallBand', null, 'a two-skill test has no Overall');
select lives_ok($$select api.publish_test_results(pg_temp.id('lr'), pg_temp.id('p'), true)$$,
  'a complete two-skill result is published without Overall');
select is((select count(*)::int from app.audit_events where action = 'test_result.save'), 5,
  'each IELTS save writes one audit');

-------------------------------------------------------------------------------
-- Refused input: off-step, out of range, computed values, wrong mode or skill.
-------------------------------------------------------------------------------
select throws_ok(format('select pg_temp.save(%L, %L, pg_temp.skills(%L))', 'full', 'q', e),
    'PT400', 'validation_failed', 'refused: ' || e::text)
  from unnest(array[
    '{"R":{"band":6.3}}', '{"R":{"band":9.5}}', '{"R":{"band":-0.5}}', '{"R":{"band":"7"}}',
    '{"L":{"correctAnswers":41}}', '{"L":{"correctAnswers":2.5}}', '{"R":{"correctAnswers":20}}',
    '{"W":{"band":6.5}}', '{"W":{"criteria":{"fc":6}}}', '{"S":{"criteria":{"t1_ta":6}}}',
    '{"S":{"criteria":{"fc":6.25}}}', '{"W":{"criteria":{"t1_ta":6},"band":6}}',
    '{"R":{"band":null}}', '{}'
  ]::jsonb[]) e;
select throws_ok($$select pg_temp.save('lr', 'q', pg_temp.skills('{"S":{"band":6}}'))$$,
  'PT400', 'validation_failed', 'a skill outside the test is refused');
select throws_ok($$select pg_temp.save('full', 'q',
    '{"absent":false,"skills":{"R":{"band":7}},"overallBand":9}')$$,
  'PT400', 'validation_failed', 'Overall is never accepted from the client');
select throws_ok($$select pg_temp.save('full', 'q', '{"absent":false,"score":7}')$$,
  'PT400', 'validation_failed', 'a numeric score does not apply to IELTS');

-------------------------------------------------------------------------------
-- Absent, unchanged content and assistants.
-------------------------------------------------------------------------------
select pg_temp.save('full', 'q', '{"absent":true}');
select is(pg_temp.result('full', 'q') ->> 'ielts', null, 'Absent has no band or IELTS rows');
select is((pg_temp.result('full', 'q') ->> 'complete')::boolean, true, 'Absent is complete');
select is((select count(*)::int from app.ielts_skill_results x join app.test_results r on r.id = x.result_id
            where r.test_id = pg_temp.id('full') and r.student_id = pg_temp.id('q')), 0,
  'no band 0 or fake component is created for Absent');
select pg_temp.save('lr', 'r', pg_temp.skills('{"R":{"band":5.5}}'));
select pg_temp.save('lr', 'r', pg_temp.skills('{"R":{"band":5.50},"L":null}'));
select is((pg_temp.result('lr', 'r') ->> 'rowVersion')::int, 1, 'unchanged IELTS content writes no version');

select pg_temp.actor(3);
select lives_ok($$select pg_temp.save('lr', 'r', pg_temp.skills('{"R":{"band":6}}'))$$,
  'an assistant enters IELTS results');
select throws_ok($$select api.publish_test_results(pg_temp.id('lr'), pg_temp.id('r'), true)$$,
  'PT403', 'forbidden', 'an assistant cannot publish IELTS results');

select * from finish();
rollback;
