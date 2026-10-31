-- GĐ 5, fifth feature: IELTS results (TEST-01, IELTS part).
--
-- A test chooses one to four skills, each entered directly (a band) or in
-- detail, the same for every student. L/R in detail keep the correct answers
-- AND the band typed by the user: nothing is converted either way. Writing in
-- detail has Task 1 and Task 2 with four criteria each; each Task is rounded
-- first, then Writing = roundBand((Task1 + 2 x Task2) / 3). Speaking in detail
-- is roundBand of its four criteria. Overall only exists when the test has all
-- four skills and the student has the four bands. Every computed value (Task,
-- W/S bands in detail, Overall) is computed here and never accepted from the
-- client or Excel. Missing input stays missing, never 0.
--
-- roundBand(x) = floor(2x + 0.5) / 2 for exact non-negative x (formula
-- mledu-ielts-v1 of the test snapshot). Design: docs/developer/assessment-schema.md.

-------------------------------------------------------------------------------
-- Tables.
-------------------------------------------------------------------------------

create function app_private.is_band(p_value numeric)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_value >= 0 and p_value <= 9 and p_value * 2 = trunc(p_value * 2)
$$;

alter table app.test_results
  add column overall_band numeric,
  add constraint test_results_overall_check check (
    overall_band is null
    or (app_private.is_band(overall_band) and result_kind = 'graded' and deleted_at is null)
  );

create table app.ielts_skill_results (
  result_id uuid not null,
  config_id uuid not null,
  skill text not null,
  -- L/R in detail: typed correct answers (never derived from the band).
  correct_answers integer,
  -- Band typed by the user: direct mode, or L/R in detail.
  input_band numeric,
  -- W/S in detail: computed from the criteria; NULL while a criterion is missing.
  calculated_band numeric,
  task1_band numeric,
  task2_band numeric,
  primary key (result_id, skill),
  constraint ielts_skill_results_key unique (result_id, config_id, skill),
  constraint ielts_skill_results_result_fkey foreign key (result_id, config_id)
    references app.test_results (id, config_id),
  constraint ielts_skill_results_skill_fkey foreign key (config_id, skill)
    references app.test_ielts_skills (config_id, skill),
  constraint ielts_skill_results_values_check check (
    (correct_answers is null or (correct_answers >= 0 and skill in ('L', 'R')))
    and (input_band is null or app_private.is_band(input_band))
    and (calculated_band is null or (app_private.is_band(calculated_band) and skill in ('W', 'S')))
    and (input_band is null or calculated_band is null)
    and ((task1_band is null and task2_band is null) or skill = 'W')
    and (task1_band is null or app_private.is_band(task1_band))
    and (task2_band is null or app_private.is_band(task2_band))
  )
);

create table app.ielts_criterion_results (
  result_id uuid not null,
  config_id uuid not null,
  skill text not null,
  criterion_code text not null,
  band numeric not null,
  primary key (result_id, skill, criterion_code),
  constraint ielts_criterion_results_skill_fkey foreign key (result_id, config_id, skill)
    references app.ielts_skill_results (result_id, config_id, skill),
  constraint ielts_criterion_results_code_check check (
    (skill = 'W' and criterion_code in ('t1_ta', 't1_cc', 't1_lr', 't1_gra',
                                        't2_tr', 't2_cc', 't2_lr', 't2_gra'))
    or (skill = 'S' and criterion_code in ('fc', 'lr', 'gra', 'pronunciation'))
  ),
  constraint ielts_criterion_results_band_check check (app_private.is_band(band))
);

comment on table app.ielts_skill_results is
  'Inputs and computed cache of one IELTS skill of a result (TEST-01). Missing row = not entered.';
comment on table app.ielts_criterion_results is
  'Writing/Speaking criteria entered in detail (TEST-01). Missing row = not entered, never 0.';

create trigger ielts_skill_results_no_truncate
  before truncate on app.ielts_skill_results
  for each statement execute function app_private.reject_change();
create trigger ielts_criterion_results_no_truncate
  before truncate on app.ielts_criterion_results
  for each statement execute function app_private.reject_change();

alter table app.ielts_skill_results enable row level security;
alter table app.ielts_criterion_results enable row level security;
revoke all on table app.ielts_skill_results, app.ielts_criterion_results
  from public, anon, authenticated;

-------------------------------------------------------------------------------
-- Formula mledu-ielts-v1.
-------------------------------------------------------------------------------

create function app_private.round_band(p_value numeric)
returns numeric
language sql
immutable
set search_path = ''
as $$
  select trim_scale(floor(2 * p_value + 0.5) / 2)
$$;

-- Fixed criterion codes of the formula version kept by the snapshot.
create function app_private.ielts_criteria(p_formula text, p_skill text)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select case when p_formula = 'mledu-ielts-v1' then
    case p_skill
      when 'W' then array['t1_ta', 't1_cc', 't1_lr', 't1_gra', 't2_tr', 't2_cc', 't2_lr', 't2_gra']
      when 'S' then array['fc', 'lr', 'gra', 'pronunciation']
    end
  end
$$;

create function app_private.clear_ielts_inputs(p_result_id uuid)
returns void
language sql
volatile
set search_path = ''
as $$
  delete from app.ielts_criterion_results x where x.result_id = p_result_id;
  delete from app.ielts_skill_results x where x.result_id = p_result_id;
$$;

-- A cleared/Absent result keeps no IELTS input or Overall. The commands write
-- the history before the change.
create function app_private.test_results_clear_ielts()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.deleted_at is not null or new.result_kind = 'absent' then
    perform app_private.clear_ielts_inputs(old.id);
    new.overall_band := null;
  end if;
  return new;
end
$$;

create trigger test_results_clear_ielts
  before update on app.test_results
  for each row execute function app_private.test_results_clear_ielts();

-- Writes the normalized skill inputs of ielts_result_entry with the computed
-- Task / W / S bands. Each Task is rounded before the 1:2 weighting.
create function app_private.write_ielts_inputs(
  p_result_id uuid,
  p_config app.test_config_versions,
  p_items jsonb
)
returns void
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_item jsonb;
  v_skill text;
  v_criteria jsonb;
  v_task1 numeric;
  v_task2 numeric;
  v_calculated numeric;
begin
  for v_item in select x from jsonb_array_elements(p_items) x
  loop
    v_skill := v_item ->> 'skill';
    v_criteria := coalesce(v_item -> 'criteria', '{}');
    v_task1 := null;
    v_task2 := null;
    v_calculated := null;
    if v_skill = 'W' and v_criteria <> '{}' then
      if (select count(*) from jsonb_object_keys(v_criteria) k where left(k, 3) = 't1_') = 4 then
        v_task1 := app_private.round_band((select sum(e.value::text::numeric) / 4
                                             from jsonb_each(v_criteria) e where left(e.key, 3) = 't1_'));
      end if;
      if (select count(*) from jsonb_object_keys(v_criteria) k where left(k, 3) = 't2_') = 4 then
        v_task2 := app_private.round_band((select sum(e.value::text::numeric) / 4
                                             from jsonb_each(v_criteria) e where left(e.key, 3) = 't2_'));
      end if;
      if v_task1 is not null and v_task2 is not null then
        v_calculated := app_private.round_band((v_task1 + 2 * v_task2) / 3);
      end if;
    elsif v_skill = 'S' and (select count(*) from jsonb_object_keys(v_criteria)) = 4 then
      v_calculated := app_private.round_band((select sum(e.value::text::numeric) / 4
                                                from jsonb_each(v_criteria) e));
    end if;
    insert into app.ielts_skill_results (result_id, config_id, skill, correct_answers, input_band,
                                         calculated_band, task1_band, task2_band)
    values (p_result_id, p_config.id, v_skill, (v_item ->> 'answers')::integer,
            (v_item ->> 'band')::numeric, v_calculated, v_task1, v_task2);
    insert into app.ielts_criterion_results (result_id, config_id, skill, criterion_code, band)
    select p_result_id, p_config.id, v_skill, e.key, e.value::text::numeric
      from jsonb_each(v_criteria) e;
  end loop;
end
$$;

-- Band used for a skill: typed (direct, L/R in detail) or computed (W/S in detail).
create function app_private.ielts_effective_band(p_skill app.test_ielts_skills, p_result app.ielts_skill_results)
returns numeric
language sql
immutable
set search_path = ''
as $$
  select case when p_skill.input_mode = 'detailed' and p_skill.skill in ('W', 'S')
              then p_result.calculated_band else p_result.input_band end
$$;

-- Overall only with all four skills in the test and the four bands of the student.
create function app_private.ielts_overall(p_result_id uuid, p_config_id uuid)
returns numeric
language sql
stable
set search_path = ''
as $$
  select case when count(*) = 4 and count(x.band) = 4 then app_private.round_band(sum(x.band) / 4) end
    from (select app_private.ielts_effective_band(s, r) band
            from app.test_ielts_skills s
            left join app.ielts_skill_results r on r.result_id = p_result_id and r.skill = s.skill
           where s.config_id = p_config_id) x
$$;

-------------------------------------------------------------------------------
-- Entry validation: {absent: false, skills: {L: {...}, ...}} on the snapshot.
--   direct:          {band}
--   L/R in detail:   {correctAnswers, band}  (two independent inputs)
--   W/S in detail:   {criteria: {code: band}} (no band: it is computed)
-- null or a missing key is not entered. Bands are 0-9 in steps of 0.5; values
-- out of range or off-step are refused, never corrected.
-- Normalized: {kind, components: [], ielts: [{skill, answers?, band?, criteria}]}.
-------------------------------------------------------------------------------

create function app_private.ielts_result_entry(p_config app.test_config_versions, p_entry jsonb)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_skill app.test_ielts_skills;
  v_in jsonb;
  v_value jsonb;
  v_number numeric;
  v_answers integer;
  v_band numeric;
  v_criteria jsonb;
  v_items jsonb := '[]';
  v_code text;
begin
  if exists (select 1 from jsonb_object_keys(p_entry) k where k not in ('absent', 'skills'))
    or jsonb_typeof(p_entry -> 'skills') is distinct from 'object'
    or exists (select 1 from jsonb_object_keys(p_entry -> 'skills') k
                where not exists (select 1 from app.test_ielts_skills s
                                   where s.config_id = p_config.id and s.skill = k))
  then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;

  for v_skill in
    select * from app.test_ielts_skills s
     where s.config_id = p_config.id
     order by array_position(array['L', 'R', 'W', 'S'], s.skill)
  loop
    v_in := p_entry -> 'skills' -> v_skill.skill;
    continue when v_in is null or v_in = 'null'::jsonb;
    if jsonb_typeof(v_in) <> 'object' then
      perform app_private.raise_api_error(400, 'validation_failed');
    end if;
    v_answers := null;
    v_band := null;
    v_criteria := '{}';

    if v_skill.input_mode = 'direct' or v_skill.skill in ('L', 'R') then
      if exists (select 1 from jsonb_object_keys(v_in) k
                  where k <> 'band' and not (k = 'correctAnswers' and v_skill.input_mode = 'detailed'))
      then
        perform app_private.raise_api_error(400, 'validation_failed');
      end if;
      v_value := v_in -> 'band';
      if v_value is not null and v_value <> 'null'::jsonb then
        if jsonb_typeof(v_value) <> 'number' or not app_private.is_band(v_value::text::numeric) then
          perform app_private.raise_api_error(400, 'validation_failed');
        end if;
        v_band := v_value::text::numeric;
      end if;
      v_value := v_in -> 'correctAnswers';
      if v_value is not null and v_value <> 'null'::jsonb then
        if jsonb_typeof(v_value) <> 'number' then
          perform app_private.raise_api_error(400, 'validation_failed');
        end if;
        v_number := v_value::text::numeric;
        if v_number <> trunc(v_number) or v_number < 0 or v_number > v_skill.max_questions then
          perform app_private.raise_api_error(400, 'validation_failed');
        end if;
        v_answers := v_number::integer;
      end if;
    else
      if exists (select 1 from jsonb_object_keys(v_in) k where k <> 'criteria')
        or jsonb_typeof(v_in -> 'criteria') is distinct from 'object'
      then
        perform app_private.raise_api_error(400, 'validation_failed');
      end if;
      for v_code, v_value in select e.key, e.value from jsonb_each(v_in -> 'criteria') e
      loop
        if not (v_code = any (app_private.ielts_criteria(p_config.formula_version, v_skill.skill))) then
          perform app_private.raise_api_error(400, 'validation_failed');
        end if;
        continue when v_value = 'null'::jsonb;
        if jsonb_typeof(v_value) <> 'number' or not app_private.is_band(v_value::text::numeric) then
          perform app_private.raise_api_error(400, 'validation_failed');
        end if;
        v_criteria := v_criteria || jsonb_build_object(v_code, v_value::text::numeric);
      end loop;
    end if;

    continue when v_band is null and v_answers is null and v_criteria = '{}';
    v_items := v_items || jsonb_build_array(
      jsonb_strip_nulls(jsonb_build_object('skill', v_skill.skill, 'answers', v_answers, 'band', v_band))
      || jsonb_build_object('criteria', v_criteria));
  end loop;

  -- Nothing entered is not a result: the client sends null to clear instead.
  if jsonb_array_length(v_items) = 0 then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  return jsonb_build_object('kind', 'graded', 'components', '[]'::jsonb, 'ielts', v_items);
end
$$;

-------------------------------------------------------------------------------
-- Derived values, snapshots and DTOs.
-------------------------------------------------------------------------------

-- {L: {correctAnswers, inputBand, band, task1Band, task2Band, criteria}, ...},
-- or NULL when the result has no IELTS input.
create function app_private.ielts_result_json(p_result_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_object_agg(r.skill, jsonb_build_object(
           'correctAnswers', r.correct_answers,
           'inputBand', r.input_band,
           'band', app_private.ielts_effective_band(s, r),
           'task1Band', r.task1_band,
           'task2Band', r.task2_band,
           'criteria', coalesce((select jsonb_object_agg(c.criterion_code, c.band)
                                   from app.ielts_criterion_results c
                                  where c.result_id = r.result_id and c.skill = r.skill), '{}')))
    from app.ielts_skill_results r
    join app.test_ielts_skills s on s.config_id = r.config_id and s.skill = r.skill
   where r.result_id = p_result_id
$$;

-- Complete: Absent; every component; one value; or, for IELTS, every chosen
-- skill complete in its mode (L/R in detail need both answers and band).
create or replace function app_private.result_complete(p_result app.test_results)
returns boolean
language sql
stable
set search_path = ''
as $$
  select p_result.deleted_at is null and (
    p_result.result_kind = 'absent'
    or (select case
          when c.scale_kind = 'ielts' then
            not exists (
              select 1 from app.test_ielts_skills s
                left join app.ielts_skill_results r on r.result_id = p_result.id and r.skill = s.skill
               where s.config_id = c.id
                 and not coalesce(case
                       when s.input_mode = 'detailed' and s.skill in ('L', 'R')
                         then r.correct_answers is not null and r.input_band is not null
                       else app_private.ielts_effective_band(s, r) is not null
                     end, false))
          when c.input_mode = 'components' then
            (select count(*) from app.component_results x where x.result_id = p_result.id)
            = (select count(*) from app.test_components k where k.config_id = c.id)
          else num_nonnulls(p_result.numeric_score, p_result.correct_answers, p_result.letter_level_id) = 1
        end
          from app.test_config_versions c where c.id = p_result.config_id))
$$;

create or replace function app_private.result_snapshot(p_result app.test_results)
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
    'ielts', app_private.ielts_result_json(p_result.id),
    'overall_band', p_result.overall_band,
    'published_at', p_result.published_at,
    'published_by', p_result.published_by,
    'deleted_at', p_result.deleted_at,
    'deleted_by', p_result.deleted_by
  )
$$;

create or replace function app_private.result_dto(p_result app.test_results)
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
    'ielts', app_private.ielts_result_json(p_result.id),
    'overallBand', p_result.overall_band,
    'complete', app_private.result_complete(p_result),
    'published', p_result.published_at is not null,
    'publishedAt', p_result.published_at,
    'publishedByName', (select b.full_name from app.account_profiles b where b.id = p_result.published_by),
    'rowVersion', p_result.row_version,
    'updatedAt', p_result.updated_at,
    'updatedByName', a.full_name
  )
    from app.account_profiles a
   where a.id = p_result.updated_by
$$;

-- Stored result in the normalized shape of result_entry (IELTS inputs only:
-- computed bands are not inputs).
create or replace function app_private.result_entry_of(p_result app.test_results)
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
    || coalesce((
         select jsonb_build_object('ielts', jsonb_agg(
                  jsonb_strip_nulls(jsonb_build_object('skill', r.skill, 'answers', r.correct_answers,
                                                       'band', r.input_band))
                  || jsonb_build_object('criteria', coalesce((
                       select jsonb_object_agg(c.criterion_code, c.band)
                         from app.ielts_criterion_results c
                        where c.result_id = r.result_id and c.skill = r.skill), '{}'))
                  order by array_position(array['L', 'R', 'W', 'S'], r.skill)))
           from app.ielts_skill_results r
          where r.result_id = p_result.id
         having count(*) > 0), '{}')
$$;

-------------------------------------------------------------------------------
-- Entry and save: IELTS goes through the same command, lock order, history
-- and single audit as the other scales.
-------------------------------------------------------------------------------

create or replace function app_private.result_entry(p_config app.test_config_versions, p_entry jsonb)
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
  if p_config.scale_kind = 'ielts' then
    return app_private.ielts_result_entry(p_config, p_entry);
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

-- As before (one transaction, one audit, published rows locked), now for
-- IELTS too: its inputs are written with the computed bands and Overall.
create or replace function api.save_test_results(p_test_id uuid, p_config_id uuid, p_items jsonb)
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
  -- Shared: results of one test may be saved together, while a date change,
  -- publication or archiving the test waits.
  select * into v_test from app.tests t where t.id = p_test_id for share;
  if v_test.deleted_at is not null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
  if p_config_id is distinct from v_test.current_config_id then
    perform app_private.raise_api_error(409, 'version_conflict');
  end if;
  select * into v_config from app.test_config_versions c where c.id = v_test.current_config_id;
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
      perform app_private.clear_ielts_inputs(v_before.id);
      update app.test_results x
         set numeric_score = null, correct_answers = null, letter_level_id = null, overall_band = null,
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
      perform app_private.clear_ielts_inputs(v_before.id);
      perform app_private.write_ielts_inputs(v_before.id, v_config, coalesce(v_entry -> 'ielts', '[]'));
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
      -- Overall reads the rows just written (and the trigger clears it on Absent).
      if v_after.result_kind = 'graded' and v_config.scale_kind = 'ielts' then
        update app.test_results x
           set overall_band = app_private.ielts_overall(x.id, v_config.id)
         where x.id = v_after.id
        returning * into v_after;
      end if;
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
  app_private.is_band(numeric),
  app_private.round_band(numeric),
  app_private.ielts_criteria(text, text),
  app_private.clear_ielts_inputs(uuid),
  app_private.test_results_clear_ielts(),
  app_private.write_ielts_inputs(uuid, app.test_config_versions, jsonb),
  app_private.ielts_effective_band(app.test_ielts_skills, app.ielts_skill_results),
  app_private.ielts_overall(uuid, uuid),
  app_private.ielts_result_entry(app.test_config_versions, jsonb),
  app_private.ielts_result_json(uuid)
  from public, anon, authenticated;
