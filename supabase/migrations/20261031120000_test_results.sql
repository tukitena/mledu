-- GĐ 5, third feature: results of a test per student (TEST-01/04/05) and the
-- re-entry rule of TEST-03 when a configuration changes after results exist.
--
-- One result per student and test, whatever the class record or participation
-- (TEST-05). A result is Absent or graded on the test's current snapshot:
-- numeric/fraction entered directly or by component, or one letter level.
-- Totals of components are computed here, never sent by the client. Missing
-- components stay missing (never 0) and leave the result incomplete (TEST-04).
--
-- Not in this feature: IELTS results, publication (ACAD-01), comments and Excel.
-- The published_* columns exist so the publication lock is enforced now and the
-- publication feature adds no table change. Design: docs/developer/assessment-schema.md.

-------------------------------------------------------------------------------
-- Tables.
-------------------------------------------------------------------------------

create table app.test_results (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references app.students (id),
  test_id uuid not null references app.tests (id),
  -- Snapshot the values were entered on; always the test's current one for a
  -- result in use (checked by the commands that write results or snapshots).
  config_id uuid not null,
  result_kind text not null,
  -- Numeric: direct score, or total/partial total of components (computed).
  numeric_score numeric,
  -- Fraction: direct correct answers, or sum of components (computed). The
  -- denominator is always the whole configuration's total.
  correct_answers integer,
  letter_level_id uuid,
  published_at timestamptz,
  published_by uuid references app.account_profiles (id),
  row_version bigint not null default 1,
  created_at timestamptz not null default now(),
  created_by uuid not null references app.account_profiles (id),
  updated_at timestamptz not null default now(),
  updated_by uuid not null references app.account_profiles (id),
  -- Cleared result (by the user, or because a new configuration needs the
  -- score entered again, TEST-03). Entering it again reuses the same id.
  deleted_at timestamptz,
  deleted_by uuid references app.account_profiles (id),
  constraint test_results_student_test_key unique (student_id, test_id),
  constraint test_results_id_config_key unique (id, config_id),
  constraint test_results_config_fkey foreign key (test_id, config_id)
    references app.test_config_versions (test_id, id),
  constraint test_results_level_fkey foreign key (config_id, letter_level_id)
    references app.test_letter_levels (config_id, id),
  constraint test_results_kind_check check (result_kind in ('graded', 'absent')),
  -- Absent is its own state: no score, answer count or level (TEST-01).
  constraint test_results_absent_check check (
    result_kind = 'graded'
    or (numeric_score is null and correct_answers is null and letter_level_id is null)
  ),
  constraint test_results_values_check check (
    num_nonnulls(numeric_score, correct_answers, letter_level_id) <= 1
    and (numeric_score is null or (numeric_score >= 0 and scale(numeric_score) <= 2))
    and (correct_answers is null or correct_answers >= 0)
  ),
  constraint test_results_published_check check (
    (published_at is null) = (published_by is null)
  ),
  constraint test_results_deleted_check check (
    (deleted_at is null) = (deleted_by is null)
    and (deleted_at is null or (published_at is null and numeric_score is null
         and correct_answers is null and letter_level_id is null))
  ),
  constraint test_results_row_version_check check (row_version >= 1)
);

create index test_results_test_idx on app.test_results (test_id);

comment on table app.test_results is
  'Result of one student in one test (TEST-01/04/05): Absent or graded on the current snapshot.';

create table app.component_results (
  result_id uuid not null,
  config_id uuid not null,
  component_id uuid not null,
  numeric_value numeric,
  correct_answers integer,
  primary key (result_id, component_id),
  constraint component_results_result_fkey foreign key (result_id, config_id)
    references app.test_results (id, config_id),
  constraint component_results_component_fkey foreign key (config_id, component_id)
    references app.test_components (config_id, id),
  -- A row is an entered value; 0 is a value, a missing row is not entered.
  constraint component_results_value_check check (
    (numeric_value >= 0 and scale(numeric_value) <= 2 and correct_answers is null)
    or (correct_answers >= 0 and numeric_value is null)
  )
);

comment on table app.component_results is
  'Entered component values of a result (TEST-04). Missing row = not entered, never 0.';

create trigger test_results_no_delete
  before delete on app.test_results
  for each row execute function app_private.reject_change();
create trigger test_results_no_truncate
  before truncate on app.test_results
  for each statement execute function app_private.reject_change();
create trigger component_results_no_truncate
  before truncate on app.component_results
  for each statement execute function app_private.reject_change();

alter table app.test_results enable row level security;
alter table app.component_results enable row level security;
revoke all on table app.test_results, app.component_results from public, anon, authenticated;

-------------------------------------------------------------------------------
-- Derived values, snapshots and DTOs (packages/contracts/src/assessments.ts).
-------------------------------------------------------------------------------

-- Every component has a value (or the test is entered directly). Absent counts
-- as a valid, complete result (TEST-01).
create function app_private.result_complete(p_result app.test_results)
returns boolean
language sql
stable
set search_path = ''
as $$
  select p_result.deleted_at is null and (
    p_result.result_kind = 'absent'
    or (select case
          when c.input_mode = 'components' then
            (select count(*) from app.component_results x where x.result_id = p_result.id)
            = (select count(*) from app.test_components k where k.config_id = c.id)
          else num_nonnulls(p_result.numeric_score, p_result.correct_answers, p_result.letter_level_id) = 1
        end
          from app.test_config_versions c where c.id = p_result.config_id))
$$;

-- Component values keyed by the snapshot's stable codes (c1…).
create function app_private.result_components(p_result_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(k.code, coalesce(to_jsonb(x.numeric_value), to_jsonb(x.correct_answers))
                                   order by k.sort_order), '{}')
    from app.component_results x
    join app.test_components k on k.id = x.component_id
   where x.result_id = p_result_id
$$;

-- History content: every input, cache and the publication state replaced.
create function app_private.result_snapshot(p_result app.test_results)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'test_id', p_result.test_id,
    'student_id', p_result.student_id,
    'config_id', p_result.config_id,
    'result_kind', p_result.result_kind,
    'numeric_score', p_result.numeric_score,
    'correct_answers', p_result.correct_answers,
    'letter_level', (select l.code from app.test_letter_levels l where l.id = p_result.letter_level_id),
    'components', app_private.result_components(p_result.id),
    'published_at', p_result.published_at,
    'published_by', p_result.published_by,
    'deleted_at', p_result.deleted_at,
    'deleted_by', p_result.deleted_by
  )
$$;

create function app_private.result_dto(p_result app.test_results)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_result.id,
    'absent', p_result.result_kind = 'absent',
    'score', p_result.numeric_score,
    'correctAnswers', p_result.correct_answers,
    'level', (select l.code from app.test_letter_levels l where l.id = p_result.letter_level_id),
    'components', app_private.result_components(p_result.id),
    'complete', app_private.result_complete(p_result),
    'published', p_result.published_at is not null,
    'rowVersion', p_result.row_version,
    'updatedAt', p_result.updated_at,
    'updatedByName', a.full_name
  )
    from app.account_profiles a
   where a.id = p_result.updated_by
$$;

-- Students who may have a result: a participation in the class (current or
-- past, deleted records included) meets the test day, 00:00 to 24:00 in
-- Asia/Ho_Chi_Minh (TEST-05). Students holding a result stay listed.
create function app_private.test_roster_ids(p_test app.tests)
returns setof uuid
language sql
stable
set search_path = ''
as $$
  select r.student_id
    from app.class_students r
    join app.participations p on p.class_student_id = r.id
   where r.class_id = p_test.class_id
     and p.effective_period && tstzrange(app_private.day_start(p_test.test_on),
                                         app_private.day_start(p_test.test_on + 1), '[)')
  union
  select x.student_id from app.test_results x where x.test_id = p_test.id and x.deleted_at is null
$$;

create function app_private.test_roster(p_test app.tests)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'studentId', s.id,
           'code', s.code,
           'fullName', s.full_name,
           'result', case when x.id is not null and x.deleted_at is null
                          then app_private.result_dto(x) end)
           order by s.name_key, s.id), '[]')
    from app.students s
    left join app.test_results x on x.student_id = s.id and x.test_id = p_test.id
   where s.id in (select app_private.test_roster_ids(p_test))
$$;

-- Tests in the class list also say how many results are in use.
create or replace function app_private.test_dto(p_test app.tests)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_test.id,
    'classId', p_test.class_id,
    'name', p_test.name,
    'testOn', p_test.test_on,
    'description', p_test.description,
    'showComponents', p_test.show_components,
    'configId', c.id,
    'configRevision', c.revision,
    'config', app_private.test_config_json(c.id, p_test.show_components),
    'source', app_private.test_source_dto(c.source_template_version_id),
    'resultCount', (select count(*) from app.test_results x
                     where x.test_id = p_test.id and x.deleted_at is null),
    'deleted', p_test.deleted_at is not null,
    'createdAt', p_test.created_at,
    'createdByName', a.full_name,
    'updatedAt', p_test.updated_at,
    'rowVersion', p_test.row_version
  )
    from app.test_config_versions c, app.account_profiles a
   where c.id = p_test.current_config_id and a.id = p_test.created_by
$$;

-------------------------------------------------------------------------------
-- Test date (TEST-05): within the class, and not away from a student who has
-- a result. The whole change is refused with the students named.
-------------------------------------------------------------------------------

create function app_private.check_result_participation(p_test app.tests)
returns void
language plpgsql
stable
set search_path = ''
as $$
declare
  v_outside jsonb;
begin
  select jsonb_agg(jsonb_build_object('path', 'studentName', 'message', s.full_name)
                   order by s.name_key, s.id)
    into v_outside
    from app.test_results x
    join app.students s on s.id = x.student_id
   where x.test_id = p_test.id and x.deleted_at is null
     and not exists (
       select 1 from app.class_students r
         join app.participations p on p.class_student_id = r.id
        where r.class_id = p_test.class_id and r.student_id = x.student_id
          and p.effective_period && tstzrange(app_private.day_start(p_test.test_on),
                                              app_private.day_start(p_test.test_on + 1), '[)'));
  if v_outside is not null then
    perform app_private.raise_api_conflict('test_date_excludes_results', v_outside);
  end if;
end
$$;

create or replace function api.update_test(
  p_id uuid,
  p_name text,
  p_test_on date,
  p_description text,
  p_expected_version bigint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_class_id uuid := (select t.class_id from app.tests t where t.id = p_id);
  v_actor app.account_profiles;
  v_name text;
  v_description text;
  v_before app.tests;
  v_after app.tests;
begin
  if v_class_id is null then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  v_actor := app_private.require_test_editor(v_class_id);
  v_name := app_private.clean_text(p_name, 200);
  v_description := app_private.clean_optional_text(p_description, 5000);
  v_before := app_private.lock_test(p_id, p_expected_version);
  perform app_private.check_test_date(v_class_id, p_test_on);
  if v_before.name = v_name and v_before.test_on = p_test_on
    and v_before.description is not distinct from v_description
  then
    return app_private.test_dto(v_before);
  end if;

  update app.tests t
     set name = v_name,
         name_key = app_private.name_key(v_name),
         test_on = p_test_on,
         description = v_description,
         row_version = t.row_version + 1,
         updated_at = now()
   where t.id = v_before.id
  returning * into v_after;
  -- The test row is locked, so no result can be added for the old date meanwhile.
  if v_after.test_on <> v_before.test_on then
    perform app_private.check_result_participation(v_after);
  end if;

  perform app_private.record_change('test', v_after.id, v_after.row_version,
    app_private.test_snapshot(v_before), app_private.test_snapshot(v_after), v_actor.id,
    'test.update', jsonb_build_object('class_id', v_class_id, 'test_id', v_after.id));
  return app_private.test_dto(v_after);
end
$$;

-------------------------------------------------------------------------------
-- TEST-03: a new configuration once results exist. Refused while any result is
-- published. Scores are kept in history, then cleared: they must be entered
-- again on the new snapshot. Absent stays Absent. Nothing is published.
-------------------------------------------------------------------------------

create or replace function api.change_test_config(
  p_id uuid,
  p_config jsonb,
  p_source_template_version_id uuid,
  p_expected_version bigint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_class_id uuid := (select t.class_id from app.tests t where t.id = p_id);
  v_actor app.account_profiles;
  v_config jsonb;
  v_show boolean;
  v_before app.tests;
  v_current app.test_config_versions;
  v_same_config boolean;
  v_config_id uuid := gen_random_uuid();
  v_after app.tests;
  v_result app.test_results;
  v_reset app.test_results;
  v_results_before jsonb := '[]';
  v_results_after jsonb := '[]';
begin
  if v_class_id is null then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  v_actor := app_private.require_test_editor(v_class_id);
  v_config := app_private.test_template_config(p_config);
  v_show := app_private.config_has_details(v_config)
    and coalesce((v_config ->> 'showComponents')::boolean, false);
  v_before := app_private.lock_test(p_id, p_expected_version);
  select * into v_current from app.test_config_versions c where c.id = v_before.current_config_id;

  v_same_config := v_current.source_template_version_id is not distinct from p_source_template_version_id
    and app_private.test_config_json(v_current.id, false) = app_private.test_template_config(
          case when v_config ? 'showComponents'
            then jsonb_set(v_config, '{showComponents}', 'false') else v_config end);
  if v_same_config and v_show = v_before.show_components then
    return app_private.test_dto(v_before);
  end if;
  if v_show <> v_before.show_components then
    perform app_private.require_test_editor(v_class_id, p_display => true);
  end if;
  if p_source_template_version_id is not null
    and p_source_template_version_id is distinct from v_current.source_template_version_id
  then
    perform app_private.lock_template_source(p_source_template_version_id);
  end if;

  if not v_same_config then
    -- Results are written only under a shared lock of the test, so none can
    -- appear or change once this command holds the test row.
    if exists (select 1 from app.test_results x
                where x.test_id = v_before.id and x.published_at is not null) then
      perform app_private.raise_api_error(409, 'result_published');
    end if;
    perform app_private.insert_test_config(v_config_id, v_before.id, v_current.revision + 1,
      v_config, p_source_template_version_id, v_actor.id);
  end if;

  update app.tests t
     set current_config_id = case when v_same_config then t.current_config_id else v_config_id end,
         show_components = v_show,
         row_version = t.row_version + 1,
         updated_at = now()
   where t.id = v_before.id
  returning * into v_after;

  if not v_same_config then
    for v_result in
      select * from app.test_results x
       where x.test_id = v_before.id and x.deleted_at is null
       order by x.id
         for update
    loop
      v_results_before := v_results_before || jsonb_build_array(
        app_private.result_snapshot(v_result) || jsonb_build_object('result_id', v_result.id));
      delete from app.component_results x where x.result_id = v_result.id;
      update app.test_results x
         set config_id = v_config_id,
             numeric_score = null,
             correct_answers = null,
             letter_level_id = null,
             deleted_at = case when x.result_kind = 'graded' then now() end,
             deleted_by = case when x.result_kind = 'graded' then v_actor.id end,
             row_version = x.row_version + 1,
             updated_at = now(),
             updated_by = v_actor.id
       where x.id = v_result.id
      returning * into v_reset;
      perform app_private.record_version('test_result', v_reset.id, v_reset.row_version,
        app_private.result_snapshot(v_reset), v_actor.id);
      v_results_after := v_results_after || jsonb_build_array(
        app_private.result_snapshot(v_reset) || jsonb_build_object('result_id', v_reset.id));
    end loop;
    -- Cleared rows also move to the new snapshot so every row follows the test.
    update app.test_results x
       set config_id = v_config_id
     where x.test_id = v_before.id and x.deleted_at is not null and x.config_id <> v_config_id;
  end if;

  perform app_private.record_version('test', v_after.id, v_after.row_version,
    app_private.test_snapshot(v_after), v_actor.id);
  perform app_private.write_audit(v_actor.id, 'app',
    case when v_same_config then 'test.set_show_components' else 'test.change_config' end,
    jsonb_strip_nulls(jsonb_build_object('class_id', v_class_id, 'test_id', v_after.id,
      'test_config_id', v_after.current_config_id,
      'test_template_version_id', p_source_template_version_id)),
    jsonb_build_object(
      'before', app_private.test_snapshot(v_before)
                || case when jsonb_array_length(v_results_before) > 0
                     then jsonb_build_object('results', v_results_before) else '{}' end,
      'after', app_private.test_snapshot(v_after)
               || case when jsonb_array_length(v_results_after) > 0
                    then jsonb_build_object('results', v_results_after) else '{}' end));
  return app_private.test_dto(v_after);
end
$$;

-------------------------------------------------------------------------------
-- Reading and entering results.
-------------------------------------------------------------------------------

create function app_private.test_results_dto(p_test app.tests, p_actor app.account_profiles)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'test', app_private.test_dto(p_test),
    'students', app_private.test_roster(p_test),
    'canEdit', p_test.deleted_at is null
      and exists (select 1 from app.classes c where c.id = p_test.class_id and c.deleted_at is null)
      and (p_actor.account_type = 'admin' or app_private.class_role(p_actor.id, p_test.class_id) is not null))
$$;

create function api.get_test_results(p_test_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_test app.tests;
  v_actor app.account_profiles;
begin
  select * into v_test from app.tests t where t.id = p_test_id;
  if not found then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  v_actor := app_private.require_test_reader(v_test.class_id);
  return app_private.test_results_dto(v_test, v_actor);
end
$$;

-- Validates one entry against the snapshot and returns it normalized:
-- {kind, score, answers, level_id, components: [{id, value}]}. Numbers must be
-- JSON numbers; more than two decimals, negative or above the maximum values
-- are refused, never rounded or clipped (TEST-01/04).
create function app_private.result_entry(p_config app.test_config_versions, p_entry jsonb)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_value jsonb;
  v_number numeric;
  v_component app.test_components;
  v_components jsonb := '[]';
  v_level_id uuid;
begin
  if jsonb_typeof(p_entry) is distinct from 'object'
    or jsonb_typeof(p_entry -> 'absent') is distinct from 'boolean'
  then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  if (p_entry ->> 'absent')::boolean then
    if exists (select 1 from jsonb_object_keys(p_entry) k where k <> 'absent') then
      perform app_private.raise_api_error(400, 'validation_failed');
    end if;
    return jsonb_build_object('kind', 'absent', 'components', '[]'::jsonb);
  end if;

  if p_config.scale_kind = 'letter' then
    if exists (select 1 from jsonb_object_keys(p_entry) k where k not in ('absent', 'level')) then
      perform app_private.raise_api_error(400, 'validation_failed');
    end if;
    select l.id into v_level_id from app.test_letter_levels l
     where l.config_id = p_config.id and l.code = p_entry ->> 'level';
    if v_level_id is null then
      perform app_private.raise_api_error(400, 'validation_failed');
    end if;
    return jsonb_build_object('kind', 'graded', 'level_id', v_level_id, 'components', '[]'::jsonb);
  end if;

  if p_config.input_mode = 'direct' then
    v_value := p_entry -> case p_config.scale_kind when 'numeric' then 'score' else 'correctAnswers' end;
    if exists (select 1 from jsonb_object_keys(p_entry) k
                where k not in ('absent', case p_config.scale_kind when 'numeric' then 'score'
                                                                 else 'correctAnswers' end))
      or jsonb_typeof(v_value) is distinct from 'number'
    then
      perform app_private.raise_api_error(400, 'validation_failed');
    end if;
    v_number := v_value::text::numeric;
    if v_number < 0
      or (p_config.scale_kind = 'numeric' and (scale(v_number) > 2 or v_number > p_config.max_score))
      or (p_config.scale_kind = 'fraction' and (v_number <> trunc(v_number) or v_number > p_config.total_questions))
    then
      perform app_private.raise_api_error(400, 'validation_failed');
    end if;
    return jsonb_build_object('kind', 'graded', 'components', '[]'::jsonb,
      case p_config.scale_kind when 'numeric' then 'score' else 'answers' end, v_number);
  end if;

  -- By component: only codes of this snapshot; a null or absent code is not entered.
  if exists (select 1 from jsonb_object_keys(p_entry) k where k not in ('absent', 'components'))
    or jsonb_typeof(p_entry -> 'components') is distinct from 'object'
    or exists (select 1 from jsonb_object_keys(p_entry -> 'components') k
                where not exists (select 1 from app.test_components c
                                   where c.config_id = p_config.id and c.code = k))
  then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  for v_component in
    select * from app.test_components c where c.config_id = p_config.id order by c.sort_order
  loop
    v_value := p_entry -> 'components' -> v_component.code;
    continue when v_value is null or v_value = 'null'::jsonb;
    if jsonb_typeof(v_value) <> 'number' then
      perform app_private.raise_api_error(400, 'validation_failed');
    end if;
    v_number := v_value::text::numeric;
    if v_number < 0
      or (v_component.max_score is not null and (scale(v_number) > 2 or v_number > v_component.max_score))
      or (v_component.total_questions is not null
          and (v_number <> trunc(v_number) or v_number > v_component.total_questions))
    then
      perform app_private.raise_api_error(400, 'validation_failed');
    end if;
    v_components := v_components || jsonb_build_array(jsonb_build_object('id', v_component.id, 'value', v_number));
  end loop;
  -- Nothing entered is not a result: the client sends null to clear instead.
  if jsonb_array_length(v_components) = 0 then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  return jsonb_build_object('kind', 'graded', 'components', v_components,
    case p_config.scale_kind when 'numeric' then 'score' else 'answers' end,
    (select sum((x ->> 'value')::numeric) from jsonb_array_elements(v_components) x));
end
$$;

-- A stored result in the normalized shape of result_entry, to compare them.
create function app_private.result_entry_of(p_result app.test_results)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'kind', p_result.result_kind,
    'score', p_result.numeric_score,
    'answers', p_result.correct_answers,
    'level_id', p_result.letter_level_id))
    || jsonb_build_object('components', coalesce((
         select jsonb_agg(jsonb_build_object('id', x.component_id,
                                             'value', coalesce(x.numeric_value, x.correct_answers))
                          order by k.sort_order)
           from app.component_results x
           join app.test_components k on k.id = x.component_id
          where x.result_id = p_result.id), '[]'))
$$;

-- Saves the changed rows of the entry grid in one transaction and one audit.
-- Each item: {studentId, expectedVersion (null when the student has no result
-- in use), entry: null to clear | {absent: true} | values of the configuration}.
-- p_config_id must be the snapshot the user entered on. Published results are
-- locked (ACAD-01); unchanged items write nothing.
create function api.save_test_results(p_test_id uuid, p_config_id uuid, p_items jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_class_id uuid := (select t.class_id from app.tests t where t.id = p_test_id);
  v_actor app.account_profiles;
  v_test app.tests;
  v_config app.test_config_versions;
  v_item jsonb;
  v_student_id uuid;
  v_entry jsonb;
  v_before app.test_results;
  v_after app.test_results;
  v_snapshot_before jsonb;
  v_snapshot_after jsonb;
  v_before_list jsonb := '[]';
  v_after_list jsonb := '[]';
begin
  if v_class_id is null then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  v_actor := app_private.require_test_editor(v_class_id);
  -- Shared: results of one test may be saved together, while a configuration
  -- change, a date change or (later) archiving the test waits.
  select * into v_test from app.tests t where t.id = p_test_id for share;
  if v_test.deleted_at is not null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
  if p_config_id is distinct from v_test.current_config_id then
    perform app_private.raise_api_error(409, 'version_conflict');
  end if;
  select * into v_config from app.test_config_versions c where c.id = v_test.current_config_id;
  if v_config.scale_kind = 'ielts' then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
  if jsonb_typeof(p_items) is distinct from 'array'
    or jsonb_array_length(p_items) not between 1 and 1000
    or exists (select 1 from jsonb_array_elements(p_items) x where jsonb_typeof(x) <> 'object'
                  or not (x ? 'studentId') or not (x ? 'entry') or not (x ? 'expectedVersion'))
    or (select count(distinct x ->> 'studentId') from jsonb_array_elements(p_items) x)
       <> jsonb_array_length(p_items)
  then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;

  -- One order for every writer of these rows.
  for v_item in
    select x from jsonb_array_elements(p_items) x order by x ->> 'studentId'
  loop
    begin
      v_student_id := (v_item ->> 'studentId')::uuid;
    exception when invalid_text_representation then
      perform app_private.raise_api_error(400, 'validation_failed');
    end;
    if jsonb_typeof(v_item -> 'expectedVersion') not in ('number', 'null') then
      perform app_private.raise_api_error(400, 'validation_failed');
    end if;
    -- Only students whose participation meets the test day (TEST-05).
    if not exists (
      select 1 from app.class_students r
        join app.participations p on p.class_student_id = r.id
       where r.class_id = v_test.class_id and r.student_id = v_student_id
         and p.effective_period && tstzrange(app_private.day_start(v_test.test_on),
                                             app_private.day_start(v_test.test_on + 1), '[)'))
    then
      perform app_private.raise_api_error(400, 'validation_failed');
    end if;
    v_entry := case when v_item -> 'entry' = 'null'::jsonb then null
                    else app_private.result_entry(v_config, v_item -> 'entry') end;

    select * into v_before from app.test_results x
     where x.test_id = v_test.id and x.student_id = v_student_id
       for update;
    -- null expects no result in use (none yet, or cleared); a number expects
    -- exactly that version of the row.
    if (v_item -> 'expectedVersion' = 'null'::jsonb and v_before.id is not null
          and v_before.deleted_at is null)
      or (v_item -> 'expectedVersion' <> 'null'::jsonb
          and (v_before.id is null or v_before.row_version <> (v_item ->> 'expectedVersion')::bigint))
    then
      perform app_private.raise_api_error(409, 'version_conflict');
    end if;
    if v_before.published_at is not null then
      perform app_private.raise_api_error(409, 'result_published');
    end if;
    v_snapshot_before := case when v_before.id is not null and v_before.deleted_at is null
                              then app_private.result_snapshot(v_before) end;

    if v_entry is null then
      continue when v_snapshot_before is null;
      delete from app.component_results x where x.result_id = v_before.id;
      update app.test_results x
         set numeric_score = null, correct_answers = null, letter_level_id = null,
             result_kind = 'graded', deleted_at = now(), deleted_by = v_actor.id,
             row_version = x.row_version + 1, updated_at = now(), updated_by = v_actor.id
       where x.id = v_before.id
      returning * into v_after;
    else
      -- Same content as the result in use: nothing is written.
      continue when v_snapshot_before is not null
        and app_private.result_entry_of(v_before) = v_entry;
      if v_before.id is null then
        insert into app.test_results (student_id, test_id, config_id, result_kind, created_by, updated_by)
        values (v_student_id, v_test.id, v_config.id, v_entry ->> 'kind', v_actor.id, v_actor.id)
        returning * into v_before;
        -- The update below gives the new row its first version.
        v_before.row_version := 0;
      end if;
      delete from app.component_results x where x.result_id = v_before.id;
      insert into app.component_results (result_id, config_id, component_id, numeric_value, correct_answers)
      select v_before.id, v_config.id, (c ->> 'id')::uuid,
             case when v_config.scale_kind = 'numeric' then (c ->> 'value')::numeric end,
             case when v_config.scale_kind = 'fraction' then (c ->> 'value')::integer end
        from jsonb_array_elements(v_entry -> 'components') c;
      update app.test_results x
         set result_kind = v_entry ->> 'kind',
             numeric_score = (v_entry ->> 'score')::numeric,
             correct_answers = (v_entry ->> 'answers')::integer,
             letter_level_id = (v_entry ->> 'level_id')::uuid,
             deleted_at = null, deleted_by = null,
             row_version = v_before.row_version + 1,
             updated_at = now(), updated_by = v_actor.id
       where x.id = v_before.id
      returning * into v_after;
    end if;

    v_snapshot_after := app_private.result_snapshot(v_after);
    perform app_private.record_version('test_result', v_after.id, v_after.row_version,
      v_snapshot_after, v_actor.id);
    v_before_list := v_before_list || jsonb_build_array(jsonb_build_object(
      'result_id', v_after.id, 'student_id', v_student_id, 'result', v_snapshot_before));
    v_after_list := v_after_list || jsonb_build_array(jsonb_build_object(
      'result_id', v_after.id, 'student_id', v_student_id,
      'result', case when v_after.deleted_at is null then v_snapshot_after end));
  end loop;

  if jsonb_array_length(v_after_list) > 0 then
    perform app_private.write_audit(v_actor.id, 'app', 'test_result.save',
      jsonb_build_object('class_id', v_class_id, 'test_id', v_test.id, 'test_config_id', v_config.id),
      jsonb_build_object('before', jsonb_strip_nulls(v_before_list), 'after', v_after_list));
  end if;
  return app_private.test_results_dto(v_test, v_actor);
end
$$;

revoke all on function
  app_private.result_complete(app.test_results),
  app_private.result_components(uuid),
  app_private.result_snapshot(app.test_results),
  app_private.result_dto(app.test_results),
  app_private.test_roster_ids(app.tests),
  app_private.test_roster(app.tests),
  app_private.check_result_participation(app.tests),
  app_private.test_results_dto(app.tests, app.account_profiles),
  app_private.result_entry(app.test_config_versions, jsonb),
  app_private.result_entry_of(app.test_results)
  from public, anon, authenticated;
revoke all on function
  api.get_test_results(uuid),
  api.save_test_results(uuid, uuid, jsonb)
  from public, anon;
grant execute on function
  api.get_test_results(uuid),
  api.save_test_results(uuid, uuid, jsonb)
  to authenticated;
