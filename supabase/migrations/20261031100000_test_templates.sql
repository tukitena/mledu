-- GĐ 5, first feature: shared test template library (TEST-02, techstack §4.6).
--
-- One library for the whole centre (no class, site or tenant ownership). Only a
-- current Admin creates, edits, archives or restores templates. Every edit adds
-- an immutable version and moves the template's pointer to it, so tests copied
-- from an older version (later GĐ 5 feature) never change. Archiving only stops
-- new use; versions are never deleted.
--
-- The configuration of a version is typed JSONB validated here (not only in
-- TypeScript): numeric / fraction / letter / IELTS, input modes, components,
-- letter levels and IELTS skills. It never holds SQL, expressions or formulas;
-- the IELTS formula is fixed by TEST-01 and identified by formulaVersion.
-- Design: docs/developer/assessment-schema.md.

-------------------------------------------------------------------------------
-- JSON validation helpers. Any problem is a 400 validation_failed; the API
-- validates the same shape first and reports field paths.
-------------------------------------------------------------------------------

-- p_value is an object holding every required key and no key outside the lists.
create function app_private.assert_json_keys(
  p_value jsonb,
  p_required text[],
  p_optional text[] default '{}'
)
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  if p_value is null
    or jsonb_typeof(p_value) <> 'object'
    or not (p_value ?& p_required)
    or exists (select 1 from jsonb_object_keys(p_value) k where k <> all (p_required || p_optional))
  then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
end
$$;

-- Positive score with at most two decimals (TEST-01). Trailing zeros are dropped;
-- more decimals are refused, never rounded. No upper bound is added beyond the spec.
create function app_private.json_max_score(p_value jsonb)
returns numeric
language plpgsql
stable
set search_path = ''
as $$
declare
  v_value numeric;
begin
  if p_value is null or jsonb_typeof(p_value) <> 'number' then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  v_value := trim_scale((p_value #>> '{}')::numeric);
  if v_value <= 0 or scale(v_value) > 2 then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  return v_value;
end
$$;

-- Positive integer (question counts).
create function app_private.json_positive_int(p_value jsonb)
returns integer
language plpgsql
stable
set search_path = ''
as $$
declare
  v_value numeric;
begin
  if p_value is null or jsonb_typeof(p_value) <> 'number' then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  v_value := (p_value #>> '{}')::numeric;
  if v_value <> trunc(v_value) or v_value < 1 or v_value > 2147483647 then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  return v_value::integer;
end
$$;

create function app_private.json_text(p_value jsonb)
returns text
language plpgsql
stable
set search_path = ''
as $$
begin
  if p_value is null or jsonb_typeof(p_value) <> 'string' then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  return p_value #>> '{}';
end
$$;

create function app_private.json_boolean(p_value jsonb)
returns boolean
language plpgsql
stable
set search_path = ''
as $$
begin
  if p_value is null or jsonb_typeof(p_value) <> 'boolean' then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  return (p_value #>> '{}')::boolean;
end
$$;

-- Approved IELTS formula of TEST-01 (Task rounding, then Writing 1:2; S average;
-- Overall only with four bands). Templates and tests never choose a formula.
create function app_private.ielts_formula_version()
returns text
language sql
immutable
set search_path = ''
as $$ select 'mledu-ielts-v1' $$;

-- Validates a template configuration (schema version 1) and returns its
-- normalized form: names trimmed/NFC, trailing zeros dropped, component/level
-- codes assigned by position, totals computed, IELTS skills in L/R/W/S order
-- and the formula version attached by the backend.
create function app_private.test_template_config(p_config jsonb)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_kind text;
  v_mode text;
  v_limit_key text;
  v_item jsonb;
  v_index bigint;
  v_name text;
  v_keys text[] := '{}';
  v_items jsonb := '[]';
  v_score numeric;
  v_score_total numeric := 0;
  v_count integer;
  v_count_total bigint := 0;
  v_show boolean;
  v_code text;
  v_skill_mode text;
  v_detailed boolean := false;
begin
  if p_config is null or jsonb_typeof(p_config) <> 'object' then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  v_kind := app_private.json_text(p_config -> 'scaleKind');

  if v_kind in ('numeric', 'fraction') then
    v_limit_key := case v_kind when 'numeric' then 'maxScore' else 'totalQuestions' end;
    v_mode := app_private.json_text(p_config -> 'inputMode');

    if v_mode = 'direct' then
      perform app_private.assert_json_keys(p_config, array['scaleKind', 'inputMode', v_limit_key]);
      return jsonb_build_object(
        'scaleKind', v_kind,
        'inputMode', 'direct',
        v_limit_key, case v_kind
          when 'numeric' then to_jsonb(app_private.json_max_score(p_config -> v_limit_key))
          else to_jsonb(app_private.json_positive_int(p_config -> v_limit_key)) end);
    elsif v_mode <> 'components' then
      perform app_private.raise_api_error(400, 'validation_failed');
    end if;

    -- TEST-04: 1–50 components; the whole test's limit is their sum.
    perform app_private.assert_json_keys(p_config,
      array['scaleKind', 'inputMode', 'showComponents', 'components'], array[v_limit_key]);
    v_show := app_private.json_boolean(p_config -> 'showComponents');
    if jsonb_typeof(p_config -> 'components') <> 'array'
      or jsonb_array_length(p_config -> 'components') not between 1 and 50
    then
      perform app_private.raise_api_error(400, 'validation_failed');
    end if;

    for v_item, v_index in
      select e.value, e.ordinality from jsonb_array_elements(p_config -> 'components') with ordinality e
    loop
      -- Codes are assigned by position; a code sent back must be that one.
      perform app_private.assert_json_keys(v_item, array['name', v_limit_key], array['code']);
      if v_item ? 'code' and app_private.json_text(v_item -> 'code') <> ('c' || v_index) then
        perform app_private.raise_api_error(400, 'validation_failed');
      end if;
      v_name := app_private.clean_text(app_private.json_text(v_item -> 'name'), 200);
      if app_private.name_key(v_name) = any (v_keys) then
        perform app_private.raise_api_error(400, 'validation_failed');
      end if;
      v_keys := v_keys || app_private.name_key(v_name);
      if v_kind = 'numeric' then
        v_score := app_private.json_max_score(v_item -> v_limit_key);
        v_score_total := v_score_total + v_score;
        v_items := v_items || jsonb_build_object('code', 'c' || v_index, 'name', v_name,
          v_limit_key, v_score);
      else
        v_count := app_private.json_positive_int(v_item -> v_limit_key);
        v_count_total := v_count_total + v_count;
        v_items := v_items || jsonb_build_object('code', 'c' || v_index, 'name', v_name,
          v_limit_key, v_count);
      end if;
    end loop;

    if v_kind = 'fraction' and v_count_total > 2147483647 then
      perform app_private.raise_api_error(400, 'validation_failed');
    end if;
    -- A total sent by the client must match the sum; the backend stays the source.
    if p_config ? v_limit_key
      and (jsonb_typeof(p_config -> v_limit_key) <> 'number'
           or (p_config ->> v_limit_key)::numeric
              <> case v_kind when 'numeric' then v_score_total else v_count_total end)
    then
      perform app_private.raise_api_error(400, 'validation_failed');
    end if;

    return jsonb_build_object(
      'scaleKind', v_kind,
      'inputMode', 'components',
      v_limit_key, case v_kind when 'numeric' then to_jsonb(trim_scale(v_score_total))
                               else to_jsonb(v_count_total) end,
      'showComponents', v_show,
      'components', v_items);

  elsif v_kind = 'letter' then
    -- TEST-02: 1–20 levels, labels 1–100 characters, unique by name key.
    perform app_private.assert_json_keys(p_config, array['scaleKind', 'inputMode', 'levels']);
    if app_private.json_text(p_config -> 'inputMode') <> 'direct'
      or jsonb_typeof(p_config -> 'levels') <> 'array'
      or jsonb_array_length(p_config -> 'levels') not between 1 and 20
    then
      perform app_private.raise_api_error(400, 'validation_failed');
    end if;
    for v_item, v_index in
      select e.value, e.ordinality from jsonb_array_elements(p_config -> 'levels') with ordinality e
    loop
      perform app_private.assert_json_keys(v_item, array['label'], array['code']);
      if v_item ? 'code' and app_private.json_text(v_item -> 'code') <> ('l' || v_index) then
        perform app_private.raise_api_error(400, 'validation_failed');
      end if;
      v_name := app_private.clean_text(app_private.json_text(v_item -> 'label'), 100);
      if app_private.name_key(v_name) = any (v_keys) then
        perform app_private.raise_api_error(400, 'validation_failed');
      end if;
      v_keys := v_keys || app_private.name_key(v_name);
      v_items := v_items || jsonb_build_object('code', 'l' || v_index, 'label', v_name);
    end loop;
    return jsonb_build_object('scaleKind', 'letter', 'inputMode', 'direct', 'levels', v_items);

  elsif v_kind = 'ielts' then
    -- TEST-01: 1–4 distinct skills, each direct or detailed. L/R detailed keep a
    -- maximum number of questions; W/S detailed use the fixed criteria of the formula.
    perform app_private.assert_json_keys(p_config, array['scaleKind', 'showComponents', 'skills'],
      array['formulaVersion']);
    if p_config ? 'formulaVersion'
      and app_private.json_text(p_config -> 'formulaVersion') <> app_private.ielts_formula_version()
    then
      perform app_private.raise_api_error(400, 'validation_failed');
    end if;
    v_show := app_private.json_boolean(p_config -> 'showComponents');
    if jsonb_typeof(p_config -> 'skills') <> 'array'
      or jsonb_array_length(p_config -> 'skills') not between 1 and 4
    then
      perform app_private.raise_api_error(400, 'validation_failed');
    end if;
    for v_item in select e.value from jsonb_array_elements(p_config -> 'skills') e
    loop
      perform app_private.assert_json_keys(v_item, array['code', 'inputMode'], array['maxQuestions']);
      v_code := app_private.json_text(v_item -> 'code');
      v_skill_mode := app_private.json_text(v_item -> 'inputMode');
      if v_code not in ('L', 'R', 'W', 'S') or v_code = any (v_keys)
        or v_skill_mode not in ('direct', 'detailed')
        or ((v_code in ('L', 'R') and v_skill_mode = 'detailed') <> (v_item ? 'maxQuestions'))
      then
        perform app_private.raise_api_error(400, 'validation_failed');
      end if;
      v_keys := v_keys || v_code;
      v_detailed := v_detailed or v_skill_mode = 'detailed';
    end loop;
    -- Canonical L, R, W, S order.
    select jsonb_agg(
             case when s.value ? 'maxQuestions'
               then jsonb_build_object('code', s.value ->> 'code', 'inputMode', 'detailed',
                      'maxQuestions', app_private.json_positive_int(s.value -> 'maxQuestions'))
               else jsonb_build_object('code', s.value ->> 'code', 'inputMode', s.value ->> 'inputMode')
             end
             order by array_position(array['L', 'R', 'W', 'S'], s.value ->> 'code'))
      into v_items
      from jsonb_array_elements(p_config -> 'skills') s;
    return jsonb_build_object(
      'scaleKind', 'ielts',
      'formulaVersion', app_private.ielts_formula_version(),
      -- Only detailed skills have details to show (TEST-04).
      'showComponents', v_show and v_detailed,
      'skills', v_items);
  end if;

  perform app_private.raise_api_error(400, 'validation_failed');
end
$$;

comment on function app_private.test_template_config(jsonb) is
  'TEST-01/02 template configuration v1: validates and returns the normalized JSON.';

-------------------------------------------------------------------------------
-- Tables.
-------------------------------------------------------------------------------

create table app.test_templates (
  -- Stable across versions, archive and restore.
  id uuid primary key default gen_random_uuid(),
  current_version_id uuid not null,
  row_version bigint not null default 1,
  created_at timestamptz not null default now(),
  created_by uuid not null references app.account_profiles (id),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  deleted_by uuid references app.account_profiles (id),
  deleted_reason text,
  constraint test_templates_row_version_check check (row_version >= 1),
  constraint test_templates_deleted_check check (
    (deleted_at is null and deleted_by is null and deleted_reason is null)
    or (deleted_at is not null and deleted_by is not null
        and char_length(deleted_reason) between 1 and 1000)
  )
);

comment on table app.test_templates is
  'Shared test templates (TEST-02). Admin only; no class/site ownership. Archive keeps every version.';

create table app.test_template_versions (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references app.test_templates (id),
  revision bigint not null,
  -- Name/description are versioned so older tests keep the name of their source.
  name text not null,
  description text,
  config_schema_version smallint not null,
  config jsonb not null,
  created_at timestamptz not null default now(),
  created_by uuid not null references app.account_profiles (id),
  constraint test_template_versions_revision_key unique (template_id, revision),
  constraint test_template_versions_template_id_id_key unique (template_id, id),
  constraint test_template_versions_revision_check check (revision >= 1),
  constraint test_template_versions_name_check check (
    name = btrim(name) and name is nfc normalized and char_length(name) between 1 and 200
  ),
  constraint test_template_versions_description_check check (
    description is null
    or (description = btrim(description) and description is nfc normalized
        and char_length(description) between 1 and 5000)
  ),
  constraint test_template_versions_schema_check check (config_schema_version = 1),
  -- Stored configurations are always in the normalized form produced by the validator.
  constraint test_template_versions_config_check check (
    jsonb_typeof(config) = 'object' and config = app_private.test_template_config(config)
  )
);

comment on table app.test_template_versions is
  'Immutable template versions (TEST-02). Tests reference the exact version they copied.';

-- Template and its first version are created in one transaction: the pointer is
-- checked at commit.
alter table app.test_templates
  add constraint test_templates_current_version_fkey
  foreign key (id, current_version_id)
  references app.test_template_versions (template_id, id)
  deferrable initially deferred;

create index test_templates_current_version_idx on app.test_templates (current_version_id);

-- Versions are never edited or removed, whoever the caller is.
create trigger test_template_versions_no_change
  before update or delete on app.test_template_versions
  for each row execute function app_private.reject_change();

create trigger test_template_versions_no_truncate
  before truncate on app.test_template_versions
  for each statement execute function app_private.reject_change();

create trigger test_templates_no_delete
  before delete on app.test_templates
  for each row execute function app_private.reject_change();

alter table app.test_templates enable row level security;
alter table app.test_template_versions enable row level security;
revoke all on table app.test_templates, app.test_template_versions from public, anon, authenticated;

-------------------------------------------------------------------------------
-- Snapshots (history/audit) and DTOs (packages/contracts/src/assessments.ts).
-------------------------------------------------------------------------------

create function app_private.test_template_snapshot(p_template app.test_templates)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'current_version_id', p_template.current_version_id,
    'revision', v.revision,
    'name', v.name,
    'description', v.description,
    'config_schema_version', v.config_schema_version,
    'config', v.config,
    'deleted_at', p_template.deleted_at,
    'deleted_by', p_template.deleted_by,
    'deleted_reason', p_template.deleted_reason
  )
    from app.test_template_versions v
   where v.id = p_template.current_version_id
$$;

create function app_private.test_template_dto(p_template app.test_templates)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_template.id,
    'currentVersionId', v.id,
    'revision', v.revision,
    'name', v.name,
    'description', v.description,
    'config', v.config,
    'archived', p_template.deleted_at is not null,
    'deletedAt', p_template.deleted_at,
    'deletedReason', p_template.deleted_reason,
    'createdAt', p_template.created_at,
    'updatedAt', p_template.updated_at,
    'rowVersion', p_template.row_version
  )
    from app.test_template_versions v
   where v.id = p_template.current_version_id
$$;

create function app_private.test_template_version_dto(p_version app.test_template_versions)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_version.id,
    'templateId', p_version.template_id,
    'revision', p_version.revision,
    'name', p_version.name,
    'description', p_version.description,
    'config', p_version.config,
    'createdAt', p_version.created_at,
    'createdByName', a.full_name
  )
    from app.account_profiles a
   where a.id = p_version.created_by
$$;

-------------------------------------------------------------------------------
-- Commands. Reads and writes are Admin only in this feature; reading templates
-- to pick one for a test arrives with the test feature, scoped to the class.
-------------------------------------------------------------------------------

create function app_private.lock_test_template(p_id uuid, p_expected_version bigint)
returns app.test_templates
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_template app.test_templates;
begin
  select * into v_template from app.test_templates t where t.id = p_id for update;
  if not found then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  if p_expected_version is null or v_template.row_version <> p_expected_version then
    perform app_private.raise_api_error(409, 'version_conflict');
  end if;
  return v_template;
end
$$;

create function api.list_test_templates(p_include_archived boolean default false)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_account();
begin
  if v_actor.account_type <> 'admin' then
    perform app_private.raise_api_error(403, 'forbidden');
  end if;
  return coalesce((
    select jsonb_agg(app_private.test_template_dto(t)
             order by t.deleted_at nulls first, app_private.name_key(v.name), t.id)
      from app.test_templates t
      join app.test_template_versions v on v.id = t.current_version_id
     where coalesce(p_include_archived, false) or t.deleted_at is null
  ), '[]');
end
$$;

-- Every version of one template, newest first, including archived templates.
create function api.list_test_template_versions(p_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_account();
begin
  if v_actor.account_type <> 'admin' then
    perform app_private.raise_api_error(403, 'forbidden');
  end if;
  if not exists (select 1 from app.test_templates t where t.id = p_id) then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  return coalesce((
    select jsonb_agg(app_private.test_template_version_dto(v) order by v.revision desc)
      from app.test_template_versions v
     where v.template_id = p_id
  ), '[]');
end
$$;

create function api.create_test_template(p_name text, p_description text, p_config jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_admin();
  v_name text := app_private.clean_text(p_name, 200);
  v_description text := app_private.clean_optional_text(p_description, 5000);
  v_config jsonb := app_private.test_template_config(p_config);
  v_template app.test_templates;
begin
  insert into app.test_templates (current_version_id, created_by)
  values (gen_random_uuid(), v_actor.id)
  returning * into v_template;

  insert into app.test_template_versions
    (id, template_id, revision, name, description, config_schema_version, config, created_by)
  values (v_template.current_version_id, v_template.id, 1, v_name, v_description, 1, v_config,
          v_actor.id);

  perform app_private.record_change('test_template', v_template.id, v_template.row_version, null,
    app_private.test_template_snapshot(v_template), v_actor.id, 'test_template.create',
    jsonb_build_object('test_template_id', v_template.id,
                       'test_template_version_id', v_template.current_version_id));
  return app_private.test_template_dto(v_template);
end
$$;

-- Editing adds an immutable version; tests copied from older versions keep them
-- (TEST-02). Saving unchanged content returns the template as it is.
create function api.update_test_template(
  p_id uuid,
  p_name text,
  p_description text,
  p_config jsonb,
  p_expected_version bigint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_admin();
  v_name text := app_private.clean_text(p_name, 200);
  v_description text := app_private.clean_optional_text(p_description, 5000);
  v_config jsonb := app_private.test_template_config(p_config);
  v_before app.test_templates := app_private.lock_test_template(p_id, p_expected_version);
  v_current app.test_template_versions;
  v_version_id uuid := gen_random_uuid();
  v_after app.test_templates;
begin
  if v_before.deleted_at is not null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
  select * into v_current from app.test_template_versions v where v.id = v_before.current_version_id;
  if v_current.name = v_name
    and v_current.description is not distinct from v_description
    and v_current.config = v_config
  then
    return app_private.test_template_dto(v_before);
  end if;

  insert into app.test_template_versions
    (id, template_id, revision, name, description, config_schema_version, config, created_by)
  values (v_version_id, v_before.id, v_current.revision + 1, v_name, v_description, 1, v_config,
          v_actor.id);

  update app.test_templates t
     set current_version_id = v_version_id,
         row_version = t.row_version + 1,
         updated_at = now()
   where t.id = v_before.id
  returning * into v_after;

  perform app_private.record_change('test_template', v_after.id, v_after.row_version,
    app_private.test_template_snapshot(v_before), app_private.test_template_snapshot(v_after),
    v_actor.id, 'test_template.update',
    jsonb_build_object('test_template_id', v_after.id, 'test_template_version_id', v_version_id));
  return app_private.test_template_dto(v_after);
end
$$;

-- Archiving stops new use only; tests keep their copy and its source version.
create function api.archive_test_template(p_id uuid, p_reason text, p_expected_version bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_admin();
  v_reason text := app_private.normalize_reason(p_reason);
  v_before app.test_templates := app_private.lock_test_template(p_id, p_expected_version);
  v_after app.test_templates;
begin
  if v_before.deleted_at is not null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;

  update app.test_templates t
     set deleted_at = now(),
         deleted_by = v_actor.id,
         deleted_reason = v_reason,
         row_version = t.row_version + 1,
         updated_at = now()
   where t.id = v_before.id
  returning * into v_after;

  perform app_private.record_change('test_template', v_after.id, v_after.row_version,
    app_private.test_template_snapshot(v_before), app_private.test_template_snapshot(v_after),
    v_actor.id, 'test_template.archive', jsonb_build_object('test_template_id', v_after.id),
    v_reason);
  return app_private.test_template_dto(v_after);
end
$$;

-- Restoring reuses the identifier and every version; it creates no new version.
create function api.restore_test_template(p_id uuid, p_expected_version bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_admin();
  v_before app.test_templates := app_private.lock_test_template(p_id, p_expected_version);
  v_after app.test_templates;
begin
  if v_before.deleted_at is null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;

  update app.test_templates t
     set deleted_at = null,
         deleted_by = null,
         deleted_reason = null,
         row_version = t.row_version + 1,
         updated_at = now()
   where t.id = v_before.id
  returning * into v_after;

  perform app_private.record_change('test_template', v_after.id, v_after.row_version,
    app_private.test_template_snapshot(v_before), app_private.test_template_snapshot(v_after),
    v_actor.id, 'test_template.restore', jsonb_build_object('test_template_id', v_after.id));
  return app_private.test_template_dto(v_after);
end
$$;

grant execute on function api.list_test_templates(boolean) to authenticated;
grant execute on function api.list_test_template_versions(uuid) to authenticated;
grant execute on function api.create_test_template(text, text, jsonb) to authenticated;
grant execute on function api.update_test_template(uuid, text, text, jsonb, bigint) to authenticated;
grant execute on function api.archive_test_template(uuid, text, bigint) to authenticated;
grant execute on function api.restore_test_template(uuid, bigint) to authenticated;
