-- Shared test template library (TEST-02): typed configuration validator
-- (TEST-01/04 shapes), Admin-only commands, immutable versions, archive/restore
-- and audit atomicity.
begin;
create extension if not exists pgtap with schema extensions;
select plan(67);

-- Seed fixtures: 1 admin, 2 receptionist, 3 user.
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

create function pg_temp.cfg(p_config text)
returns jsonb
language sql
as $$ select app_private.test_template_config(p_config::jsonb) $$;

create temp table ids (key text primary key, id uuid, version bigint);
grant all on ids to authenticated;

-------------------------------------------------------------------------------
-- Privileges.
-------------------------------------------------------------------------------
select ok(not has_table_privilege('authenticated', 'app.test_templates', 'select')
       and not has_table_privilege('authenticated', 'app.test_template_versions', 'select')
       and not has_table_privilege('anon', 'app.test_templates', 'select'),
  'template tables are not exposed to clients');
select ok(not has_function_privilege('anon', 'api.list_test_templates(boolean)', 'execute')
       and not has_function_privilege('anon', 'api.create_test_template(text, text, jsonb)', 'execute')
       and not has_function_privilege('authenticated', 'app_private.test_template_config(jsonb)', 'execute'),
  'anon cannot call template RPCs and clients cannot call the validator');

-------------------------------------------------------------------------------
-- Configuration validator (schema version 1).
-------------------------------------------------------------------------------
select is(pg_temp.cfg('{"scaleKind":"numeric","inputMode":"direct","maxScore":10.50}'),
  '{"scaleKind":"numeric","inputMode":"direct","maxScore":10.5}'::jsonb,
  'numeric direct keeps the maximum and drops trailing zeros');
select throws_ok($$select pg_temp.cfg('{"scaleKind":"numeric","inputMode":"direct","maxScore":8.255}')$$,
  'PT400', 'validation_failed', 'more than two decimals are refused, not rounded');
select throws_ok($$select pg_temp.cfg('{"scaleKind":"numeric","inputMode":"direct","maxScore":0}')$$,
  'PT400', 'validation_failed', 'a maximum must be positive');
select throws_ok($$select pg_temp.cfg('{"scaleKind":"numeric","inputMode":"direct","maxScore":"10"}')$$,
  'PT400', 'validation_failed', 'scores must be JSON numbers');
select is(pg_temp.cfg('{"scaleKind":"numeric","inputMode":"components","showComponents":true,
    "components":[{"name":" Nghe ","maxScore":1.25},{"name":"Đọc","maxScore":2.10}]}'),
  '{"scaleKind":"numeric","inputMode":"components","maxScore":3.35,"showComponents":true,
    "components":[{"code":"c1","name":"Nghe","maxScore":1.25},{"code":"c2","name":"Đọc","maxScore":2.1}]}'::jsonb,
  'components get positional codes and their exact sum (1,25 + 2,10 = 3,35)');
select throws_ok($$select pg_temp.cfg('{"scaleKind":"numeric","inputMode":"components","showComponents":false,
    "maxScore":4,"components":[{"name":"A","maxScore":1.25},{"name":"B","maxScore":2.1}]}')$$,
  'PT400', 'validation_failed', 'a total that differs from the sum of components is refused');
select lives_ok($$select pg_temp.cfg('{"scaleKind":"numeric","inputMode":"components","showComponents":false,
    "maxScore":3.35,"components":[{"name":"A","maxScore":1.25},{"name":"B","maxScore":2.1}]}')$$,
  'a total equal to the sum is accepted');
select is(jsonb_array_length(app_private.test_template_config(jsonb_build_object(
    'scaleKind', 'numeric', 'inputMode', 'components', 'showComponents', false,
    'components', (select jsonb_agg(jsonb_build_object('name', 'Phần ' || n, 'maxScore', 1))
                     from generate_series(1, 50) n))) -> 'components'), 50,
  '50 components are accepted');
select throws_ok($$select app_private.test_template_config(jsonb_build_object(
    'scaleKind', 'numeric', 'inputMode', 'components', 'showComponents', false,
    'components', (select jsonb_agg(jsonb_build_object('name', 'Phần ' || n, 'maxScore', 1))
                     from generate_series(1, 51) n)))$$,
  'PT400', 'validation_failed', '51 components are refused');
select throws_ok($$select pg_temp.cfg('{"scaleKind":"numeric","inputMode":"components","showComponents":false,
    "components":[]}')$$, 'PT400', 'validation_failed', 'components mode needs at least one component');
select throws_ok($$select pg_temp.cfg('{"scaleKind":"numeric","inputMode":"components","showComponents":false,
    "components":[{"name":"Phần 1","maxScore":1},{"name":"phan  1","maxScore":2}]}')$$,
  'PT400', 'validation_failed', 'component names are unique by name key');
select throws_ok($$select pg_temp.cfg('{"scaleKind":"numeric","inputMode":"components","showComponents":false,
    "components":[{"code":"c9","name":"A","maxScore":1}]}')$$,
  'PT400', 'validation_failed', 'a component code other than its positional code is refused');
select throws_ok($$select pg_temp.cfg('{"scaleKind":"numeric","inputMode":"components",
    "components":[{"name":"A","maxScore":1}]}')$$,
  'PT400', 'validation_failed', 'components mode needs the show-components option');
select throws_ok($$select pg_temp.cfg('{"scaleKind":"numeric","inputMode":"direct","maxScore":10,
    "totalQuestions":10}')$$, 'PT400', 'validation_failed', 'keys of another scale are refused');
select is(pg_temp.cfg('{"scaleKind":"fraction","inputMode":"components","showComponents":false,
    "components":[{"name":"Trắc nghiệm","totalQuestions":30},{"name":"Tự luận","totalQuestions":10}]}')
    -> 'totalQuestions', '40'::jsonb, 'fraction components add up the question counts');
select throws_ok($$select pg_temp.cfg('{"scaleKind":"fraction","inputMode":"direct","totalQuestions":1.5}')$$,
  'PT400', 'validation_failed', 'question counts are integers');
select throws_ok($$select pg_temp.cfg('{"scaleKind":"fraction","inputMode":"direct","totalQuestions":0}')$$,
  'PT400', 'validation_failed', 'question counts are positive');

select is(pg_temp.cfg('{"scaleKind":"letter","inputMode":"direct",
    "levels":[{"label":"Chưa đạt"},{"label":"Đạt"},{"label":"Tốt"},{"label":"Xuất sắc"}]}') -> 'levels' -> 3,
  '{"code":"l4","label":"Xuất sắc"}'::jsonb, 'letter levels keep their order and get codes');
select is(jsonb_array_length(app_private.test_template_config(jsonb_build_object(
    'scaleKind', 'letter', 'inputMode', 'direct',
    'levels', (select jsonb_agg(jsonb_build_object('label', 'Mức ' || n)) from generate_series(1, 20) n)))
    -> 'levels'), 20, '20 letter levels are accepted');
select throws_ok($$select app_private.test_template_config(jsonb_build_object(
    'scaleKind', 'letter', 'inputMode', 'direct',
    'levels', (select jsonb_agg(jsonb_build_object('label', 'Mức ' || n)) from generate_series(1, 21) n)))$$,
  'PT400', 'validation_failed', '21 letter levels are refused');
select throws_ok($$select pg_temp.cfg('{"scaleKind":"letter","inputMode":"direct","levels":[]}')$$,
  'PT400', 'validation_failed', 'an empty letter set is refused');
select throws_ok($$select app_private.test_template_config(jsonb_build_object(
    'scaleKind', 'letter', 'inputMode', 'direct', 'levels', jsonb_build_array(
      jsonb_build_object('label', repeat('a', 101)))))$$,
  'PT400', 'validation_failed', 'letter labels are limited to 100 characters');
select throws_ok($$select pg_temp.cfg('{"scaleKind":"letter","inputMode":"direct",
    "levels":[{"label":"Đạt"},{"label":"dat"}]}')$$,
  'PT400', 'validation_failed', 'letter labels are unique by name key');
select throws_ok($$select pg_temp.cfg('{"scaleKind":"letter","inputMode":"direct","showComponents":true,
    "levels":[{"label":"Đạt"}]}')$$,
  'PT400', 'validation_failed', 'letter scales have no show-components option');

select is(pg_temp.cfg('{"scaleKind":"ielts","showComponents":true,"skills":[
    {"code":"S","inputMode":"direct"},{"code":"W","inputMode":"detailed"},
    {"code":"L","inputMode":"detailed","maxQuestions":40},{"code":"R","inputMode":"direct"}]}'),
  '{"scaleKind":"ielts","formulaVersion":"mledu-ielts-v1","showComponents":true,"skills":[
    {"code":"L","inputMode":"detailed","maxQuestions":40},{"code":"R","inputMode":"direct"},
    {"code":"W","inputMode":"detailed"},{"code":"S","inputMode":"direct"}]}'::jsonb,
  'IELTS skills are ordered L/R/W/S and the backend attaches the formula version');
select is(pg_temp.cfg('{"scaleKind":"ielts","showComponents":false,"skills":[
    {"code":"R","inputMode":"direct"},{"code":"L","inputMode":"direct"}]}') -> 'skills',
  '[{"code":"L","inputMode":"direct"},{"code":"R","inputMode":"direct"}]'::jsonb,
  'an L/R-only IELTS template is valid');
select is(pg_temp.cfg('{"scaleKind":"ielts","showComponents":true,"skills":[{"code":"W","inputMode":"direct"}]}')
    -> 'showComponents', 'false'::jsonb, 'details cannot be shown when every skill is direct');
select throws_ok($$select pg_temp.cfg('{"scaleKind":"ielts","showComponents":false,"skills":[]}')$$,
  'PT400', 'validation_failed', 'an IELTS template needs at least one skill');
select throws_ok($$select pg_temp.cfg('{"scaleKind":"ielts","showComponents":false,"skills":[
    {"code":"L","inputMode":"direct"},{"code":"L","inputMode":"detailed","maxQuestions":40}]}')$$,
  'PT400', 'validation_failed', 'a skill appears once');
select throws_ok($$select pg_temp.cfg('{"scaleKind":"ielts","showComponents":false,"skills":[
    {"code":"L","inputMode":"detailed"}]}')$$,
  'PT400', 'validation_failed', 'detailed L/R need a maximum number of questions');
select throws_ok($$select pg_temp.cfg('{"scaleKind":"ielts","showComponents":false,"skills":[
    {"code":"W","inputMode":"detailed","maxQuestions":2}]}')$$,
  'PT400', 'validation_failed', 'W/S have no question count; their criteria are fixed');
select throws_ok($$select pg_temp.cfg('{"scaleKind":"ielts","showComponents":false,"skills":[
    {"code":"R","inputMode":"direct","maxQuestions":40}]}')$$,
  'PT400', 'validation_failed', 'direct L/R have no question count');
select throws_ok($$select pg_temp.cfg('{"scaleKind":"ielts","showComponents":false,
    "formulaVersion":"custom","skills":[{"code":"S","inputMode":"direct"}]}')$$,
  'PT400', 'validation_failed', 'templates cannot choose another IELTS formula');
select throws_ok($$select pg_temp.cfg('{"scaleKind":"ielts","showComponents":false,"skills":[
    {"code":"S","inputMode":"detailed","weights":[1,1,1,1]}]}')$$,
  'PT400', 'validation_failed', 'criteria or weights cannot be customised');
select throws_ok($$select pg_temp.cfg('{"scaleKind":"percent","inputMode":"direct","maxScore":100}')$$,
  'PT400', 'validation_failed', 'unknown scales are refused');
select is((select pg_temp.cfg(pg_temp.cfg('{"scaleKind":"fraction","inputMode":"components","showComponents":true,
    "components":[{"name":"A","totalQuestions":3}]}')::text)),
  pg_temp.cfg('{"scaleKind":"fraction","inputMode":"components","showComponents":true,
    "components":[{"name":"A","totalQuestions":3}]}'),
  'normalizing a normalized configuration changes nothing');

-------------------------------------------------------------------------------
-- Commands: Admin only; edits add versions.
-------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user(2);
select throws_ok($$select api.create_test_template('Mẫu', null,
    '{"scaleKind":"numeric","inputMode":"direct","maxScore":10}')$$,
  'PT403', 'forbidden', 'a Receptionist cannot create templates');
select throws_ok($$select api.list_test_templates()$$, 'PT403', 'forbidden',
  'a Receptionist cannot list the template library');
select pg_temp.as_user(3);
select throws_ok($$select api.create_test_template('Mẫu', null,
    '{"scaleKind":"numeric","inputMode":"direct","maxScore":10}')$$,
  'PT403', 'forbidden', 'a teacher cannot save a template');

select pg_temp.as_user(1);
insert into ids select 'mid', (t ->> 'id')::uuid, (t ->> 'rowVersion')::bigint
  from (select api.create_test_template('  Kiểm tra giữa kỳ ', '', '{"scaleKind":"numeric",
    "inputMode":"components","showComponents":false,"components":[{"name":"Nghe","maxScore":5},
    {"name":"Viết","maxScore":5}]}') as t) c;
select is((select (t ->> 'revision')::int from jsonb_array_elements(api.list_test_templates()) t
            where (t ->> 'id')::uuid = (select id from ids where key = 'mid')), 1,
  'Admin creates a template with its first version');
select throws_ok($$select api.create_test_template('', null,
    '{"scaleKind":"numeric","inputMode":"direct","maxScore":10}')$$,
  'PT400', 'validation_failed', 'a template needs a name');
select throws_ok($$select api.create_test_template('Mẫu', repeat('a', 5001),
    '{"scaleKind":"numeric","inputMode":"direct","maxScore":10}')$$,
  'PT400', 'validation_failed', 'descriptions are limited to 5000 characters');
select throws_ok($$select api.update_test_template((select id from ids where key = 'mid'), 'Giữa kỳ', null,
    '{"scaleKind":"numeric","inputMode":"direct","maxScore":10}', 7)$$,
  'PT409', 'version_conflict', 'stale versions are refused');
select is(api.update_test_template((select id from ids where key = 'mid'), 'Kiểm tra giữa kỳ', null,
    '{"scaleKind":"numeric","inputMode":"components","showComponents":false,"components":[
      {"name":"Nghe","maxScore":5},{"name":"Viết","maxScore":5}]}', 1) ->> 'rowVersion', '1',
  'saving unchanged content adds no version');
select is(api.update_test_template((select id from ids where key = 'mid'), 'Kiểm tra giữa kỳ', 'Hai phần',
    '{"scaleKind":"letter","inputMode":"direct","levels":[{"label":"Đạt"},{"label":"Chưa đạt"}]}', 1)
    ->> 'revision', '2', 'editing adds version 2');
select is((select jsonb_agg(v ->> 'revision') from jsonb_array_elements(
            api.list_test_template_versions((select id from ids where key = 'mid'))) v),
  '["2", "1"]'::jsonb, 'both versions are listed, newest first');
select is(api.list_test_template_versions((select id from ids where key = 'mid')) -> 1 #>> '{config,maxScore}',
  '10', 'version 1 keeps its original configuration');
select throws_ok($$select api.archive_test_template((select id from ids where key = 'mid'), '  ', 2)$$,
  'PT400', 'validation_failed', 'archiving needs a reason');
select is(api.archive_test_template((select id from ids where key = 'mid'), 'Không dùng nữa', 2)
    ->> 'archived', 'true', 'Admin archives a template');
select ok(not exists (select 1 from jsonb_array_elements(api.list_test_templates()) t
                       where (t ->> 'id')::uuid = (select id from ids where key = 'mid')),
  'archived templates are not offered by default');
select ok(exists (select 1 from jsonb_array_elements(api.list_test_templates(true)) t
                   where (t ->> 'id')::uuid = (select id from ids where key = 'mid')),
  'archived templates are listed on request');
select throws_ok($$select api.update_test_template((select id from ids where key = 'mid'), 'Sửa', null,
    '{"scaleKind":"numeric","inputMode":"direct","maxScore":10}', 3)$$,
  'PT409', 'invalid_state', 'archived templates cannot be edited');
select is((select t ->> 'id' || '/' || (t ->> 'revision') from (select api.restore_test_template(
            (select id from ids where key = 'mid'), 3) as t) r),
  (select id::text || '/2' from ids where key = 'mid'),
  'restoring reuses the identifier and the current version');
select pg_temp.as_user(3);
select throws_ok($$select api.list_test_template_versions((select id from ids where key = 'mid'))$$,
  'PT403', 'forbidden', 'a teacher cannot read template history');
reset role;

select is(pg_temp.audits('test_template.create') + pg_temp.audits('test_template.update')
        + pg_temp.audits('test_template.archive') + pg_temp.audits('test_template.restore'), 4::bigint,
  'every template change has one audit row');
select is((select count(*) from app.business_entity_versions
            where entity_kind = 'test_template' and entity_id = (select id from ids where key = 'mid')),
  4::bigint, 'every template change keeps a business version');
select is((select before_after #>> '{before,config,scaleKind}' || '>' || (before_after #>> '{after,config,scaleKind}')
             from app.audit_events where action = 'test_template.update' and created_at = now()),
  'numeric>letter', 'the update audit holds the configuration before and after');
select throws_ok($$update app.test_template_versions set name = 'Đổi tên'
    where template_id = (select id from ids where key = 'mid')$$,
  '42501', 'append_only', 'versions cannot be edited in place');
select throws_ok($$delete from app.test_template_versions
    where template_id = (select id from ids where key = 'mid')$$,
  '42501', 'append_only', 'versions cannot be deleted');
select throws_ok($$insert into app.test_template_versions
    (template_id, revision, name, config_schema_version, config, created_by)
    values ((select id from ids where key = 'mid'), 9, 'Ngoài luồng', 1,
            '{"scaleKind":"letter","inputMode":"direct","levels":[{"label":"Đạt"}]}',
            '00000000-0000-4000-8000-000000000001')$$,
  '23514', null, 'stored configurations must already be normalized');

-------------------------------------------------------------------------------
-- Atomicity and current permissions.
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
select throws_ok($$select api.update_test_template((select id from ids where key = 'mid'), 'Lỗi audit', null,
    '{"scaleKind":"numeric","inputMode":"direct","maxScore":20}', 4)$$,
  'P0001', 'injected audit failure', 'audit failure aborts the edit');
select throws_ok($$select api.create_test_template('Lỗi audit', null,
    '{"scaleKind":"numeric","inputMode":"direct","maxScore":20}')$$,
  'P0001', 'injected audit failure', 'audit failure aborts the creation');
reset role;
delete from app_private.test_fail_audit;
select is((select count(*)::int from app.test_template_versions
            where template_id = (select id from ids where key = 'mid')), 2,
  'no version is left behind by the failed edit');
select is((select count(*)::int from app.test_template_versions where name = 'Lỗi audit'), 0,
  'no template is left behind by the failed creation');

-- A former Admin's session no longer manages templates (current account type).
update app.account_profiles set account_type = 'receptionist'
 where id = '00000000-0000-4000-8000-000000000001';
set local role authenticated;
select pg_temp.as_user(1);
select throws_ok($$select api.archive_test_template((select id from ids where key = 'mid'), 'Thử', 4)$$,
  'PT403', 'forbidden', 'the current account type is checked, not the session');
reset role;

select * from finish();
rollback;
