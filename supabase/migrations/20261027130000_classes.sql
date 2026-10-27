-- GĐ 3: classes (CLASS-03) and dated teacher/assistant assignments
-- (CLASS-01/02), with the assignment checks of AUTH-04/07.
--
-- Business dates are Asia/Ho_Chi_Minh calendar days: a start date takes effect
-- at 00:00 and an end date lasts until the end of that day. Early ends and
-- cancellations are separate instants, so an interval ends at the earliest of
-- its end date and its end event and never comes back when dates move later.
--
-- Closing/reopening/deleting/restoring classes (CLASS-05) needs enrollments,
-- schedules and fees; the state columns are here, the commands come with the
-- features that own those effects.

create extension if not exists btree_gist with schema extensions;

-------------------------------------------------------------------------------
-- Time helpers (A.3).
-------------------------------------------------------------------------------

-- Instant at which a business date starts (00:00 in Asia/Ho_Chi_Minh).
create function app_private.day_start(p_day date)
returns timestamptz
language sql
immutable
parallel safe
set search_path = ''
as $$
  select (p_day::timestamp at time zone 'Asia/Ho_Chi_Minh')
$$;

-- [first day 00:00, min(day after last day 00:00, end event)); empty when the
-- end event happened before the start (a cancelled future interval).
create function app_private.dated_period(p_first_day date, p_last_day date, p_ended_at timestamptz)
returns tstzrange
language sql
immutable
parallel safe
set search_path = ''
as $$
  select case
    when least(app_private.day_start(p_last_day + 1), coalesce(p_ended_at, 'infinity'))
         <= app_private.day_start(p_first_day)
      then 'empty'::tstzrange
    else tstzrange(app_private.day_start(p_first_day),
                   least(app_private.day_start(p_last_day + 1), coalesce(p_ended_at, 'infinity')),
                   '[)')
  end
$$;

-------------------------------------------------------------------------------
-- Classes (CLASS-03).
-------------------------------------------------------------------------------

create table app.classes (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  name_key text not null,
  -- One subject and one grade; archived catalog entries stay referenced (CAT-01).
  subject_id uuid not null references app.catalog_entries (id),
  grade_id uuid not null references app.catalog_entries (id),
  start_date date not null,
  end_date date not null,
  note text,
  -- CLASS-05 administrative state; new classes are open.
  admin_state text not null default 'open',
  closed_at timestamptz,
  row_version bigint not null default 1,
  created_at timestamptz not null default now(),
  created_by uuid not null references app.account_profiles (id),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  deleted_by uuid references app.account_profiles (id),
  deleted_reason text,
  constraint classes_name_check check (
    name = btrim(name) and name is nfc normalized and char_length(name) between 1 and 200
  ),
  constraint classes_name_key_check check (name_key = app_private.name_key(name)),
  constraint classes_dates_check check (end_date >= start_date),
  constraint classes_note_check check (
    note is null or (note is nfc normalized and char_length(note) between 1 and 1000)
  ),
  constraint classes_admin_state_check check (
    (admin_state = 'open' and closed_at is null) or (admin_state = 'closed' and closed_at is not null)
  ),
  constraint classes_row_version_check check (row_version >= 1),
  constraint classes_deleted_check check (
    (deleted_at is null and deleted_by is null and deleted_reason is null)
    or (deleted_at is not null and deleted_by is not null
        and char_length(deleted_reason) between 1 and 1000)
  )
);

create index classes_name_key_idx on app.classes (name_key);

comment on table app.classes is
  'Class (CLASS-03): one subject, one grade, opening/closing dates; many staff and schedules.';

-------------------------------------------------------------------------------
-- Assignments (CLASS-01/02).
-------------------------------------------------------------------------------

create table app.class_assignments (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references app.classes (id),
  account_id uuid not null references app.account_profiles (id),
  role text not null,
  start_date date not null,
  end_date date not null,
  -- Optional teaching speciality; never tied to the class subject (CLASS-03).
  subject_note text,
  -- End event: ended early (in effect) or cancelled (not started yet).
  ended_at timestamptz,
  end_kind text,
  end_reason text,
  ended_by uuid references app.account_profiles (id),
  -- Interval in which the assignment grants class rights; maintained by the
  -- commands from the dates and the end event.
  effective_period tstzrange not null,
  row_version bigint not null default 1,
  created_at timestamptz not null default now(),
  created_by uuid not null references app.account_profiles (id),
  updated_at timestamptz not null default now(),
  constraint class_assignments_role_check check (role in ('teacher', 'assistant')),
  constraint class_assignments_dates_check check (end_date >= start_date),
  constraint class_assignments_subject_note_check check (
    subject_note is null
    or (subject_note is nfc normalized and char_length(subject_note) between 1 and 200)
  ),
  constraint class_assignments_end_check check (
    (ended_at is null and end_kind is null and end_reason is null and ended_by is null)
    or (ended_at is not null
        and end_kind in ('ended_early', 'cancelled', 'cancelled_account_deleted',
                         'cancelled_account_type')
        and (end_reason is null or char_length(end_reason) between 1 and 1000))
  ),
  constraint class_assignments_period_check check (
    effective_period = app_private.dated_period(start_date, end_date, ended_at)
  ),
  constraint class_assignments_row_version_check check (row_version >= 1),
  -- One role per person and class at any time; covers teacher/assistant and
  -- same-role overlaps, using the end event (CLASS-01/02).
  constraint class_assignments_no_overlap
    exclude using gist (class_id with =, account_id with =, effective_period with &&)
);

create index class_assignments_account_idx on app.class_assignments (account_id);

comment on table app.class_assignments is
  'Teacher/assistant assignment (CLASS-01/02). Rights follow effective_period at request time.';

alter table app.classes enable row level security;
alter table app.class_assignments enable row level security;
revoke all on table app.classes, app.class_assignments from public, anon, authenticated;

-------------------------------------------------------------------------------
-- Class rights at request time.
-------------------------------------------------------------------------------

-- Role of an account in a class right now: an assignment in effect, in a class
-- that is not soft-deleted (CLASS-01, CLASS-05). NULL otherwise.
create function app_private.class_role(p_account_id uuid, p_class_id uuid)
returns text
language sql
stable
set search_path = ''
as $$
  select a.role
    from app.class_assignments a
    join app.classes c on c.id = a.class_id
   where a.account_id = p_account_id
     and a.class_id = p_class_id
     and c.deleted_at is null
     and a.effective_period @> now()
   limit 1
$$;

-- Caller may read the class: Admin/Receptionist always (deleted classes too),
-- a User through an assignment in effect.
create function app_private.require_class_reader(p_class_id uuid)
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
  if v_actor.account_type not in ('admin', 'receptionist')
    and app_private.class_role(v_actor.id, p_class_id) is null
  then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  return v_actor;
end
$$;

-------------------------------------------------------------------------------
-- Snapshots and DTOs (packages/contracts/src/classes.ts).
-------------------------------------------------------------------------------

create function app_private.class_snapshot(p_class app.classes)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'name', p_class.name,
    'subject_id', p_class.subject_id,
    'grade_id', p_class.grade_id,
    'start_date', p_class.start_date,
    'end_date', p_class.end_date,
    'note', p_class.note,
    'admin_state', p_class.admin_state,
    'closed_at', p_class.closed_at,
    'deleted_at', p_class.deleted_at,
    'deleted_by', p_class.deleted_by,
    'deleted_reason', p_class.deleted_reason
  )
$$;

create function app_private.catalog_ref(p_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object('id', e.id, 'name', e.name, 'archived', e.deleted_at is not null)
    from app.catalog_entries e
   where e.id = p_id
$$;

create function app_private.class_dto(p_class app.classes)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_class.id,
    'name', p_class.name,
    'subject', app_private.catalog_ref(p_class.subject_id),
    'grade', app_private.catalog_ref(p_class.grade_id),
    'startDate', p_class.start_date,
    'endDate', p_class.end_date,
    'note', p_class.note,
    'adminState', p_class.admin_state,
    'period', case
      when app_private.business_date(now()) < p_class.start_date then 'upcoming'
      when app_private.business_date(now()) > p_class.end_date then 'ended'
      else 'running' end,
    'deleted', p_class.deleted_at is not null,
    'deletedAt', p_class.deleted_at,
    'deletedReason', p_class.deleted_reason,
    -- Staff whose assignment is in effect now.
    'currentStaff', coalesce((
      select jsonb_agg(jsonb_build_object('accountId', p.id, 'fullName', p.full_name, 'role', a.role)
                       order by a.role desc, p.full_name)
        from app.class_assignments a
        join app.account_profiles p on p.id = a.account_id
       where a.class_id = p_class.id and a.effective_period @> now()
    ), '[]'),
    'rowVersion', p_class.row_version
  )
$$;

create function app_private.assignment_snapshot(p_assignment app.class_assignments)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'class_id', p_assignment.class_id,
    'account_id', p_assignment.account_id,
    'role', p_assignment.role,
    'start_date', p_assignment.start_date,
    'end_date', p_assignment.end_date,
    'subject_note', p_assignment.subject_note,
    'ended_at', p_assignment.ended_at,
    'end_kind', p_assignment.end_kind,
    'end_reason', p_assignment.end_reason,
    'ended_by', p_assignment.ended_by
  )
$$;

-- not_started / active / expired (end date passed) / ended (end event) / cancelled.
create function app_private.assignment_status(p_assignment app.class_assignments)
returns text
language sql
stable
set search_path = ''
as $$
  select case
    when p_assignment.end_kind like 'cancelled%' then 'cancelled'
    when p_assignment.ended_at is not null and not (p_assignment.effective_period @> now()) then 'ended'
    when p_assignment.effective_period @> now() then 'active'
    when now() < app_private.day_start(p_assignment.start_date) then 'not_started'
    else 'expired'
  end
$$;

create function app_private.assignment_dto(p_assignment app.class_assignments)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_assignment.id,
    'classId', p_assignment.class_id,
    'accountId', p_assignment.account_id,
    'fullName', p.full_name,
    'email', p.login_email_key,
    'role', p_assignment.role,
    'startDate', p_assignment.start_date,
    'endDate', p_assignment.end_date,
    'subjectNote', p_assignment.subject_note,
    'status', app_private.assignment_status(p_assignment),
    'endedAt', p_assignment.ended_at,
    'endKind', p_assignment.end_kind,
    'endReason', p_assignment.end_reason,
    'rowVersion', p_assignment.row_version
  )
    from app.account_profiles p
   where p.id = p_assignment.account_id
$$;

-------------------------------------------------------------------------------
-- Class queries and commands.
-------------------------------------------------------------------------------

-- Admin/Receptionist list every class (deleted ones with p_deleted); a User
-- lists the classes it currently teaches or assists.
create function api.list_classes(
  p_search text default null,
  p_deleted boolean default false,
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
  v_manager boolean := v_actor.account_type in ('admin', 'receptionist');
  v_key text := app_private.name_key(coalesce(p_search, ''));
  v_result jsonb;
begin
  if p_limit not between 1 and 100 or p_offset < 0 or char_length(coalesce(p_search, '')) > 200 then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  if coalesce(p_deleted, false) and not v_manager then
    perform app_private.raise_api_error(403, 'forbidden');
  end if;

  with matching as (
    select c
      from app.classes c
     where (c.deleted_at is not null) = coalesce(p_deleted, false)
       and (v_key = '' or strpos(c.name_key, v_key) > 0)
       and (v_manager or app_private.class_role(v_actor.id, c.id) is not null)
  )
  select jsonb_build_object(
    'total', (select count(*) from matching),
    'items', coalesce((
      select jsonb_agg(app_private.class_dto(p.c) order by (p.c).start_date desc, (p.c).name_key, (p.c).id)
        from (select m.c from matching m order by (m.c).start_date desc, (m.c).name_key, (m.c).id
              limit p_limit offset p_offset) p
    ), '[]')
  ) into v_result;
  return v_result;
end
$$;

create function api.get_class(p_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_class_reader(p_id);
  v_class app.classes;
begin
  select * into v_class from app.classes c where c.id = p_id;
  return app_private.class_dto(v_class) || jsonb_build_object(
    'myRole', app_private.class_role(v_actor.id, p_id));
end
$$;

-- New and changed references must be active entries of the right kind; an
-- unchanged archived reference stays on the class (CAT-01).
create function app_private.check_class_catalog(p_id uuid, p_kind text, p_current uuid)
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  if p_id is distinct from p_current and not exists (
    select 1 from app.catalog_entries e where e.id = p_id and e.kind = p_kind and e.deleted_at is null
  ) then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
end
$$;

-- CLASS-03: a class "has activity" once it started or has participation
-- history (or, from GĐ 4, a session that started). Its opening date is then
-- locked and its end date may only move to today or later. The enrollment
-- feature extends this check with participations.
create function app_private.class_has_activity(p_class app.classes)
returns boolean
language sql
stable
set search_path = ''
as $$
  select app_private.business_date(now()) >= p_class.start_date
$$;

-- Applies the effects of a date change inside the same command. Enrollment
-- adds: every stored join date stays covered, and open participations follow
-- the new end date (ended ones keep theirs). GĐ 4 adds sessions outside the
-- new range.
create function app_private.apply_class_date_change(p_before app.classes, p_after app.classes)
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  return;
end
$$;

create function api.create_class(
  p_name text,
  p_subject_id uuid,
  p_grade_id uuid,
  p_start_date date,
  p_end_date date,
  p_note text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_manager();
  v_name text := app_private.clean_text(p_name, 200);
  v_note text := app_private.clean_optional_text(p_note, 1000);
  v_class app.classes;
begin
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  perform app_private.check_class_catalog(p_subject_id, 'subject', null);
  perform app_private.check_class_catalog(p_grade_id, 'grade', null);

  insert into app.classes (name, name_key, subject_id, grade_id, start_date, end_date, note, created_by)
  values (v_name, app_private.name_key(v_name), p_subject_id, p_grade_id, p_start_date, p_end_date,
          v_note, v_actor.id)
  returning * into v_class;

  perform app_private.record_change('class', v_class.id, v_class.row_version, null,
    app_private.class_snapshot(v_class), v_actor.id, 'class.create',
    jsonb_build_object('class_id', v_class.id));
  return app_private.class_dto(v_class);
end
$$;

create function app_private.lock_class(p_id uuid, p_expected_version bigint)
returns app.classes
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_class app.classes;
begin
  select * into v_class from app.classes c where c.id = p_id for update;
  if not found then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  if p_expected_version is not null and v_class.row_version <> p_expected_version then
    perform app_private.raise_api_error(409, 'version_conflict');
  end if;
  return v_class;
end
$$;

create function api.update_class(
  p_id uuid,
  p_name text,
  p_subject_id uuid,
  p_grade_id uuid,
  p_start_date date,
  p_end_date date,
  p_note text,
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
  v_name text := app_private.clean_text(p_name, 200);
  v_note text := app_private.clean_optional_text(p_note, 1000);
  v_before app.classes;
  v_after app.classes;
  v_today date := app_private.business_date(now());
begin
  if p_expected_version is null or p_start_date is null or p_end_date is null
    or p_end_date < p_start_date
  then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  v_before := app_private.lock_class(p_id, p_expected_version);
  if v_before.deleted_at is not null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
  perform app_private.check_class_catalog(p_subject_id, 'subject', v_before.subject_id);
  perform app_private.check_class_catalog(p_grade_id, 'grade', v_before.grade_id);

  -- CLASS-03: after activity the opening date is locked and the end date is
  -- never moved into the past (no retroactive cut of history).
  if app_private.class_has_activity(v_before)
    and (p_start_date <> v_before.start_date
         or (p_end_date <> v_before.end_date and p_end_date < v_today))
  then
    perform app_private.raise_api_error(409, 'class_dates_locked');
  end if;

  update app.classes c
     set name = v_name,
         name_key = app_private.name_key(v_name),
         subject_id = p_subject_id,
         grade_id = p_grade_id,
         start_date = p_start_date,
         end_date = p_end_date,
         note = v_note,
         row_version = c.row_version + 1,
         updated_at = now()
   where c.id = v_before.id
  returning * into v_after;

  if app_private.class_snapshot(v_after) = app_private.class_snapshot(v_before) then
    raise exception using errcode = 'P0004', message = 'no_change';
  end if;
  if (v_after.start_date, v_after.end_date) is distinct from (v_before.start_date, v_before.end_date) then
    perform app_private.apply_class_date_change(v_before, v_after);
  end if;

  perform app_private.record_change('class', v_after.id, v_after.row_version,
    app_private.class_snapshot(v_before), app_private.class_snapshot(v_after), v_actor.id,
    'class.update', jsonb_build_object('class_id', v_after.id));
  return app_private.class_dto(v_after);
exception
  when sqlstate 'P0004' then
    return app_private.class_dto(v_before);
end
$$;

-------------------------------------------------------------------------------
-- Assignment queries and commands (Admin/Receptionist).
-------------------------------------------------------------------------------

create function api.list_class_assignments(p_class_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  perform app_private.require_class_reader(p_class_id);
  return coalesce((
    select jsonb_agg(app_private.assignment_dto(a) order by a.start_date desc, a.created_at desc)
      from app.class_assignments a
     where a.class_id = p_class_id
  ), '[]');
end
$$;

-- Accounts that may be assigned: User or Admin, enabled and not deleted (CLASS-01).
create function api.list_assignable_accounts()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  perform app_private.require_manager();
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', p.id, 'fullName', p.full_name, 'email', p.login_email_key,
                                        'accountType', p.account_type)
                     order by p.full_name, p.id)
      from app.account_profiles p
     where p.account_type in ('user', 'admin') and p.is_enabled and p.deleted_at is null
  ), '[]');
end
$$;

-- Stores an assignment row; an overlap with another assignment of the same
-- person in the class is reported as assignment_overlap (CLASS-01/02).
create function app_private.write_assignment(p_assignment app.class_assignments, p_insert boolean)
returns app.class_assignments
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_row app.class_assignments;
begin
  if p_insert then
    insert into app.class_assignments
      (class_id, account_id, role, start_date, end_date, subject_note, effective_period, created_by)
    values (p_assignment.class_id, p_assignment.account_id, p_assignment.role, p_assignment.start_date,
            p_assignment.end_date, p_assignment.subject_note,
            app_private.dated_period(p_assignment.start_date, p_assignment.end_date, null),
            p_assignment.created_by)
    returning * into v_row;
  else
    update app.class_assignments a
       set role = p_assignment.role,
           start_date = p_assignment.start_date,
           end_date = p_assignment.end_date,
           subject_note = p_assignment.subject_note,
           ended_at = p_assignment.ended_at,
           end_kind = p_assignment.end_kind,
           end_reason = p_assignment.end_reason,
           ended_by = p_assignment.ended_by,
           effective_period = app_private.dated_period(p_assignment.start_date, p_assignment.end_date,
                                                       p_assignment.ended_at),
           row_version = a.row_version + 1,
           updated_at = now()
     where a.id = p_assignment.id
    returning * into v_row;
  end if;
  return v_row;
exception
  when exclusion_violation then
    perform app_private.raise_api_error(409, 'assignment_overlap');
    return null;
end
$$;

create function app_private.lock_assignment(p_id uuid, p_expected_version bigint)
returns app.class_assignments
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_assignment app.class_assignments;
begin
  select * into v_assignment from app.class_assignments a where a.id = p_id for update;
  if not found then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  if p_expected_version is null or v_assignment.row_version <> p_expected_version then
    perform app_private.raise_api_error(409, 'version_conflict');
  end if;
  return v_assignment;
end
$$;

create function api.create_class_assignment(
  p_class_id uuid,
  p_account_id uuid,
  p_role text,
  p_start_date date,
  p_end_date date,
  p_subject_note text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_manager();
  v_class app.classes;
  v_account app.account_profiles;
  v_row app.class_assignments;
begin
  if p_role is null or p_role not in ('teacher', 'assistant')
    or p_start_date is null or p_end_date is null or p_end_date < p_start_date
  then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  -- Shared lock: the class dates cannot change while the assignment is checked.
  select * into v_class from app.classes c where c.id = p_class_id for share;
  if not found then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  if v_class.deleted_at is not null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
  if p_start_date < v_class.start_date or p_end_date > v_class.end_date then
    perform app_private.raise_api_error(409, 'outside_class_dates');
  end if;
  -- The account row is locked so a concurrent delete/type change waits (AUTH-04/07).
  select * into v_account from app.account_profiles p where p.id = p_account_id for share;
  if not found or v_account.account_type not in ('user', 'admin') or not v_account.is_enabled
    or v_account.deleted_at is not null
  then
    perform app_private.raise_api_error(409, 'account_not_assignable');
  end if;

  v_row.class_id := v_class.id;
  v_row.account_id := v_account.id;
  v_row.role := p_role;
  v_row.start_date := p_start_date;
  v_row.end_date := p_end_date;
  v_row.subject_note := app_private.clean_optional_text(p_subject_note, 200);
  v_row.created_by := v_actor.id;
  v_row := app_private.write_assignment(v_row, true);

  perform app_private.record_change('class_assignment', v_row.id, v_row.row_version, null,
    app_private.assignment_snapshot(v_row), v_actor.id, 'class.assignment.create',
    jsonb_build_object('class_id', v_row.class_id, 'account_id', v_row.account_id,
                       'assignment_id', v_row.id));
  return app_private.assignment_dto(v_row);
end
$$;

-- CLASS-01: before it starts everything may change (within the class dates).
-- Once started, role and start date are history; the end date may move to
-- today or later. Ended, cancelled or expired assignments never revive.
create function api.update_class_assignment(
  p_id uuid,
  p_role text,
  p_start_date date,
  p_end_date date,
  p_subject_note text,
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
  v_before app.class_assignments := app_private.lock_assignment(p_id, p_expected_version);
  v_status text := app_private.assignment_status(v_before);
  v_class app.classes;
  v_row app.class_assignments := v_before;
begin
  if p_role is null or p_role not in ('teacher', 'assistant')
    or p_start_date is null or p_end_date is null or p_end_date < p_start_date
  then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  select * into v_class from app.classes c where c.id = v_before.class_id for share;
  if v_class.deleted_at is not null or v_status not in ('not_started', 'active') then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
  if v_status = 'active'
    and (p_role <> v_before.role or p_start_date <> v_before.start_date
         or (p_end_date <> v_before.end_date and p_end_date < app_private.business_date(now())))
  then
    perform app_private.raise_api_error(409, 'assignment_locked');
  end if;
  if (p_start_date <> v_before.start_date and p_start_date < v_class.start_date)
    or (p_end_date <> v_before.end_date and p_end_date > v_class.end_date)
  then
    perform app_private.raise_api_error(409, 'outside_class_dates');
  end if;

  v_row.role := p_role;
  v_row.start_date := p_start_date;
  v_row.end_date := p_end_date;
  v_row.subject_note := app_private.clean_optional_text(p_subject_note, 200);
  if app_private.assignment_snapshot(v_row) = app_private.assignment_snapshot(v_before) then
    return app_private.assignment_dto(v_before);
  end if;
  v_row := app_private.write_assignment(v_row, false);

  perform app_private.record_change('class_assignment', v_row.id, v_row.row_version,
    app_private.assignment_snapshot(v_before), app_private.assignment_snapshot(v_row), v_actor.id,
    'class.assignment.update', jsonb_build_object('class_id', v_row.class_id,
      'account_id', v_row.account_id, 'assignment_id', v_row.id));
  return app_private.assignment_dto(v_row);
end
$$;

-- CLASS-01: an assignment in effect ends now; one not started yet is
-- cancelled. History and academic data stay; other staff are untouched.
create function api.end_class_assignment(p_id uuid, p_reason text, p_expected_version bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_manager();
  v_reason text := app_private.normalize_reason(p_reason);
  v_before app.class_assignments := app_private.lock_assignment(p_id, p_expected_version);
  v_status text := app_private.assignment_status(v_before);
  v_row app.class_assignments := v_before;
begin
  if v_status not in ('not_started', 'active') then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;

  v_row.ended_at := now();
  v_row.end_kind := case when v_status = 'active' then 'ended_early' else 'cancelled' end;
  v_row.end_reason := v_reason;
  v_row.ended_by := v_actor.id;
  v_row := app_private.write_assignment(v_row, false);

  perform app_private.record_change('class_assignment', v_row.id, v_row.row_version,
    app_private.assignment_snapshot(v_before), app_private.assignment_snapshot(v_row), v_actor.id,
    case when v_status = 'active' then 'class.assignment.end' else 'class.assignment.cancel' end,
    jsonb_build_object('class_id', v_row.class_id, 'account_id', v_row.account_id,
                       'assignment_id', v_row.id), v_reason);
  return app_private.assignment_dto(v_row);
end
$$;

-------------------------------------------------------------------------------
-- AUTH-04/07: account deletion and User -> Receptionist depend on assignments.
-------------------------------------------------------------------------------

-- Refuses while an assignment of the account is in effect in a class that is
-- not deleted (the conflict lists those classes). Otherwise cancels future
-- assignments in the caller's transaction and returns their ids. A refusal
-- changes nothing.
create function app_private.settle_assignments_for_account(
  p_account_id uuid,
  p_actor_id uuid,
  p_end_kind text
)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_in_effect jsonb;
  v_before app.class_assignments;
  v_row app.class_assignments;
  v_cancelled jsonb := '[]';
begin
  select jsonb_agg(jsonb_build_object('path', 'class', 'message', c.name) order by c.name_key)
    into v_in_effect
    from app.class_assignments a
    join app.classes c on c.id = a.class_id
   where a.account_id = p_account_id and c.deleted_at is null and a.effective_period @> now();
  if v_in_effect is not null then
    perform app_private.raise_api_conflict('assignment_in_effect', v_in_effect);
  end if;

  for v_before in
    select * from app.class_assignments a
     where a.account_id = p_account_id
       and a.ended_at is null
       and now() < app_private.day_start(a.start_date)
     order by a.id
       for update
  loop
    v_row := v_before;
    v_row.ended_at := now();
    v_row.end_kind := p_end_kind;
    v_row.ended_by := p_actor_id;
    v_row := app_private.write_assignment(v_row, false);
    perform app_private.record_version('class_assignment', v_row.id, v_row.row_version,
      app_private.assignment_snapshot(v_row), p_actor_id);
    v_cancelled := v_cancelled || to_jsonb(v_row.id);
  end loop;
  return v_cancelled;
end
$$;

-- AUTH-04 (replaces the GĐ 2 version): adds the assignment rule.
create or replace function api.soft_delete_account(
  p_account_id uuid,
  p_reason text,
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
  v_before app.account_profiles := app_private.lock_managed_account(p_account_id, p_expected_version);
  v_reason text := app_private.normalize_reason(p_reason);
  v_after app.account_profiles;
  v_cancelled jsonb;
begin
  if v_before.deleted_at is not null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
  v_cancelled := app_private.settle_assignments_for_account(v_before.id, v_actor.id,
    'cancelled_account_deleted');

  update app.account_profiles a
     set deleted_at = now(),
         deleted_by = v_actor.id,
         deleted_reason = v_reason,
         sessions_valid_after = clock_timestamp(),
         row_version = a.row_version + 1,
         updated_at = now()
   where a.id = p_account_id
  returning * into v_after;

  perform app_private.record_account_change(v_before, v_after, v_actor.id, 'app',
    'account.soft_delete', null, v_reason);
  if jsonb_array_length(v_cancelled) > 0 then
    perform app_private.write_audit(v_actor.id, 'app', 'class.assignment.auto_cancel',
      jsonb_build_object('account_id', v_after.id),
      jsonb_build_object('cause', 'account.soft_delete', 'assignment_ids', v_cancelled));
  end if;
  return app_private.account_summary(v_after);
end
$$;

-- AUTH-07 (replaces the GĐ 2 version): User -> Receptionist needs no
-- assignment in effect and cancels future ones. Receptionist -> User restores
-- no cancelled assignment.
create or replace function api.set_account_type(
  p_account_id uuid,
  p_account_type text,
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
  v_before app.account_profiles;
  v_after app.account_profiles;
  v_cancelled jsonb := '[]';
begin
  if p_account_type = 'admin' then
    perform app_private.raise_api_error(403, 'admin_account_forbidden');
  end if;
  if p_account_type is null or p_account_type not in ('user', 'receptionist') then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  v_before := app_private.lock_managed_account(p_account_id, p_expected_version);
  if v_before.deleted_at is not null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
  if v_before.account_type::text = p_account_type then
    return app_private.account_summary(v_before);
  end if;
  if p_account_type = 'receptionist' then
    v_cancelled := app_private.settle_assignments_for_account(v_before.id, v_actor.id,
      'cancelled_account_type');
  end if;

  update app.account_profiles a
     set account_type = p_account_type::app.account_type,
         row_version = a.row_version + 1,
         updated_at = now()
   where a.id = p_account_id
  returning * into v_after;

  perform app_private.record_account_change(v_before, v_after, v_actor.id, 'app', 'account.type.change');
  if jsonb_array_length(v_cancelled) > 0 then
    perform app_private.write_audit(v_actor.id, 'app', 'class.assignment.auto_cancel',
      jsonb_build_object('account_id', v_after.id),
      jsonb_build_object('cause', 'account.type.change', 'assignment_ids', v_cancelled));
  end if;
  return app_private.account_summary(v_after);
end
$$;

grant execute on function api.list_classes(text, boolean, integer, integer) to authenticated;
grant execute on function api.get_class(uuid) to authenticated;
grant execute on function api.create_class(text, uuid, uuid, date, date, text) to authenticated;
grant execute on function api.update_class(uuid, text, uuid, uuid, date, date, text, bigint)
  to authenticated;
grant execute on function api.list_class_assignments(uuid) to authenticated;
grant execute on function api.list_assignable_accounts() to authenticated;
grant execute on function api.create_class_assignment(uuid, uuid, text, date, date, text)
  to authenticated;
grant execute on function api.update_class_assignment(uuid, text, date, date, text, bigint)
  to authenticated;
grant execute on function api.end_class_assignment(uuid, text, bigint) to authenticated;
