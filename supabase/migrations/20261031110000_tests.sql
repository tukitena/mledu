-- GĐ 5, second feature: tests in a class with their own grading snapshot
-- (TEST-05; configuration shapes of TEST-01/04; use of TEST-02 templates).
--
-- A test belongs to one class. Its grading configuration is an immutable,
-- relational snapshot (test_config_versions + letter levels / components /
-- IELTS skills), created from scratch or copied from one exact template
-- version and then adjusted. The configuration is fixed when the test is
-- created: it is never changed afterwards (one snapshot per test). Editing a
-- template never changes a test, and a test never writes to the template library.
--
-- Not in this feature: results (TEST-01/04), publication (ACAD-01) and
-- archive/restore of a test (TEST-06). The deleted_* columns exist so that feature adds no table change.
-- Design: docs/developer/assessment-schema.md.

-------------------------------------------------------------------------------
-- Tables.
-------------------------------------------------------------------------------

create table app.tests (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references app.classes (id),
  -- Duplicate names are allowed in a class (TEST-05); the id and date tell tests apart.
  name text not null,
  name_key text not null,
  test_on date not null,
  description text,
  current_config_id uuid not null,
  -- One display option for the whole test (TEST-04), kept outside the immutable
  -- configuration: it can change on its own, without touching results.
  show_components boolean not null default false,
  row_version bigint not null default 1,
  created_at timestamptz not null default now(),
  created_by uuid not null references app.account_profiles (id),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  deleted_by uuid references app.account_profiles (id),
  deleted_reason text,
  constraint tests_name_check check (
    name = btrim(name) and name is nfc normalized and char_length(name) between 1 and 200
  ),
  constraint tests_name_key_check check (name_key = app_private.name_key(name)),
  constraint tests_description_check check (
    description is null
    or (description = btrim(description) and description is nfc normalized
        and char_length(description) between 1 and 5000)
  ),
  constraint tests_row_version_check check (row_version >= 1),
  constraint tests_deleted_check check (
    (deleted_at is null and deleted_by is null and deleted_reason is null)
    or (deleted_at is not null and deleted_by is not null
        and char_length(deleted_reason) between 1 and 1000)
  )
);

create index tests_class_idx on app.tests (class_id, test_on desc);

comment on table app.tests is
  'Test of a class (TEST-05). Its grading configuration is the snapshot current_config_id.';

create table app.test_config_versions (
  -- Identifier used by results and Excel _Meta (XLS-06).
  id uuid primary key default gen_random_uuid(),
  test_id uuid not null references app.tests (id),
  revision bigint not null,
  scale_kind text not null,
  -- direct/components for numeric and fraction, direct for letter; NULL for IELTS,
  -- whose mode belongs to each skill.
  input_mode text,
  max_score numeric,
  total_questions integer,
  formula_version text,
  -- Provenance only: the exact template version copied. No cascade, no follow-up.
  source_template_version_id uuid references app.test_template_versions (id),
  created_at timestamptz not null default now(),
  created_by uuid not null references app.account_profiles (id),
  constraint test_config_versions_revision_key unique (test_id, revision),
  constraint test_config_versions_test_id_id_key unique (test_id, id),
  -- One snapshot per test: the configuration cannot be changed after creation.
  constraint test_config_versions_revision_check check (revision = 1),
  constraint test_config_versions_shape_check check (
    (scale_kind = 'numeric' and input_mode in ('direct', 'components')
       and max_score > 0 and scale(max_score) <= 2
       and total_questions is null and formula_version is null)
    or (scale_kind = 'fraction' and input_mode in ('direct', 'components')
       and total_questions >= 1 and max_score is null and formula_version is null)
    or (scale_kind = 'letter' and input_mode = 'direct'
       and max_score is null and total_questions is null and formula_version is null)
    or (scale_kind = 'ielts' and input_mode is null
       and max_score is null and total_questions is null and formula_version is not null)
  )
);

create index test_config_versions_source_idx
  on app.test_config_versions (source_template_version_id);

comment on table app.test_config_versions is
  'Immutable grading snapshot of a test (TEST-01/02/04), fixed when the test is created.';

-- The test and its first snapshot are created in one transaction.
alter table app.tests
  add constraint tests_current_config_fkey
  foreign key (id, current_config_id)
  references app.test_config_versions (test_id, id)
  deferrable initially deferred;

create index tests_current_config_idx on app.tests (current_config_id);

create table app.test_letter_levels (
  id uuid primary key default gen_random_uuid(),
  config_id uuid not null references app.test_config_versions (id),
  -- Positional code of the configuration (l1…), stable inside this snapshot.
  code text not null,
  label text not null,
  label_key text not null,
  sort_order smallint not null,
  constraint test_letter_levels_config_id_id_key unique (config_id, id),
  constraint test_letter_levels_label_key unique (config_id, label_key),
  constraint test_letter_levels_order_key unique (config_id, sort_order),
  constraint test_letter_levels_code_check check (code = 'l' || sort_order),
  constraint test_letter_levels_order_check check (sort_order between 1 and 20),
  constraint test_letter_levels_label_check check (
    label = btrim(label) and label is nfc normalized and char_length(label) between 1 and 100
  ),
  constraint test_letter_levels_label_key_check check (label_key = app_private.name_key(label))
);

create table app.test_components (
  id uuid primary key default gen_random_uuid(),
  config_id uuid not null references app.test_config_versions (id),
  code text not null,
  name text not null,
  name_key text not null,
  max_score numeric,
  total_questions integer,
  sort_order smallint not null,
  constraint test_components_config_id_id_key unique (config_id, id),
  constraint test_components_name_key unique (config_id, name_key),
  constraint test_components_order_key unique (config_id, sort_order),
  constraint test_components_code_check check (code = 'c' || sort_order),
  constraint test_components_order_check check (sort_order between 1 and 50),
  constraint test_components_name_check check (
    name = btrim(name) and name is nfc normalized and char_length(name) between 1 and 200
  ),
  constraint test_components_name_key_check check (name_key = app_private.name_key(name)),
  -- Exactly one limit of the right kind (checked against the parent at commit).
  constraint test_components_limit_check check (
    (max_score > 0 and scale(max_score) <= 2 and total_questions is null)
    or (total_questions >= 1 and max_score is null)
  )
);

create table app.test_ielts_skills (
  config_id uuid not null references app.test_config_versions (id),
  skill text not null,
  input_mode text not null,
  max_questions integer,
  primary key (config_id, skill),
  constraint test_ielts_skills_skill_check check (skill in ('L', 'R', 'W', 'S')),
  constraint test_ielts_skills_mode_check check (input_mode in ('direct', 'detailed')),
  -- L/R detailed keep a maximum number of questions; nothing else has one.
  constraint test_ielts_skills_questions_check check (
    (skill in ('L', 'R') and input_mode = 'detailed' and max_questions >= 1)
    or (not (skill in ('L', 'R') and input_mode = 'detailed') and max_questions is null)
  )
);

comment on table app.test_letter_levels is 'Letter levels of one test snapshot (TEST-01/02).';
comment on table app.test_components is 'Components of one numeric/fraction test snapshot (TEST-04).';
comment on table app.test_ielts_skills is 'Skills and per-skill mode of one IELTS test snapshot (TEST-01).';

-------------------------------------------------------------------------------
-- Snapshot as configuration JSON. Same normalized shape as a template version
-- (contracts TestTemplateConfig); showComponents comes from the test.
-------------------------------------------------------------------------------

create function app_private.test_config_json(p_config_id uuid, p_show boolean)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select case
    when c.scale_kind in ('numeric', 'fraction') and c.input_mode = 'direct' then
      jsonb_build_object('scaleKind', c.scale_kind, 'inputMode', 'direct',
        case c.scale_kind when 'numeric' then 'maxScore' else 'totalQuestions' end,
        case c.scale_kind when 'numeric' then to_jsonb(c.max_score) else to_jsonb(c.total_questions) end)
    when c.scale_kind = 'numeric' then
      jsonb_build_object('scaleKind', 'numeric', 'inputMode', 'components',
        'maxScore', c.max_score, 'showComponents', coalesce(p_show, false),
        'components', coalesce((
          select jsonb_agg(jsonb_build_object('code', x.code, 'name', x.name, 'maxScore', x.max_score)
                           order by x.sort_order)
            from app.test_components x where x.config_id = c.id), '[]'))
    when c.scale_kind = 'fraction' then
      jsonb_build_object('scaleKind', 'fraction', 'inputMode', 'components',
        'totalQuestions', c.total_questions, 'showComponents', coalesce(p_show, false),
        'components', coalesce((
          select jsonb_agg(jsonb_build_object('code', x.code, 'name', x.name,
                                              'totalQuestions', x.total_questions)
                           order by x.sort_order)
            from app.test_components x where x.config_id = c.id), '[]'))
    when c.scale_kind = 'letter' then
      jsonb_build_object('scaleKind', 'letter', 'inputMode', 'direct',
        'levels', coalesce((
          select jsonb_agg(jsonb_build_object('code', l.code, 'label', l.label) order by l.sort_order)
            from app.test_letter_levels l where l.config_id = c.id), '[]'))
    else
      jsonb_build_object('scaleKind', 'ielts', 'formulaVersion', c.formula_version,
        'showComponents', coalesce(p_show, false)
          and exists (select 1 from app.test_ielts_skills s
                       where s.config_id = c.id and s.input_mode = 'detailed'),
        'skills', coalesce((
          select jsonb_agg(case when s.max_questions is null
                             then jsonb_build_object('code', s.skill, 'inputMode', s.input_mode)
                             else jsonb_build_object('code', s.skill, 'inputMode', s.input_mode,
                                                     'maxQuestions', s.max_questions) end
                           order by array_position(array['L', 'R', 'W', 'S'], s.skill))
            from app.test_ielts_skills s where s.config_id = c.id), '[]'))
  end
    from app.test_config_versions c
   where c.id = p_config_id
$$;

-- True when the configuration has details that the display option can show
-- (components, or an IELTS skill entered in detail).
create function app_private.config_has_details(p_config jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_config ->> 'inputMode' = 'components'
      or exists (select 1 from jsonb_array_elements(coalesce(p_config -> 'skills', '[]')) s
                  where s ->> 'inputMode' = 'detailed')
$$;

-- Counts, totals, kinds and codes of the child rows cannot be proved by one-row
-- CHECKs. At commit, the snapshot rebuilt from its rows must be a valid, already
-- normalized configuration (same validator as templates), whoever inserted it.
-- Deferred triggers run at commit as the session role, outside the RPC's
-- SECURITY DEFINER scope, so this one reads the snapshot as its owner.
create function app_private.check_test_config()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_config_id uuid;
  v_config jsonb;
begin
  if tg_table_name = 'test_config_versions' then
    v_config_id := new.id;
  else
    v_config_id := new.config_id;
  end if;
  v_config := app_private.test_config_json(v_config_id, false);
  if v_config is null or app_private.test_template_config(v_config) <> v_config then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  return null;
end
$$;

create constraint trigger test_config_versions_valid
  after insert on app.test_config_versions
  deferrable initially deferred
  for each row execute function app_private.check_test_config();
create constraint trigger test_letter_levels_valid
  after insert on app.test_letter_levels
  deferrable initially deferred
  for each row execute function app_private.check_test_config();
create constraint trigger test_components_valid
  after insert on app.test_components
  deferrable initially deferred
  for each row execute function app_private.check_test_config();
create constraint trigger test_ielts_skills_valid
  after insert on app.test_ielts_skills
  deferrable initially deferred
  for each row execute function app_private.check_test_config();

-- Snapshots are never edited or removed; tests are archived later, never deleted.
create trigger test_config_versions_no_change
  before update or delete on app.test_config_versions
  for each row execute function app_private.reject_change();
create trigger test_letter_levels_no_change
  before update or delete on app.test_letter_levels
  for each row execute function app_private.reject_change();
create trigger test_components_no_change
  before update or delete on app.test_components
  for each row execute function app_private.reject_change();
create trigger test_ielts_skills_no_change
  before update or delete on app.test_ielts_skills
  for each row execute function app_private.reject_change();
create trigger tests_no_delete
  before delete on app.tests
  for each row execute function app_private.reject_change();
create trigger test_config_versions_no_truncate
  before truncate on app.test_config_versions
  for each statement execute function app_private.reject_change();
create trigger test_letter_levels_no_truncate
  before truncate on app.test_letter_levels
  for each statement execute function app_private.reject_change();
create trigger test_components_no_truncate
  before truncate on app.test_components
  for each statement execute function app_private.reject_change();
create trigger test_ielts_skills_no_truncate
  before truncate on app.test_ielts_skills
  for each statement execute function app_private.reject_change();
create trigger tests_no_truncate
  before truncate on app.tests
  for each statement execute function app_private.reject_change();

alter table app.tests enable row level security;
alter table app.test_config_versions enable row level security;
alter table app.test_letter_levels enable row level security;
alter table app.test_components enable row level security;
alter table app.test_ielts_skills enable row level security;
revoke all on table app.tests, app.test_config_versions, app.test_letter_levels,
  app.test_components, app.test_ielts_skills from public, anon, authenticated;

-- Writes one snapshot from a normalized configuration (validator output).
create function app_private.insert_test_config(
  p_config_id uuid,
  p_test_id uuid,
  p_revision bigint,
  p_config jsonb,
  p_source_version_id uuid,
  p_actor_id uuid
)
returns void
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_kind text := p_config ->> 'scaleKind';
begin
  insert into app.test_config_versions
    (id, test_id, revision, scale_kind, input_mode, max_score, total_questions, formula_version,
     source_template_version_id, created_by)
  values (p_config_id, p_test_id, p_revision, v_kind,
          case when v_kind = 'ielts' then null else p_config ->> 'inputMode' end,
          case when v_kind = 'numeric' then (p_config ->> 'maxScore')::numeric end,
          case when v_kind = 'fraction' then (p_config ->> 'totalQuestions')::integer end,
          case when v_kind = 'ielts' then p_config ->> 'formulaVersion' end,
          p_source_version_id, p_actor_id);

  if v_kind in ('numeric', 'fraction') and p_config ->> 'inputMode' = 'components' then
    insert into app.test_components
      (config_id, code, name, name_key, max_score, total_questions, sort_order)
    select p_config_id, e.value ->> 'code', e.value ->> 'name',
           app_private.name_key(e.value ->> 'name'),
           (e.value ->> 'maxScore')::numeric, (e.value ->> 'totalQuestions')::integer, e.ordinality
      from jsonb_array_elements(p_config -> 'components') with ordinality e;
  elsif v_kind = 'letter' then
    insert into app.test_letter_levels (config_id, code, label, label_key, sort_order)
    select p_config_id, e.value ->> 'code', e.value ->> 'label',
           app_private.name_key(e.value ->> 'label'), e.ordinality
      from jsonb_array_elements(p_config -> 'levels') with ordinality e;
  elsif v_kind = 'ielts' then
    insert into app.test_ielts_skills (config_id, skill, input_mode, max_questions)
    select p_config_id, s.value ->> 'code', s.value ->> 'inputMode',
           (s.value ->> 'maxQuestions')::integer
      from jsonb_array_elements(p_config -> 'skills') s;
  end if;
end
$$;

-------------------------------------------------------------------------------
-- Snapshots (history/audit) and DTOs (packages/contracts/src/assessments.ts).
-------------------------------------------------------------------------------

create function app_private.test_snapshot(p_test app.tests)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'class_id', p_test.class_id,
    'name', p_test.name,
    'test_on', p_test.test_on,
    'description', p_test.description,
    'show_components', p_test.show_components,
    'current_config_id', p_test.current_config_id,
    'config', app_private.test_config_json(c.id, p_test.show_components),
    'source_template_version_id', c.source_template_version_id,
    'deleted_at', p_test.deleted_at,
    'deleted_by', p_test.deleted_by,
    'deleted_reason', p_test.deleted_reason
  )
    from app.test_config_versions c
   where c.id = p_test.current_config_id
$$;

create function app_private.test_source_dto(p_version_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'templateId', v.template_id,
    'templateVersionId', v.id,
    'revision', v.revision,
    'name', v.name,
    'templateArchived', t.deleted_at is not null
  )
    from app.test_template_versions v
    join app.test_templates t on t.id = v.template_id
   where v.id = p_version_id
$$;

create function app_private.test_dto(p_test app.tests)
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
    'config', app_private.test_config_json(c.id, p_test.show_components),
    'source', app_private.test_source_dto(c.source_template_version_id),
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
-- Academic rights at request time (TEST-05, TEST-01, TEST-04).
-------------------------------------------------------------------------------

-- Read: Admin, or a User with an assignment in effect (teacher or assistant).
-- Receptionists have no academic access (A.1). A User without a role gets 404,
-- like a class it cannot read.
create function app_private.require_test_reader(p_class_id uuid)
returns app.account_profiles
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_account();
begin
  if not exists (select 1 from app.classes c where c.id = p_class_id) then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  if v_actor.account_type = 'receptionist' then
    perform app_private.raise_api_error(403, 'forbidden');
  end if;
  if v_actor.account_type <> 'admin' and app_private.class_role(v_actor.id, p_class_id) is null then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  return v_actor;
end
$$;

-- Write: as read, in a class that is not deleted. Locks the actor, the class
-- (shared, so class deletion waits) and the User's assignment, then checks the
-- assignment again so a revocation cannot commit in between. p_display asks
-- for the display right of TEST-04 (Admin or teacher; assistants are refused).
create function app_private.require_test_editor(p_class_id uuid, p_display boolean default false)
returns app.account_profiles
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_account(p_lock => true);
  v_class app.classes;
begin
  select * into v_class from app.classes c where c.id = p_class_id for share;
  if not found then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  if v_actor.account_type = 'receptionist' then
    perform app_private.raise_api_error(403, 'forbidden');
  end if;
  if v_actor.account_type <> 'admin' then
    if app_private.class_role(v_actor.id, p_class_id) is null then
      perform app_private.raise_api_error(404, 'not_found');
    end if;
    perform app_private.lock_student_edit_assignment(v_actor.id, array[p_class_id]);
    if p_display and app_private.class_role(v_actor.id, p_class_id) is distinct from 'teacher' then
      perform app_private.raise_api_error(403, 'forbidden');
    end if;
  end if;
  if v_class.deleted_at is not null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
  return v_actor;
end
$$;

-- A newly chosen template version: the template is locked (shared, so an
-- archive or edit waits), must not be archived and must still point at the
-- version the user reviewed (TEST-02).
create function app_private.lock_template_source(p_version_id uuid)
returns void
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_template app.test_templates;
begin
  select t.* into v_template
    from app.test_templates t
    join app.test_template_versions v on v.template_id = t.id
   where v.id = p_version_id
     for share of t;
  if not found then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  if v_template.deleted_at is not null or v_template.current_version_id <> p_version_id then
    perform app_private.raise_api_error(409, 'template_unavailable');
  end if;
end
$$;

create function app_private.lock_test(p_id uuid, p_expected_version bigint)
returns app.tests
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_test app.tests;
begin
  select * into v_test from app.tests t where t.id = p_id for update;
  if not found then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  if p_expected_version is null or v_test.row_version <> p_expected_version then
    perform app_private.raise_api_error(409, 'version_conflict');
  end if;
  if v_test.deleted_at is not null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
  return v_test;
end
$$;

-- TEST-05: the test date lies within the class dates. Results do not exist yet;
-- the participation check of a changed date arrives with them.
create function app_private.check_test_date(p_class_id uuid, p_test_on date)
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  if p_test_on is null then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  if not exists (select 1 from app.classes c
                  where c.id = p_class_id and p_test_on between c.start_date and c.end_date) then
    perform app_private.raise_api_error(409, 'outside_class_dates');
  end if;
end
$$;

-------------------------------------------------------------------------------
-- Reads.
-------------------------------------------------------------------------------

-- Tests of a class, newest date first, with what the caller may do.
create function api.list_class_tests(p_class_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_test_reader(p_class_id);
  v_open boolean := exists (select 1 from app.classes c where c.id = p_class_id and c.deleted_at is null);
  v_role text := app_private.class_role(v_actor.id, p_class_id);
begin
  return jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(app_private.test_dto(t) order by t.test_on desc, t.created_at desc, t.id)
        from app.tests t
       where t.class_id = p_class_id and t.deleted_at is null
    ), '[]'),
    'canEdit', v_open and (v_actor.account_type = 'admin' or v_role is not null),
    'canChangeDisplay', v_open and (v_actor.account_type = 'admin' or v_role = 'teacher'));
end
$$;

-- One test.
create function api.get_test(p_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_test app.tests;
begin
  select * into v_test from app.tests t where t.id = p_id;
  if not found then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  perform app_private.require_test_reader(v_test.class_id);
  return app_private.test_dto(v_test);
end
$$;

-- Templates a person who may configure tests of this class can pick: current
-- version of every template that is not archived (TEST-02). Receptionists and
-- Users without a role are refused, as for writing tests.
create function api.list_test_template_choices(p_class_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  perform app_private.require_test_reader(p_class_id);
  if exists (select 1 from app.classes c where c.id = p_class_id and c.deleted_at is not null) then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
  return coalesce((
    select jsonb_agg(app_private.test_template_dto(t) order by app_private.name_key(v.name), t.id)
      from app.test_templates t
      join app.test_template_versions v on v.id = t.current_version_id
     where t.deleted_at is null
  ), '[]');
end
$$;

-------------------------------------------------------------------------------
-- Commands. Each writes history and one audit in its transaction.
-------------------------------------------------------------------------------

-- TEST-05: from scratch (p_source_template_version_id NULL) or from a template
-- version whose configuration the user may have adjusted. The display option
-- starts from the configuration sent.
create function api.create_test(
  p_class_id uuid,
  p_name text,
  p_test_on date,
  p_description text,
  p_config jsonb,
  p_source_template_version_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_test_editor(p_class_id);
  v_name text := app_private.clean_text(p_name, 200);
  v_description text := app_private.clean_optional_text(p_description, 5000);
  v_config jsonb := app_private.test_template_config(p_config);
  v_test app.tests;
begin
  perform app_private.check_test_date(p_class_id, p_test_on);
  if p_source_template_version_id is not null then
    perform app_private.lock_template_source(p_source_template_version_id);
  end if;

  insert into app.tests
    (class_id, name, name_key, test_on, description, current_config_id, show_components, created_by)
  values (p_class_id, v_name, app_private.name_key(v_name), p_test_on, v_description,
          gen_random_uuid(),
          app_private.config_has_details(v_config) and coalesce((v_config ->> 'showComponents')::boolean, false),
          v_actor.id)
  returning * into v_test;

  perform app_private.insert_test_config(v_test.current_config_id, v_test.id, 1, v_config,
    p_source_template_version_id, v_actor.id);

  perform app_private.record_change('test', v_test.id, v_test.row_version, null,
    app_private.test_snapshot(v_test), v_actor.id, 'test.create',
    jsonb_strip_nulls(jsonb_build_object('class_id', p_class_id, 'test_id', v_test.id,
      'test_config_id', v_test.current_config_id,
      'test_template_version_id', p_source_template_version_id)));
  return app_private.test_dto(v_test);
end
$$;

-- TEST-05: name, date and description only; never the configuration, display
-- option, results or publication. Unchanged content returns the test as it is.
create function api.update_test(
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

  perform app_private.record_change('test', v_after.id, v_after.row_version,
    app_private.test_snapshot(v_before), app_private.test_snapshot(v_after), v_actor.id,
    'test.update', jsonb_build_object('class_id', v_class_id, 'test_id', v_after.id));
  return app_private.test_dto(v_after);
end
$$;

-- TEST-04 display option of the whole test: Admin or teacher only; changes no
-- configuration, result or publication.
create function api.set_test_show_components(p_id uuid, p_show boolean, p_expected_version bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_class_id uuid := (select t.class_id from app.tests t where t.id = p_id);
  v_actor app.account_profiles;
  v_before app.tests;
  v_after app.tests;
begin
  if v_class_id is null then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  v_actor := app_private.require_test_editor(v_class_id, p_display => true);
  if p_show is null then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  v_before := app_private.lock_test(p_id, p_expected_version);
  if not app_private.config_has_details(app_private.test_config_json(v_before.current_config_id, false)) then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
  if v_before.show_components = p_show then
    return app_private.test_dto(v_before);
  end if;

  update app.tests t
     set show_components = p_show,
         row_version = t.row_version + 1,
         updated_at = now()
   where t.id = v_before.id
  returning * into v_after;

  perform app_private.record_change('test', v_after.id, v_after.row_version,
    app_private.test_snapshot(v_before), app_private.test_snapshot(v_after), v_actor.id,
    'test.set_show_components', jsonb_build_object('class_id', v_class_id, 'test_id', v_after.id));
  return app_private.test_dto(v_after);
end
$$;

revoke all on function
  api.list_class_tests(uuid),
  api.get_test(uuid),
  api.list_test_template_choices(uuid),
  api.create_test(uuid, text, date, text, jsonb, uuid),
  api.update_test(uuid, text, date, text, bigint),
  api.set_test_show_components(uuid, boolean, bigint)
  from public, anon;
grant execute on function
  api.list_class_tests(uuid),
  api.get_test(uuid),
  api.list_test_template_choices(uuid),
  api.create_test(uuid, text, date, text, jsonb, uuid),
  api.update_test(uuid, text, date, text, bigint),
  api.set_test_show_components(uuid, boolean, bigint)
  to authenticated;
