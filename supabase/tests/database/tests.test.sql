-- Tests of a class with their own grading snapshot (TEST-05; TEST-01/04
-- configuration; use of TEST-02 templates): academic rights, snapshot
-- independence from templates, immutable revisions, commit-time validation of
-- the relational snapshot and audit atomicity.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Seed fixtures: 1 admin, 2 receptionist, 3 user.
insert into auth.sessions (id, user_id, created_at, updated_at)
select format('26000000-0000-4000-8000-%s', lpad(n::text, 12, '0'))::uuid,
       format('00000000-0000-4000-8000-%s', lpad(n::text, 12, '0'))::uuid,
       now() - interval '1 minute', now()
  from generate_series(1, 3) n;
insert into auth.mfa_amr_claims (id, session_id, created_at, updated_at, authentication_method)
select gen_random_uuid(), s.id, now(), now(), 'password'
  from auth.sessions s where s.id::text like '26000000%';

create function pg_temp.actor(p_user int)
returns void
language sql
as $$
  select set_config('request.jwt.claims', json_build_object(
    'sub', format('00000000-0000-4000-8000-%s', lpad(p_user::text, 12, '0')),
    'session_id', format('26000000-0000-4000-8000-%s', lpad(p_user::text, 12, '0')),
    'role', 'authenticated')::text, true);
$$;

create temp table ids (key text primary key, id uuid, version bigint);
create function pg_temp.id(p_key text) returns uuid language sql as $$ select id from ids where key = p_key $$;
create function pg_temp.ver(p_key text) returns bigint language sql as $$ select version from ids where key = p_key $$;
create function pg_temp.keep(p_key text, p_dto jsonb) returns jsonb language sql as $$
  insert into ids values (p_key, (p_dto ->> 'id')::uuid, (p_dto ->> 'rowVersion')::bigint)
  on conflict (key) do update set id = excluded.id, version = excluded.version
  returning p_dto
$$;

-------------------------------------------------------------------------------
-- Privileges.
-------------------------------------------------------------------------------
select ok(not has_table_privilege('authenticated', 'app.tests', 'select')
       and not has_table_privilege('authenticated', 'app.test_config_versions', 'select')
       and not has_table_privilege('authenticated', 'app.test_components', 'insert')
       and not has_table_privilege('anon', 'app.test_letter_levels', 'select')
       and not has_table_privilege('anon', 'app.test_ielts_skills', 'select'),
  'test tables are not exposed to clients');
select ok(not has_function_privilege('anon', 'api.create_test(uuid, text, date, text, jsonb, uuid)', 'execute')
       and not has_function_privilege('anon', 'api.list_class_tests(uuid)', 'execute')
       and has_function_privilege('authenticated', 'api.create_test(uuid, text, date, text, jsonb, uuid)', 'execute'),
  'anon cannot call test RPCs');

-------------------------------------------------------------------------------
-- Fixture: classes A (user 3 teacher), B (user 3 assistant), C (no role).
-------------------------------------------------------------------------------
select pg_temp.actor(1);
create temp table day as select app_private.business_date(now()) d;
select pg_temp.keep(k, api.create_class('Bài kiểm tra ' || k, '10000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000011', d - 10, d + 20))
  from day, unnest(array['A', 'B', 'C']) k;
select api.create_class_assignment(pg_temp.id('A'), '00000000-0000-4000-8000-000000000003', 'teacher',
    d - 1, d + 10, null) from day;
select api.create_class_assignment(pg_temp.id('B'), '00000000-0000-4000-8000-000000000003', 'assistant',
    d - 1, d + 10, null) from day;
select pg_temp.keep('tpl', api.create_test_template('Mẫu chữ', null,
  '{"scaleKind":"letter","inputMode":"direct","levels":[{"label":"Chưa đạt"},{"label":"Đạt"}]}'));
insert into ids select 'tpl_v1', (current_version_id), null from app.test_templates where id = pg_temp.id('tpl');

-------------------------------------------------------------------------------
-- Creation from scratch (Admin).
-------------------------------------------------------------------------------
select pg_temp.keep('t1', api.create_test(pg_temp.id('A'), '  Giữa kỳ  ', d, '',
    '{"scaleKind":"numeric","inputMode":"components","showComponents":true,
      "components":[{"name":"Nghe","maxScore":1.25},{"name":"Viết","maxScore":2.10}]}', null))
  from day;
select is((select api.get_test(pg_temp.id('t1')) - 'id' - 'classId' - 'configId' - 'createdAt'
             - 'updatedAt' - 'testOn' - 'configVersions'),
  '{"name":"Giữa kỳ","description":null,"showComponents":true,"configRevision":1,"source":null,
    "deleted":false,"createdByName":"Quản trị Thử nghiệm","rowVersion":1,"resultCount":0,
    "config":{"scaleKind":"numeric","inputMode":"components","maxScore":3.35,"showComponents":true,
      "components":[{"code":"c1","name":"Nghe","maxScore":1.25},{"code":"c2","name":"Viết","maxScore":2.1}]}}'::jsonb,
  'a test created from scratch stores a trimmed name, an empty description as NULL and a normalized snapshot');
select is((select count(*)::int from app.test_components c join app.tests t on t.current_config_id = c.config_id
            where t.id = pg_temp.id('t1')), 2, 'components are stored as rows of the snapshot');
select is((select count(*)::int from app.audit_events where action = 'test.create'), 1,
  'creation writes one audit');
select is((select count(*)::int from app.business_entity_versions
            where entity_kind = 'test' and entity_id = pg_temp.id('t1')), 1,
  'creation writes one business version');
select lives_ok($$set constraints all immediate$$, 'the snapshot passes the commit-time checks');
set constraints all deferred;

select throws_ok($$select api.create_test(pg_temp.id('A'), '   ', d, null,
    '{"scaleKind":"numeric","inputMode":"direct","maxScore":10}', null) from day$$,
  'PT400', 'validation_failed', 'a name is required');
select throws_ok($$select api.create_test(pg_temp.id('A'), 'Không ngày', null, null,
    '{"scaleKind":"numeric","inputMode":"direct","maxScore":10}', null)$$,
  'PT400', 'validation_failed', 'a test date is required');
select throws_ok($$select api.create_test(pg_temp.id('A'), 'Ngoài lớp', d + 21, null,
    '{"scaleKind":"numeric","inputMode":"direct","maxScore":10}', null) from day$$,
  'PT409', 'outside_class_dates', 'the test date must lie within the class dates');
select throws_ok($$select api.create_test(pg_temp.id('A'), 'Trước lớp', d - 11, null,
    '{"scaleKind":"numeric","inputMode":"direct","maxScore":10}', null) from day$$,
  'PT409', 'outside_class_dates', 'a date before the class start is refused');
select throws_ok($$select api.create_test(pg_temp.id('A'), 'Ba số lẻ', d, null,
    '{"scaleKind":"numeric","inputMode":"direct","maxScore":8.255}', null) from day$$,
  'PT400', 'validation_failed', 'more than two decimals are refused, not rounded');
select throws_ok($$select api.create_test(pg_temp.id('A'), 'Thiếu cấu hình', d, null, null, null) from day$$,
  'PT400', 'validation_failed', 'a grading configuration is required');
select lives_ok($$select api.create_test(pg_temp.id('A'), 'Giữa kỳ', d, 'Trùng tên',
    '{"scaleKind":"fraction","inputMode":"direct","totalQuestions":40}', null) from day$$,
  'duplicate test names are allowed in a class');
select is((select count(*)::int from app.tests where class_id = pg_temp.id('A') and name = 'Giữa kỳ'), 2,
  'both tests with the same name exist');

-------------------------------------------------------------------------------
-- Academic rights.
-------------------------------------------------------------------------------
select pg_temp.actor(2);
select throws_ok($$select api.list_class_tests(pg_temp.id('A'))$$, 'PT403', 'forbidden',
  'receptionists cannot read tests');
select throws_ok($$select api.create_test(pg_temp.id('A'), 'Lễ tân', d, null,
    '{"scaleKind":"numeric","inputMode":"direct","maxScore":10}', null) from day$$,
  'PT403', 'forbidden', 'receptionists cannot create tests');
select throws_ok($$select api.list_test_template_choices(pg_temp.id('A'))$$, 'PT403', 'forbidden',
  'receptionists cannot pick templates');

select pg_temp.actor(3);
select is((select api.list_class_tests(pg_temp.id('A')) - 'items'),
  '{"canEdit":true,"canChangeDisplay":true}'::jsonb, 'a current teacher may edit and change display');
select is((select api.list_class_tests(pg_temp.id('B')) - 'items'),
  '{"canEdit":true,"canChangeDisplay":false}'::jsonb, 'a current assistant may edit but not change display');
select throws_ok($$select api.list_class_tests(pg_temp.id('C'))$$, 'PT404', 'not_found',
  'a User without an assignment does not see the class tests');
select throws_ok($$select api.create_test(pg_temp.id('C'), 'Không phân công', d, null,
    '{"scaleKind":"numeric","inputMode":"direct","maxScore":10}', null) from day$$,
  'PT404', 'not_found', 'a User without an assignment cannot create tests');
select is(jsonb_array_length(api.list_test_template_choices(pg_temp.id('B'))), 1,
  'an assistant may read the current templates to pick one');

-------------------------------------------------------------------------------
-- Creation from a template, adjusted (assistant), and template independence.
-------------------------------------------------------------------------------
select pg_temp.keep('t2', api.create_test(pg_temp.id('B'), 'Đánh giá', d, null,
    '{"scaleKind":"letter","inputMode":"direct","levels":[{"label":"Chưa đạt"},{"label":"Đạt"},{"label":"Giỏi"}]}',
    pg_temp.id('tpl_v1'))) from day;
select is((select (api.get_test(pg_temp.id('t2')) -> 'source') - 'templateId'),
  jsonb_build_object('templateVersionId', pg_temp.id('tpl_v1'), 'revision', 1, 'name', 'Mẫu chữ',
                     'templateArchived', false),
  'the exact source version is kept as provenance');
select is((select api.get_test(pg_temp.id('t2')) #> '{config,levels,2}'),
  '{"code":"l3","label":"Giỏi"}'::jsonb, 'the copy holds the adjusted configuration');
select is((select (config -> 'levels') from app.test_template_versions where id = pg_temp.id('tpl_v1')),
  '[{"code":"l1","label":"Chưa đạt"},{"code":"l2","label":"Đạt"}]'::jsonb,
  'adjusting the copy never writes the template');
select is((select count(*)::int from app.test_letter_levels l join app.tests t on t.current_config_id = l.config_id
            where t.id = pg_temp.id('t2')), 3, 'letter levels are stored as rows of the snapshot');

select pg_temp.actor(1);
select pg_temp.keep('tpl', api.update_test_template(pg_temp.id('tpl'), 'Mẫu chữ', null,
  '{"scaleKind":"numeric","inputMode":"direct","maxScore":10}', pg_temp.ver('tpl')));
select is((select api.get_test(pg_temp.id('t2')) #>> '{config,scaleKind}'), 'letter',
  'editing the template leaves the test configuration unchanged');
select throws_ok($$select api.create_test(pg_temp.id('A'), 'Phiên bản cũ', d, null,
    '{"scaleKind":"numeric","inputMode":"direct","maxScore":10}', pg_temp.id('tpl_v1')) from day$$,
  'PT409', 'template_unavailable', 'a version that is no longer current cannot be chosen');
insert into ids select 'tpl_v2', current_version_id, null from app.test_templates where id = pg_temp.id('tpl');
select pg_temp.keep('t3', api.create_test(pg_temp.id('A'), 'Phiên bản mới', d, null,
    '{"scaleKind":"numeric","inputMode":"direct","maxScore":10}', pg_temp.id('tpl_v2'))) from day;
select pg_temp.keep('tpl', api.archive_test_template(pg_temp.id('tpl'), 'Ngừng dùng', pg_temp.ver('tpl')));
select throws_ok($$select api.create_test(pg_temp.id('A'), 'Mẫu lưu trữ', d, null,
    '{"scaleKind":"numeric","inputMode":"direct","maxScore":10}', pg_temp.id('tpl_v2')) from day$$,
  'PT409', 'template_unavailable', 'an archived template cannot be chosen');
select is(jsonb_array_length(api.list_test_template_choices(pg_temp.id('A'))), 0,
  'archived templates are not offered');
select is((select api.get_test(pg_temp.id('t3')) #>> '{source,templateArchived}'), 'true',
  'tests keep their source after the template is archived');
select throws_ok($$select api.create_test(pg_temp.id('A'), 'Không tồn tại', d, null,
    '{"scaleKind":"numeric","inputMode":"direct","maxScore":10}', gen_random_uuid()) from day$$,
  'PT404', 'not_found', 'an unknown template version is refused');

-------------------------------------------------------------------------------
-- New configuration and display option.
-------------------------------------------------------------------------------
select pg_temp.actor(3);
-- Keeping an archived template's provenance does not check the template again.
select is((select api.change_test_config(pg_temp.id('t3'),
    '{"scaleKind":"numeric","inputMode":"direct","maxScore":20}', pg_temp.id('tpl_v2'), 1)
    -> 'configRevision'), '2'::jsonb, 'a teacher adjusts a test copied from an archived template');
select pg_temp.keep('t3', api.get_test(pg_temp.id('t3')));
select is((select api.change_test_config(pg_temp.id('t3'),
    '{"scaleKind":"numeric","inputMode":"direct","maxScore":20}', pg_temp.id('tpl_v2'), pg_temp.ver('t3'))
    -> 'rowVersion')::bigint, pg_temp.ver('t3'), 'an unchanged configuration creates no revision');

select pg_temp.keep('t2', api.change_test_config(pg_temp.id('t2'),
    '{"scaleKind":"numeric","inputMode":"direct","maxScore":10}', null, pg_temp.ver('t2')));
select is((select api.get_test(pg_temp.id('t2')) -> 'configVersions' -> 1 ->> 'scaleKind'), 'letter',
  'the previous snapshot is kept in the history');
select is((select api.get_test(pg_temp.id('t2')) -> 'source'), 'null'::jsonb,
  'a custom configuration has no source');
select is((select count(*)::int from app.test_letter_levels l join app.test_config_versions c on c.id = l.config_id
            where c.test_id = pg_temp.id('t2')), 3, 'rows of the earlier snapshot are kept');
select throws_ok($$select api.change_test_config(pg_temp.id('t2'),
    '{"scaleKind":"numeric","inputMode":"components","showComponents":true,
      "components":[{"name":"A","maxScore":5},{"name":"B","maxScore":5}]}', null, pg_temp.ver('t2'))$$,
  'PT403', 'forbidden', 'an assistant cannot turn on the display option through a new configuration');
select pg_temp.keep('t2', api.change_test_config(pg_temp.id('t2'),
    '{"scaleKind":"numeric","inputMode":"components","showComponents":false,
      "components":[{"name":"A","maxScore":5},{"name":"B","maxScore":5}]}', null, pg_temp.ver('t2')));
select is((select (api.get_test(pg_temp.id('t2')) ->> 'configRevision')::int), 3,
  'an assistant may change the structure while keeping the display option');
select throws_ok($$select api.set_test_show_components(pg_temp.id('t2'), true, pg_temp.ver('t2'))$$,
  'PT403', 'forbidden', 'an assistant cannot change the display option');
select throws_ok($$select api.change_test_config(pg_temp.id('t2'),
    '{"scaleKind":"numeric","inputMode":"direct","maxScore":10}', null, pg_temp.ver('t2') - 1)$$,
  'PT409', 'version_conflict', 'a stale configuration change is refused');

select pg_temp.actor(1);
select is((select api.set_test_show_components(pg_temp.id('t2'), true, pg_temp.ver('t2')) -> 'config' ->> 'showComponents'),
  'true', 'Admin turns on the display option without a new snapshot');
select is((select (api.get_test(pg_temp.id('t2')) ->> 'configRevision')::int), 3,
  'the display option adds no configuration revision');
select throws_ok($$select api.set_test_show_components(pg_temp.id('t3'), true, pg_temp.ver('t3'))$$,
  'PT409', 'invalid_state', 'a direct configuration has no details to show');
select is((select count(*)::int from app.audit_events where action = 'test.set_show_components'), 1,
  'the display change is audited');

-------------------------------------------------------------------------------
-- Information edits (TEST-05).
-------------------------------------------------------------------------------
select pg_temp.actor(3);
select pg_temp.keep('t1', api.update_test(pg_temp.id('t1'), 'Giữa kỳ I', d - 1, 'Mô tả', 1)) from day;
select is((select api.get_test(pg_temp.id('t1')) ->> 'name'), 'Giữa kỳ I', 'a teacher renames the test');
select is((select (api.get_test(pg_temp.id('t1')) ->> 'configRevision')::int), 1,
  'editing information does not change the configuration');
select throws_ok($$select api.update_test(pg_temp.id('t1'), 'Cũ', d, null, 1) from day$$,
  'PT409', 'version_conflict', 'a stale information edit is refused');
select throws_ok($$select api.update_test(pg_temp.id('t1'), 'Ngoài', d + 30, null, pg_temp.ver('t1')) from day$$,
  'PT409', 'outside_class_dates', 'the date cannot move outside the class dates');
select is((select (api.update_test(pg_temp.id('t1'), 'Giữa kỳ I', d - 1, 'Mô tả', pg_temp.ver('t1'))
            ->> 'rowVersion')::bigint from day), pg_temp.ver('t1'),
  'unchanged information creates no version');

-------------------------------------------------------------------------------
-- Immutability and commit-time validation of the relational snapshot.
-------------------------------------------------------------------------------
select throws_ok($$update app.test_config_versions set max_score = 99 where test_id = pg_temp.id('t1')$$,
  '42501', 'append_only', 'snapshots cannot be edited in place');
select throws_ok($$delete from app.test_components where config_id in
    (select id from app.test_config_versions where test_id = pg_temp.id('t1'))$$,
  '42501', 'append_only', 'snapshot rows cannot be deleted');
select throws_ok($$delete from app.tests where id = pg_temp.id('t1')$$,
  '42501', 'append_only', 'tests are never deleted');

savepoint before_bad_snapshot;
insert into app.tests (id, class_id, name, name_key, test_on, current_config_id, created_by)
select '30000000-0000-4000-8000-000000000001', pg_temp.id('A'), 'Ngoài luồng', 'ngoai luong', d,
       '30000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000001' from day;
insert into app.test_config_versions (id, test_id, revision, scale_kind, input_mode, max_score, created_by)
values ('30000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000001', 1, 'numeric',
        'components', 5, '00000000-0000-4000-8000-000000000001');
insert into app.test_components (config_id, code, name, name_key, max_score, sort_order)
values ('30000000-0000-4000-8000-000000000002', 'c1', 'A', 'a', 2, 1);
select throws_ok($$set constraints all immediate$$, 'PT400', 'validation_failed',
  'a total that differs from its component rows is refused at commit');
rollback to savepoint before_bad_snapshot;
set constraints all deferred;

savepoint before_letterless;
insert into app.tests (id, class_id, name, name_key, test_on, current_config_id, created_by)
select '30000000-0000-4000-8000-000000000003', pg_temp.id('A'), 'Không mức', 'khong muc', d,
       '30000000-0000-4000-8000-000000000004', '00000000-0000-4000-8000-000000000001' from day;
insert into app.test_config_versions (id, test_id, revision, scale_kind, input_mode, created_by)
values ('30000000-0000-4000-8000-000000000004', '30000000-0000-4000-8000-000000000003', 1, 'letter',
        'direct', '00000000-0000-4000-8000-000000000001');
select throws_ok($$set constraints all immediate$$, 'PT400', 'validation_failed',
  'a letter snapshot without levels is refused at commit');
rollback to savepoint before_letterless;
set constraints all deferred;

savepoint before_ielts;
select lives_ok($$select api.create_test(pg_temp.id('A'), 'IELTS', d, null,
    '{"scaleKind":"ielts","showComponents":true,"skills":[{"code":"W","inputMode":"detailed"},
      {"code":"L","inputMode":"detailed","maxQuestions":40}]}', null) from day$$,
  'an IELTS test with two skills is created');
select is((select api.get_test(id) -> 'config' from app.tests where name = 'IELTS'),
  '{"scaleKind":"ielts","formulaVersion":"mledu-ielts-v1","showComponents":true,"skills":[
    {"code":"L","inputMode":"detailed","maxQuestions":40},{"code":"W","inputMode":"detailed"}]}'::jsonb,
  'IELTS skills come back in L/R/W/S order with the backend formula version');
select lives_ok($$set constraints all immediate$$, 'the IELTS snapshot passes the commit-time checks');
rollback to savepoint before_ielts;
set constraints all deferred;

-- Commit-time checks also run for the API role, outside SECURITY DEFINER.
savepoint before_client_role;
grant select on ids, day to authenticated;
set local role authenticated;
select lives_ok($$select api.create_test((select id from ids where key = 'A'), 'Vai trò API', d, null,
    '{"scaleKind":"letter","inputMode":"direct","levels":[{"label":"Đạt"}]}', null) from day$$,
  'the API role creates a test');
select lives_ok($$set constraints all immediate$$, 'commit-time checks run for the API role');
reset role;
rollback to savepoint before_client_role;
set constraints all deferred;

-------------------------------------------------------------------------------
-- Atomicity, revoked rights and deleted classes.
-------------------------------------------------------------------------------
create function pg_temp.fail_audit() returns trigger language plpgsql as $$
begin raise exception 'audit_failure'; end $$;
create trigger zz_test_fail_audit before insert on app.audit_events
  for each row execute function pg_temp.fail_audit();
select throws_ok($$select api.create_test(pg_temp.id('A'), 'Lỗi audit', d, null,
    '{"scaleKind":"numeric","inputMode":"direct","maxScore":10}', null) from day$$,
  'P0001', 'audit_failure', 'audit failure aborts the creation');
select throws_ok($$select api.change_test_config(pg_temp.id('t1'),
    '{"scaleKind":"numeric","inputMode":"direct","maxScore":10}', null, pg_temp.ver('t1'))$$,
  'P0001', 'audit_failure', 'audit failure aborts the configuration change');
drop trigger zz_test_fail_audit on app.audit_events;
select is((select count(*)::int from app.tests where name = 'Lỗi audit'), 0,
  'no test is left behind by the failed creation');
select is((select count(*)::int from app.test_config_versions where test_id = pg_temp.id('t1')), 1,
  'no snapshot is left behind by the failed change');

select pg_temp.actor(1);
select api.end_class_assignment(id, 'Thu hồi', row_version) from app.class_assignments
 where account_id = '00000000-0000-4000-8000-000000000003' and class_id = pg_temp.id('A');
select pg_temp.actor(3);
select throws_ok($$select api.update_test(pg_temp.id('t1'), 'Sau thu hồi', d, null, pg_temp.ver('t1')) from day$$,
  'PT404', 'not_found', 'a revoked assignment stops writes from the old session');
select throws_ok($$select api.get_test(pg_temp.id('t1'))$$, 'PT404', 'not_found',
  'a revoked assignment stops reads');

select pg_temp.actor(1);
select api.soft_delete_class(pg_temp.id('C'), 'Lưu trữ', row_version) from app.classes where id = pg_temp.id('C');
select throws_ok($$select api.create_test(pg_temp.id('C'), 'Lớp đã xóa', d, null,
    '{"scaleKind":"numeric","inputMode":"direct","maxScore":10}', null) from day$$,
  'PT409', 'invalid_state', 'no test is created in a deleted class');
select is((select api.list_class_tests(pg_temp.id('C')) - 'items'),
  '{"canEdit":false,"canChangeDisplay":false}'::jsonb, 'Admin reads a deleted class read-only');

-- A former teacher whose account became a receptionist loses every academic right.
update app.account_profiles set account_type = 'receptionist' where id = '00000000-0000-4000-8000-000000000003';
select pg_temp.actor(3);
select throws_ok($$select api.list_class_tests(pg_temp.id('B'))$$, 'PT403', 'forbidden',
  'the current account type is checked, not the session');

select * from finish();
rollback;
