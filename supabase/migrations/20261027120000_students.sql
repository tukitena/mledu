-- GĐ 3: student master records (STU-04), soft delete (STU-01) and restore (STU-02).
--
-- Only the display name is required. Names and phone numbers are compared by
-- their lookup keys (app_private.name_key, app_private.phone_key); display
-- values keep what was entered. Duplicate checks cover active and archived
-- students and are serialized per name key, so concurrent requests cannot
-- create two students that the rules forbid.
--
-- Class records and participations arrive with the class enrollment feature;
-- the soft delete then also ends/cancels them in this same command (STU-01).

-------------------------------------------------------------------------------
-- Phone lookup key (STU-04).
-------------------------------------------------------------------------------

-- Drops spaces and . - ( ) separators; +84/0084 become 0 for Vietnamese
-- numbers. Accepts 0 + 9..10 digits (10 or 11 in total) or + and 8..15 digits.
-- Anything else is refused (400): letters are never turned into digits.
create function app_private.phone_key(p_value text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_value text := regexp_replace(coalesce(p_value, ''), '[\s.()-]', '', 'g');
begin
  if v_value like '+84%' then
    v_value := '0' || substr(v_value, 4);
  elsif v_value like '0084%' then
    v_value := '0' || substr(v_value, 5);
  end if;
  if v_value !~ '^(0[0-9]{9,10}|\+[0-9]{8,15})$' then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  return v_value;
end
$$;

comment on function app_private.phone_key(text) is
  'STU-04 phone key shared by internal search, Excel matching and parent lookup.';

-- Normalized, de-duplicated phone list in the given order; NULL means empty.
create function app_private.phone_keys(p_values text[])
returns text[]
language sql
immutable
set search_path = ''
as $$
  select coalesce(array_agg(k.phone order by k.first_position), '{}')
    from (
      select app_private.phone_key(v.value) as phone, min(v.position) as first_position
        from unnest(coalesce(p_values, '{}')) with ordinality as v (value, position)
       where btrim(coalesce(v.value, '')) <> ''
       group by 1
    ) k
$$;

-- A conflict that names the other record(s), e.g. [{"path":"student","message":"HS000012"}].
-- PostgREST returns DETAIL as `details`; the Worker passes it on as error details.
create function app_private.raise_api_conflict(p_code text, p_details jsonb)
returns void
language plpgsql
set search_path = ''
as $$
begin
  raise exception using errcode = 'PT409', message = p_code, detail = p_details::text;
end
$$;

-------------------------------------------------------------------------------
-- Tables.
-------------------------------------------------------------------------------

create sequence app.student_code_seq as bigint;

create table app.students (
  id uuid primary key default gen_random_uuid(),
  -- Stable student code (XLS-05): kept through export/import and restore.
  code text not null default 'HS' || lpad(nextval('app.student_code_seq')::text, 6, '0'),
  full_name text not null,
  name_key text not null,
  parent_name text,
  birth_date date,
  school text,
  general_note text,
  row_version bigint not null default 1,
  created_at timestamptz not null default now(),
  created_by uuid not null references app.account_profiles (id),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  deleted_by uuid references app.account_profiles (id),
  deleted_reason text,
  constraint students_code_key unique (code),
  constraint students_code_check check (code ~ '^HS[0-9]{6,}$'),
  constraint students_full_name_check check (
    full_name = btrim(full_name) and full_name is nfc normalized
    and char_length(full_name) between 1 and 200
  ),
  constraint students_name_key_check check (name_key = app_private.name_key(full_name)),
  constraint students_parent_name_check check (
    parent_name is null or (parent_name = btrim(parent_name) and parent_name is nfc normalized
                            and char_length(parent_name) between 1 and 200)
  ),
  constraint students_birth_date_check check (birth_date is null or birth_date >= date '1900-01-01'),
  constraint students_school_check check (
    school is null or (school is nfc normalized and char_length(school) between 1 and 200)
  ),
  constraint students_general_note_check check (
    general_note is null or (general_note is nfc normalized and char_length(general_note) between 1 and 1000)
  ),
  constraint students_row_version_check check (row_version >= 1),
  constraint students_deleted_check check (
    (deleted_at is null and deleted_by is null and deleted_reason is null)
    or (deleted_at is not null and deleted_by is not null
        and char_length(deleted_reason) between 1 and 1000)
  )
);

create index students_name_key_idx on app.students (name_key);

comment on table app.students is
  'Student master record (STU-04). Soft-deleted rows keep code, data and history.';

create table app.student_contacts (
  student_id uuid not null references app.students (id),
  kind text not null,
  phone text not null,
  position integer not null,
  -- Duplicates within one student and kind are removed, not stored twice.
  primary key (student_id, kind, phone),
  constraint student_contacts_kind_check check (kind in ('parent', 'student')),
  constraint student_contacts_phone_check check (phone ~ '^(0[0-9]{9,10}|\+[0-9]{8,15})$'),
  constraint student_contacts_position_check check (position >= 1)
);

create index student_contacts_phone_idx on app.student_contacts (phone, kind);

alter table app.students enable row level security;
alter table app.student_contacts enable row level security;
revoke all on table app.students, app.student_contacts from public, anon, authenticated;
revoke all on sequence app.student_code_seq from public, anon, authenticated;

-------------------------------------------------------------------------------
-- Snapshots and DTOs (packages/contracts/src/students.ts).
-------------------------------------------------------------------------------

create function app_private.student_phones(p_student_id uuid, p_kind text)
returns text[]
language sql
stable
set search_path = ''
as $$
  select coalesce(array_agg(c.phone order by c.position), '{}')
    from app.student_contacts c
   where c.student_id = p_student_id and c.kind = p_kind
$$;

create function app_private.student_snapshot(p_student app.students)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'code', p_student.code,
    'full_name', p_student.full_name,
    'parent_name', p_student.parent_name,
    'parent_phones', to_jsonb(app_private.student_phones(p_student.id, 'parent')),
    'student_phones', to_jsonb(app_private.student_phones(p_student.id, 'student')),
    'birth_date', p_student.birth_date,
    'school', p_student.school,
    'general_note', p_student.general_note,
    'deleted_at', p_student.deleted_at,
    'deleted_by', p_student.deleted_by,
    'deleted_reason', p_student.deleted_reason
  )
$$;

create function app_private.student_dto(p_student app.students)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_student.id,
    'code', p_student.code,
    'fullName', p_student.full_name,
    'parentName', p_student.parent_name,
    'parentPhones', to_jsonb(app_private.student_phones(p_student.id, 'parent')),
    'studentPhones', to_jsonb(app_private.student_phones(p_student.id, 'student')),
    'birthDate', p_student.birth_date,
    'school', p_student.school,
    'generalNote', p_student.general_note,
    'status', case when p_student.deleted_at is null then 'active' else 'deleted' end,
    'deletedAt', p_student.deleted_at,
    'deletedReason', p_student.deleted_reason,
    'createdAt', p_student.created_at,
    'rowVersion', p_student.row_version
  )
$$;

-------------------------------------------------------------------------------
-- Validation and duplicate rules (STU-04).
-------------------------------------------------------------------------------

-- Locks the name keys involved (sorted, so two renames cannot deadlock).
create function app_private.lock_student_name_keys(p_keys text[])
returns void
language sql
volatile
set search_path = ''
as $$
  select count(pg_advisory_xact_lock(hashtextextended('student_name:' || k.key, 0)))
    from (select distinct unnest(p_keys) as key order by 1) k
$$;

-- p_student_id is NULL for a new student. p_name_kept is true when an existing
-- student keeps its name key: a record created without parent phones while
-- its name was unique stays valid, but cannot drop parent phones it has once
-- another record shares the name.
create function app_private.assert_student_unique(
  p_student_id uuid,
  p_name_key text,
  p_parent_phones text[],
  p_name_kept boolean,
  p_had_parent_phones boolean
)
returns void
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_conflicts jsonb;
  v_archived boolean;
begin
  select jsonb_agg(jsonb_build_object('path', 'student', 'message', s.code) order by s.code),
         bool_and(s.deleted_at is not null)
    into v_conflicts, v_archived
    from app.students s
   where s.name_key = p_name_key
     and s.id is distinct from p_student_id
     and exists (
       select 1 from app.student_contacts c
        where c.student_id = s.id and c.kind = 'parent' and c.phone = any (p_parent_phones)
     );
  if v_conflicts is not null then
    -- Same name and a shared parent phone: the same child. An archived match is
    -- restored instead of duplicated (STU-04), never merged automatically.
    perform app_private.raise_api_conflict(
      case when v_archived then 'duplicate_student_archived' else 'duplicate_student' end,
      v_conflicts);
  end if;

  if cardinality(p_parent_phones) = 0
    and (not p_name_kept or p_had_parent_phones)
    and exists (select 1 from app.students s
                 where s.name_key = p_name_key and s.id is distinct from p_student_id)
  then
    perform app_private.raise_api_conflict('parent_phone_required', (
      select jsonb_agg(jsonb_build_object('path', 'student', 'message', s.code) order by s.code)
        from app.students s
       where s.name_key = p_name_key and s.id is distinct from p_student_id));
  end if;
end
$$;

create type app_private.student_input as (
  full_name text,
  parent_name text,
  parent_phones text[],
  student_phones text[],
  birth_date date,
  school text,
  general_note text
);

create function app_private.clean_student_input(
  p_full_name text,
  p_parent_name text,
  p_parent_phones text[],
  p_student_phones text[],
  p_birth_date date,
  p_school text,
  p_general_note text
)
returns app_private.student_input
language plpgsql
stable
set search_path = ''
as $$
declare
  v_input app_private.student_input;
begin
  if cardinality(coalesce(p_parent_phones, '{}')) > 10
    or cardinality(coalesce(p_student_phones, '{}')) > 10
  then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  v_input.full_name := app_private.clean_text(p_full_name, 200);
  v_input.parent_name := app_private.clean_optional_text(p_parent_name, 200);
  v_input.parent_phones := app_private.phone_keys(p_parent_phones);
  v_input.student_phones := app_private.phone_keys(p_student_phones);
  v_input.birth_date := app_private.check_birth_date(p_birth_date);
  v_input.school := app_private.clean_optional_text(p_school, 200);
  v_input.general_note := app_private.clean_optional_text(p_general_note, 1000);
  return v_input;
end
$$;

create function app_private.replace_student_contacts(p_student_id uuid, p_kind text, p_phones text[])
returns void
language sql
volatile
set search_path = ''
as $$
  delete from app.student_contacts c where c.student_id = p_student_id and c.kind = p_kind;
  insert into app.student_contacts (student_id, kind, phone, position)
  select p_student_id, p_kind, p.phone, p.position
    from unnest(p_phones) with ordinality as p (phone, position);
$$;

create function app_private.lock_student(p_id uuid, p_expected_version bigint)
returns app.students
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_student app.students;
begin
  select * into v_student from app.students s where s.id = p_id for update;
  if not found then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  if p_expected_version is null or v_student.row_version <> p_expected_version then
    perform app_private.raise_api_error(409, 'version_conflict');
  end if;
  return v_student;
end
$$;

-- Applies an edit (also used by restore) after the duplicate checks.
create function app_private.apply_student_edit(
  p_before app.students,
  p_input app_private.student_input,
  p_restore boolean
)
returns app.students
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_name_key text := app_private.name_key(p_input.full_name);
  v_old_parent text[] := app_private.student_phones(p_before.id, 'parent');
  v_after app.students;
begin
  perform app_private.lock_student_name_keys(array[p_before.name_key, v_name_key]);
  perform app_private.assert_student_unique(p_before.id, v_name_key, p_input.parent_phones,
    v_name_key = p_before.name_key, cardinality(v_old_parent) > 0);

  update app.students s
     set full_name = p_input.full_name,
         name_key = v_name_key,
         parent_name = p_input.parent_name,
         birth_date = p_input.birth_date,
         school = p_input.school,
         general_note = p_input.general_note,
         deleted_at = case when p_restore then null else s.deleted_at end,
         deleted_by = case when p_restore then null else s.deleted_by end,
         deleted_reason = case when p_restore then null else s.deleted_reason end,
         row_version = s.row_version + 1,
         updated_at = now()
   where s.id = p_before.id
  returning * into v_after;

  perform app_private.replace_student_contacts(v_after.id, 'parent', p_input.parent_phones);
  perform app_private.replace_student_contacts(v_after.id, 'student', p_input.student_phones);
  return v_after;
end
$$;

-------------------------------------------------------------------------------
-- Queries. Every internal account searches the whole centre (STU-04);
-- archived students are listed for Admin/Receptionist only.
-------------------------------------------------------------------------------

create function api.list_students(
  p_search text default null,
  p_status text default 'active',
  p_limit integer default 20,
  p_offset integer default 0
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_account();
  v_status text := coalesce(p_status, 'active');
  v_search text := nullif(btrim(coalesce(p_search, '')), '');
  v_key text := app_private.name_key(coalesce(v_search, ''));
  v_digits text;
  v_result jsonb;
begin
  if v_status not in ('active', 'deleted') or p_limit not between 1 and 100 or p_offset < 0
    or char_length(coalesce(v_search, '')) > 200
  then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  if v_status = 'deleted' and v_actor.account_type not in ('admin', 'receptionist') then
    perform app_private.raise_api_error(403, 'forbidden');
  end if;
  -- A search made of digits and phone separators also matches phone keys.
  if v_search ~ '^\+?[0-9\s.()-]{3,}$' then
    v_digits := regexp_replace(v_search, '[\s.()-]', '', 'g');
    v_digits := case
      when v_digits like '+84%' then '0' || substr(v_digits, 4)
      when v_digits like '0084%' then '0' || substr(v_digits, 5)
      else v_digits end;
  end if;

  with matching as (
    select s
      from app.students s
     where (v_status = 'active') = (s.deleted_at is null)
       and (v_search is null
            or strpos(s.name_key, v_key) > 0
            or upper(s.code) = upper(v_search)
            or (v_digits is not null and exists (
                  select 1 from app.student_contacts c
                   where c.student_id = s.id and strpos(c.phone, v_digits) > 0)))
  )
  select jsonb_build_object(
    'total', (select count(*) from matching),
    'items', coalesce((
      select jsonb_agg(app_private.student_dto(p.s) order by (p.s).name_key, (p.s).code)
        from (select m.s from matching m order by (m.s).name_key, (m.s).code
              limit p_limit offset p_offset) p
    ), '[]')
  ) into v_result;
  return v_result;
end
$$;

create function api.get_student(p_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_account();
  v_student app.students;
begin
  select * into v_student from app.students s where s.id = p_id;
  if not found
    or (v_student.deleted_at is not null and v_actor.account_type not in ('admin', 'receptionist'))
  then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  return app_private.student_dto(v_student);
end
$$;

-------------------------------------------------------------------------------
-- Commands (Admin/Receptionist).
-------------------------------------------------------------------------------

create function api.create_student(
  p_full_name text,
  p_parent_name text default null,
  p_parent_phones text[] default '{}',
  p_student_phones text[] default '{}',
  p_birth_date date default null,
  p_school text default null,
  p_general_note text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_manager();
  v_input app_private.student_input := app_private.clean_student_input(p_full_name, p_parent_name,
    p_parent_phones, p_student_phones, p_birth_date, p_school, p_general_note);
  v_name_key text := app_private.name_key(v_input.full_name);
  v_student app.students;
begin
  perform app_private.lock_student_name_keys(array[v_name_key]);
  perform app_private.assert_student_unique(null, v_name_key, v_input.parent_phones, false, false);

  insert into app.students (full_name, name_key, parent_name, birth_date, school, general_note, created_by)
  values (v_input.full_name, v_name_key, v_input.parent_name, v_input.birth_date, v_input.school,
          v_input.general_note, v_actor.id)
  returning * into v_student;
  perform app_private.replace_student_contacts(v_student.id, 'parent', v_input.parent_phones);
  perform app_private.replace_student_contacts(v_student.id, 'student', v_input.student_phones);

  perform app_private.record_change('student', v_student.id, v_student.row_version, null,
    app_private.student_snapshot(v_student), v_actor.id, 'student.create',
    jsonb_build_object('student_id', v_student.id));
  return app_private.student_dto(v_student);
end
$$;

create function api.update_student(
  p_id uuid,
  p_full_name text,
  p_parent_name text,
  p_parent_phones text[],
  p_student_phones text[],
  p_birth_date date,
  p_school text,
  p_general_note text,
  p_expected_version bigint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_manager();
  v_input app_private.student_input := app_private.clean_student_input(p_full_name, p_parent_name,
    p_parent_phones, p_student_phones, p_birth_date, p_school, p_general_note);
  v_before app.students := app_private.lock_student(p_id, p_expected_version);
  v_before_snapshot jsonb := app_private.student_snapshot(v_before);
  v_after app.students;
begin
  if v_before.deleted_at is not null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
  v_after := app_private.apply_student_edit(v_before, v_input, false);
  if app_private.student_snapshot(v_after) = v_before_snapshot then
    -- Nothing changed: no new version and no audit (AUD-01).
    raise exception using errcode = 'P0004', message = 'no_change';
  end if;

  perform app_private.record_change('student', v_after.id, v_after.row_version, v_before_snapshot,
    app_private.student_snapshot(v_after), v_actor.id, 'student.update',
    jsonb_build_object('student_id', v_after.id));
  return app_private.student_dto(v_after);
exception
  when sqlstate 'P0004' then
    return app_private.student_dto(v_before);
end
$$;

-- STU-01: the record, its code, contacts and history are kept. Ending current
-- participations and cancelling future enrollments of the student is added to
-- this command together with class enrollment (same transaction and audit).
create function api.soft_delete_student(p_id uuid, p_reason text, p_expected_version bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_manager();
  v_reason text := app_private.normalize_reason(p_reason);
  v_before app.students := app_private.lock_student(p_id, p_expected_version);
  v_after app.students;
begin
  if v_before.deleted_at is not null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;

  update app.students s
     set deleted_at = now(),
         deleted_by = v_actor.id,
         deleted_reason = v_reason,
         row_version = s.row_version + 1,
         updated_at = now()
   where s.id = v_before.id
  returning * into v_after;

  perform app_private.record_change('student', v_after.id, v_after.row_version,
    app_private.student_snapshot(v_before), app_private.student_snapshot(v_after), v_actor.id,
    'student.soft_delete', jsonb_build_object('student_id', v_after.id), v_reason);
  return app_private.student_dto(v_after);
end
$$;

-- STU-02: keeps the code and history; conflicting data is corrected in the
-- same command (the caller sends the full, possibly edited, record). Class
-- records and participations are not reopened.
create function api.restore_student(
  p_id uuid,
  p_full_name text,
  p_parent_name text,
  p_parent_phones text[],
  p_student_phones text[],
  p_birth_date date,
  p_school text,
  p_general_note text,
  p_expected_version bigint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_manager();
  v_input app_private.student_input := app_private.clean_student_input(p_full_name, p_parent_name,
    p_parent_phones, p_student_phones, p_birth_date, p_school, p_general_note);
  v_before app.students := app_private.lock_student(p_id, p_expected_version);
  v_before_snapshot jsonb := app_private.student_snapshot(v_before);
  v_after app.students;
begin
  if v_before.deleted_at is null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
  v_after := app_private.apply_student_edit(v_before, v_input, true);

  perform app_private.record_change('student', v_after.id, v_after.row_version, v_before_snapshot,
    app_private.student_snapshot(v_after), v_actor.id, 'student.restore',
    jsonb_build_object('student_id', v_after.id));
  return app_private.student_dto(v_after);
end
$$;

grant execute on function api.list_students(text, text, integer, integer) to authenticated;
grant execute on function api.get_student(uuid) to authenticated;
grant execute on function api.create_student(text, text, text[], text[], date, text, text) to authenticated;
grant execute on function api.update_student(uuid, text, text, text[], text[], date, text, text, bigint)
  to authenticated;
grant execute on function api.soft_delete_student(uuid, text, bigint) to authenticated;
grant execute on function api.restore_student(uuid, text, text, text[], text[], date, text, text, bigint)
  to authenticated;
