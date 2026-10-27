-- GĐ 3: student–class records and participations (STU-03), transfer and
-- re-enrollment (CLASS-04), the participation effects of STU-01, and the base
-- of the class lifecycle (CLASS-05).
--
-- A student has at most one non-deleted record per class; the record holds
-- many participations. Join dates take effect at 00:00, leave dates exclude
-- from 00:00, and every participation also stops at the end of the class end
-- date recorded for it and at its end event (cancel or soft delete of the
-- student, the class record or the class). Stored dates are never edited to
-- get around a check: mistakes are fixed by cancelling or by archiving the
-- record and adding the student again (a new record, D07).
--
-- Schedules (GĐ 4) and fees (GĐ 6) add their effects to the same commands
-- through app_private.on_class_lifecycle and the participation hooks; the
-- whole CLASS-05 flow is accepted in GĐ 9.

-------------------------------------------------------------------------------
-- Tables.
-------------------------------------------------------------------------------

create table app.class_students (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references app.classes (id),
  student_id uuid not null references app.students (id),
  row_version bigint not null default 1,
  created_at timestamptz not null default now(),
  created_by uuid not null references app.account_profiles (id),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  deleted_by uuid references app.account_profiles (id),
  deleted_reason text,
  constraint class_students_row_version_check check (row_version >= 1),
  constraint class_students_deleted_check check (
    (deleted_at is null and deleted_by is null and deleted_reason is null)
    or (deleted_at is not null and deleted_by is not null
        and char_length(deleted_reason) between 1 and 1000)
  )
);

-- At most one non-deleted record per student and class (STU-03).
create unique index class_students_active_key on app.class_students (class_id, student_id)
  where deleted_at is null;
create index class_students_student_idx on app.class_students (student_id);

comment on table app.class_students is
  'Student–class record (STU-03). Deleting and adding again creates a new record (D07).';

-- Effective interval of a participation: from the join date (not before
-- p_not_before) to the earliest of the leave date, the day after the recorded
-- class end date and the end event. Empty when it never started.
create function app_private.participation_period(
  p_join_date date,
  p_leave_date date,
  p_class_end_date date,
  p_not_before timestamptz,
  p_ended_at timestamptz
)
returns tstzrange
language sql
immutable
parallel safe
set search_path = ''
as $$
  with bounds as (
    select greatest(app_private.day_start(p_join_date), coalesce(p_not_before, '-infinity')) as lower_at,
           least(coalesce(app_private.day_start(p_leave_date), 'infinity'),
                 app_private.day_start(p_class_end_date + 1),
                 coalesce(p_ended_at, 'infinity')) as upper_at
  )
  select case when upper_at <= lower_at then 'empty'::tstzrange
              else tstzrange(lower_at, upper_at, '[)') end
    from bounds
$$;

create table app.participations (
  id uuid primary key default gen_random_uuid(),
  class_student_id uuid not null references app.class_students (id),
  join_date date not null,
  -- First day the student no longer attends; written once, never changed.
  leave_date date,
  -- Class end date that applies to this participation; follows extensions
  -- only while the participation has not ended (CLASS-03).
  class_end_date date not null,
  -- A re-added record never starts before the old record was deleted (STU-03).
  not_before timestamptz,
  note text,
  ended_at timestamptz,
  end_kind text,
  end_reason text,
  ended_by uuid references app.account_profiles (id),
  effective_period tstzrange not null,
  row_version bigint not null default 1,
  created_at timestamptz not null default now(),
  created_by uuid not null references app.account_profiles (id),
  updated_at timestamptz not null default now(),
  constraint participations_leave_check check (leave_date is null or leave_date > join_date),
  constraint participations_note_check check (
    note is null or (note is nfc normalized and char_length(note) between 1 and 1000)
  ),
  constraint participations_end_check check (
    (ended_at is null and end_kind is null and end_reason is null and ended_by is null)
    or (ended_at is not null and ended_by is not null
        and end_kind in ('cancelled', 'record_deleted', 'student_deleted', 'class_deleted')
        and (end_reason is null or char_length(end_reason) between 1 and 1000))
  ),
  constraint participations_period_check check (
    effective_period = app_private.participation_period(join_date, leave_date, class_end_date,
                                                        not_before, ended_at)
  ),
  constraint participations_row_version_check check (row_version >= 1),
  -- Participations of one record never overlap (STU-03).
  constraint participations_no_overlap
    exclude using gist (class_student_id with =, effective_period with &&)
);

create index participations_record_idx on app.participations (class_student_id);

comment on table app.participations is
  'Participation in a class record (STU-03). Status is computed from dates and end events.';

-- Lifecycle events of a class (CLASS-05), kept without time limit.
create table app.class_lifecycle_events (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references app.classes (id),
  kind text not null,
  reason text,
  happened_at timestamptz not null default now(),
  actor_id uuid not null references app.account_profiles (id),
  constraint class_lifecycle_events_kind_check check (kind in ('close', 'reopen', 'delete', 'restore')),
  constraint class_lifecycle_events_reason_check check (
    (kind in ('close', 'delete') and char_length(reason) between 1 and 1000)
    or (kind in ('reopen', 'restore') and reason is null)
  )
);

create index class_lifecycle_events_class_idx on app.class_lifecycle_events (class_id, happened_at);

create trigger class_lifecycle_events_no_change
  before update or delete on app.class_lifecycle_events
  for each row execute function app_private.reject_change();

alter table app.class_students enable row level security;
alter table app.participations enable row level security;
alter table app.class_lifecycle_events enable row level security;
revoke all on table app.class_students, app.participations, app.class_lifecycle_events
  from public, anon, authenticated;

-------------------------------------------------------------------------------
-- Status, snapshots and DTOs (packages/contracts/src/enrollments.ts).
-------------------------------------------------------------------------------

-- cancelled: ended before it started; not_started; active; ended.
create function app_private.participation_status(p_row app.participations)
returns text
language sql
stable
set search_path = ''
as $$
  select case
    when isempty(p_row.effective_period) then 'cancelled'
    when now() < lower(p_row.effective_period) then 'not_started'
    when p_row.effective_period @> now() then 'active'
    else 'ended'
  end
$$;

create function app_private.participation_snapshot(p_row app.participations)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'class_student_id', p_row.class_student_id,
    'join_date', p_row.join_date,
    'leave_date', p_row.leave_date,
    'class_end_date', p_row.class_end_date,
    'not_before', p_row.not_before,
    'note', p_row.note,
    'ended_at', p_row.ended_at,
    'end_kind', p_row.end_kind,
    'end_reason', p_row.end_reason,
    'ended_by', p_row.ended_by
  )
$$;

create function app_private.participation_dto(p_row app.participations)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_row.id,
    'classStudentId', p_row.class_student_id,
    'joinDate', p_row.join_date,
    'leaveDate', p_row.leave_date,
    'classEndDate', p_row.class_end_date,
    'note', p_row.note,
    'status', app_private.participation_status(p_row),
    'effectiveFrom', case when isempty(p_row.effective_period) then null
                          else lower(p_row.effective_period) end,
    'effectiveUntil', case when isempty(p_row.effective_period) then null
                           else upper(p_row.effective_period) end,
    'endedAt', p_row.ended_at,
    'endKind', p_row.end_kind,
    'endReason', p_row.end_reason,
    'rowVersion', p_row.row_version
  )
$$;

create function app_private.class_student_snapshot(p_record app.class_students)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'class_id', p_record.class_id,
    'student_id', p_record.student_id,
    'deleted_at', p_record.deleted_at,
    'deleted_by', p_record.deleted_by,
    'deleted_reason', p_record.deleted_reason
  )
$$;

-- Includes participation notes (class notes): callers only return it to
-- people with class rights (STU-04).
create function app_private.class_student_dto(p_record app.class_students)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_record.id,
    'classId', p_record.class_id,
    'className', c.name,
    'classDeleted', c.deleted_at is not null,
    'classAdminState', c.admin_state,
    'student', jsonb_build_object('id', s.id, 'code', s.code, 'fullName', s.full_name,
                                  'deleted', s.deleted_at is not null),
    'deleted', p_record.deleted_at is not null,
    'deletedAt', p_record.deleted_at,
    'deletedReason', p_record.deleted_reason,
    'createdAt', p_record.created_at,
    'participations', coalesce((
      select jsonb_agg(app_private.participation_dto(p) order by p.join_date, p.created_at)
        from app.participations p
       where p.class_student_id = p_record.id
    ), '[]'),
    'rowVersion', p_record.row_version
  )
    from app.classes c, app.students s
   where c.id = p_record.class_id and s.id = p_record.student_id
$$;

-------------------------------------------------------------------------------
-- Extension points for later phases (inside the same transaction).
-------------------------------------------------------------------------------

-- Called by every class lifecycle command after its own changes. GĐ 4 removes
-- or rebuilds future sessions (keeping a business record of removed ones), GĐ 6
-- creates or cancels obligations. p_event: close, reopen, delete, restore.
create function app_private.on_class_lifecycle(p_class app.classes, p_event text, p_actor_id uuid)
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  return;
end
$$;

-- Called when participations end or are cancelled by an event or a leave date.
-- GĐ 6 cancels unpaid future obligations that no longer have a participation
-- to serve (STU-03, FEE-07/10); collected and accrued amounts are kept.
create function app_private.on_participations_ended(p_participation_ids uuid[], p_actor_id uuid)
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  return;
end
$$;

-------------------------------------------------------------------------------
-- Internal helpers.
-------------------------------------------------------------------------------

-- Stores a participation; an overlap inside the record is participation_overlap.
create function app_private.write_participation(p_row app.participations, p_insert boolean)
returns app.participations
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_row app.participations;
  v_period tstzrange := app_private.participation_period(p_row.join_date, p_row.leave_date,
    p_row.class_end_date, p_row.not_before, p_row.ended_at);
begin
  if p_insert then
    insert into app.participations (class_student_id, join_date, leave_date, class_end_date,
                                    not_before, note, effective_period, created_by)
    values (p_row.class_student_id, p_row.join_date, p_row.leave_date, p_row.class_end_date,
            p_row.not_before, p_row.note, v_period, p_row.created_by)
    returning * into v_row;
  else
    update app.participations p
       set leave_date = p_row.leave_date,
           class_end_date = p_row.class_end_date,
           note = p_row.note,
           ended_at = p_row.ended_at,
           end_kind = p_row.end_kind,
           end_reason = p_row.end_reason,
           ended_by = p_row.ended_by,
           effective_period = v_period,
           row_version = p.row_version + 1,
           updated_at = now()
     where p.id = p_row.id
    returning * into v_row;
  end if;
  return v_row;
exception
  when exclusion_violation then
    perform app_private.raise_api_error(409, 'participation_overlap');
    return null;
end
$$;

-- Ends every participation of the given records that has not ended yet, at
-- now: an active one ends, a future one becomes cancelled (empty interval).
-- Writes a version per participation; returns the ids for the caller's audit.
create function app_private.end_open_participations(
  p_record_ids uuid[],
  p_end_kind text,
  p_reason text,
  p_actor_id uuid
)
returns uuid[]
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_before app.participations;
  v_row app.participations;
  v_ids uuid[] := '{}';
begin
  for v_before in
    select * from app.participations p
     where p.class_student_id = any (p_record_ids)
       and p.ended_at is null
       and not isempty(p.effective_period)
       and upper(p.effective_period) > now()
     order by p.id
       for update
  loop
    v_row := v_before;
    v_row.ended_at := now();
    v_row.end_kind := p_end_kind;
    v_row.end_reason := p_reason;
    v_row.ended_by := p_actor_id;
    v_row := app_private.write_participation(v_row, false);
    perform app_private.record_version('participation', v_row.id, v_row.row_version,
      app_private.participation_snapshot(v_row), p_actor_id, p_reason);
    v_ids := v_ids || v_row.id;
  end loop;
  perform app_private.on_participations_ended(v_ids, p_actor_id);
  return v_ids;
end
$$;

create function app_private.lock_participation(p_id uuid, p_expected_version bigint)
returns app.participations
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_row app.participations;
begin
  select * into v_row from app.participations p where p.id = p_id for update;
  if not found then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  if p_expected_version is null or v_row.row_version <> p_expected_version then
    perform app_private.raise_api_error(409, 'version_conflict');
  end if;
  return v_row;
end
$$;

create function app_private.lock_class_student(p_id uuid, p_expected_version bigint)
returns app.class_students
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_record app.class_students;
begin
  select * into v_record from app.class_students r where r.id = p_id for update;
  if not found then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  if p_expected_version is not null and v_record.row_version <> p_expected_version then
    perform app_private.raise_api_error(409, 'version_conflict');
  end if;
  return v_record;
end
$$;

-- Class of a record, locked, for commands that change the record: the class
-- must not be deleted (XLS-02). p_enrolling also requires an open class.
create function app_private.lock_class_for_students(p_class_id uuid, p_enrolling boolean)
returns app.classes
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_class app.classes;
begin
  select * into v_class from app.classes c where c.id = p_class_id for share;
  if not found then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  if v_class.deleted_at is not null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
  if p_enrolling and v_class.admin_state <> 'open' then
    perform app_private.raise_api_error(409, 'class_closed');
  end if;
  return v_class;
end
$$;

-- Adds a participation for a student in a class (STU-03, CLASS-04, XLS-02):
-- in the current record (re-enrollment), or in a new record when every
-- earlier record was deleted. Returns the participation; the caller audits.
create function app_private.enroll(
  p_class app.classes,
  p_student_id uuid,
  p_join_date date,
  p_leave_date date,
  p_note text,
  p_actor_id uuid
)
returns app.participations
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_student app.students;
  v_record app.class_students;
  v_row app.participations;
begin
  if p_join_date is null or (p_leave_date is not null and p_leave_date <= p_join_date) then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  if p_join_date < p_class.start_date or p_join_date > p_class.end_date then
    perform app_private.raise_api_error(409, 'outside_class_dates');
  end if;
  select * into v_student from app.students s where s.id = p_student_id for share;
  if not found then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  if v_student.deleted_at is not null then
    perform app_private.raise_api_error(409, 'student_deleted');
  end if;

  -- One record per student and class at a time, even for concurrent requests.
  perform pg_advisory_xact_lock(hashtextextended('class_student:' || p_class.id || ':' || p_student_id, 0));
  select * into v_record
    from app.class_students r
   where r.class_id = p_class.id and r.student_id = p_student_id and r.deleted_at is null
     for update;
  if not found then
    insert into app.class_students (class_id, student_id, created_by)
    values (p_class.id, p_student_id, p_actor_id)
    returning * into v_record;
    perform app_private.record_version('class_student', v_record.id, v_record.row_version,
      app_private.class_student_snapshot(v_record), p_actor_id);
    -- The new record starts no earlier than the deletion of the previous one,
    -- even on the same day; old records are not used to refuse the dates.
    v_row.not_before := (select max(r.deleted_at) from app.class_students r
                          where r.class_id = p_class.id and r.student_id = p_student_id
                            and r.deleted_at is not null);
    if v_row.not_before <= app_private.day_start(p_join_date) then
      v_row.not_before := null;
    end if;
  end if;

  v_row.class_student_id := v_record.id;
  v_row.join_date := p_join_date;
  v_row.leave_date := p_leave_date;
  v_row.class_end_date := p_class.end_date;
  v_row.note := app_private.clean_optional_text(p_note, 1000);
  v_row.created_by := p_actor_id;
  v_row := app_private.write_participation(v_row, true);
  perform app_private.record_version('participation', v_row.id, v_row.row_version,
    app_private.participation_snapshot(v_row), p_actor_id);
  return v_row;
end
$$;

create function app_private.participation_refs(p_row app.participations)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object('class_id', r.class_id, 'student_id', r.student_id,
                            'class_student_id', r.id, 'participation_id', p_row.id)
    from app.class_students r
   where r.id = p_row.class_student_id
$$;

-------------------------------------------------------------------------------
-- Queries.
-------------------------------------------------------------------------------

-- Admin/Receptionist and staff with an assignment in effect read the records
-- of a class; deleted records too, for history (XLS-02). Users never get
-- financial data from here.
create function api.list_class_students(p_class_id uuid, p_include_deleted boolean default false)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  perform app_private.require_class_reader(p_class_id);
  return coalesce((
    select jsonb_agg(app_private.class_student_dto(r) order by s.name_key, s.code, r.created_at)
      from app.class_students r
      join app.students s on s.id = r.student_id
     where r.class_id = p_class_id
       and (coalesce(p_include_deleted, false) or r.deleted_at is null)
  ), '[]');
end
$$;

-- Class history of a student: every class for Admin/Receptionist; for a User
-- only the classes it currently teaches (class notes stay inside the class).
create function api.list_student_classes(p_student_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_account();
  v_manager boolean := v_actor.account_type in ('admin', 'receptionist');
begin
  if not exists (select 1 from app.students s where s.id = p_student_id
                  and (v_manager or s.deleted_at is null)) then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  return coalesce((
    select jsonb_agg(app_private.class_student_dto(r) order by r.created_at desc)
      from app.class_students r
     where r.student_id = p_student_id
       and (v_manager or app_private.class_role(v_actor.id, r.class_id) is not null)
  ), '[]');
end
$$;

-------------------------------------------------------------------------------
-- Commands on participations (Admin/Receptionist).
-------------------------------------------------------------------------------

create function api.enroll_student(
  p_class_id uuid,
  p_student_id uuid,
  p_join_date date,
  p_leave_date date default null,
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
  v_class app.classes := app_private.lock_class_for_students(p_class_id, true);
  v_row app.participations;
  v_record app.class_students;
begin
  v_row := app_private.enroll(v_class, p_student_id, p_join_date, p_leave_date, p_note, v_actor.id);
  perform app_private.write_audit(v_actor.id, 'app', 'class.student.enroll',
    app_private.participation_refs(v_row),
    jsonb_build_object('after', app_private.participation_snapshot(v_row)));
  select * into v_record from app.class_students r where r.id = v_row.class_student_id;
  return app_private.class_student_dto(v_record);
end
$$;

-- STU-03: the leave date is written once (first day not attending, > join
-- date) and never changed or removed afterwards.
create function api.set_participation_leave_date(p_id uuid, p_leave_date date, p_expected_version bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_manager();
  v_before app.participations := app_private.lock_participation(p_id, p_expected_version);
  v_record app.class_students := app_private.lock_class_student(v_before.class_student_id, null);
  v_row app.participations := v_before;
begin
  perform app_private.lock_class_for_students(v_record.class_id, false);
  if v_record.deleted_at is not null or v_before.ended_at is not null
    or isempty(v_before.effective_period)
  then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
  if v_before.leave_date is not null then
    perform app_private.raise_api_error(409, 'participation_dates_locked');
  end if;
  if p_leave_date is null or p_leave_date <= v_before.join_date then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;

  v_row.leave_date := p_leave_date;
  v_row := app_private.write_participation(v_row, false);
  perform app_private.record_change('participation', v_row.id, v_row.row_version,
    app_private.participation_snapshot(v_before), app_private.participation_snapshot(v_row),
    v_actor.id, 'class.student.leave', app_private.participation_refs(v_row));
  perform app_private.on_participations_ended(array[v_row.id], v_actor.id);
  return app_private.class_student_dto(v_record);
end
$$;

-- The class note of a participation stays editable (XLS-02), also when the
-- class is closed; never for a deleted record.
create function api.set_participation_note(p_id uuid, p_note text, p_expected_version bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_manager();
  v_before app.participations := app_private.lock_participation(p_id, p_expected_version);
  v_record app.class_students := app_private.lock_class_student(v_before.class_student_id, null);
  v_row app.participations := v_before;
begin
  perform app_private.lock_class_for_students(v_record.class_id, false);
  if v_record.deleted_at is not null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
  v_row.note := app_private.clean_optional_text(p_note, 1000);
  if v_row.note is not distinct from v_before.note then
    return app_private.class_student_dto(v_record);
  end if;
  v_row := app_private.write_participation(v_row, false);
  perform app_private.record_change('participation', v_row.id, v_row.row_version,
    app_private.participation_snapshot(v_before), app_private.participation_snapshot(v_row),
    v_actor.id, 'class.student.note', app_private.participation_refs(v_row));
  return app_private.class_student_dto(v_record);
end
$$;

-- STU-03: only a participation that has not started can be cancelled; the
-- record is kept with its cancelled state.
create function api.cancel_participation(p_id uuid, p_reason text, p_expected_version bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_manager();
  v_reason text := app_private.normalize_reason(p_reason);
  v_before app.participations := app_private.lock_participation(p_id, p_expected_version);
  v_record app.class_students := app_private.lock_class_student(v_before.class_student_id, null);
  v_row app.participations := v_before;
begin
  perform app_private.lock_class_for_students(v_record.class_id, false);
  if v_record.deleted_at is not null or app_private.participation_status(v_before) <> 'not_started' then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;

  v_row.ended_at := now();
  v_row.end_kind := 'cancelled';
  v_row.end_reason := v_reason;
  v_row.ended_by := v_actor.id;
  v_row := app_private.write_participation(v_row, false);
  perform app_private.record_change('participation', v_row.id, v_row.row_version,
    app_private.participation_snapshot(v_before), app_private.participation_snapshot(v_row),
    v_actor.id, 'class.student.cancel', app_private.participation_refs(v_row), v_reason);
  perform app_private.on_participations_ended(array[v_row.id], v_actor.id);
  return app_private.class_student_dto(v_record);
end
$$;

-- XLS-02 "remove from class": soft-deletes the record and ends/cancels its
-- open participations at now. Grades, comments, attendance and fees are kept.
create function api.soft_delete_class_student(p_id uuid, p_reason text, p_expected_version bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_manager();
  v_reason text := app_private.normalize_reason(p_reason);
  v_before app.class_students := app_private.lock_class_student(p_id, p_expected_version);
  v_after app.class_students;
  v_ended uuid[];
begin
  if p_expected_version is null then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  perform app_private.lock_class_for_students(v_before.class_id, false);
  if v_before.deleted_at is not null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;

  v_ended := app_private.end_open_participations(array[v_before.id], 'record_deleted', v_reason,
    v_actor.id);
  update app.class_students r
     set deleted_at = now(),
         deleted_by = v_actor.id,
         deleted_reason = v_reason,
         row_version = r.row_version + 1,
         updated_at = now()
   where r.id = v_before.id
  returning * into v_after;

  perform app_private.record_version('class_student', v_after.id, v_after.row_version,
    app_private.class_student_snapshot(v_after), v_actor.id, v_reason);
  perform app_private.write_audit(v_actor.id, 'app', 'class.student.soft_delete',
    jsonb_build_object('class_id', v_after.class_id, 'student_id', v_after.student_id,
                       'class_student_id', v_after.id),
    jsonb_build_object('before', app_private.class_student_snapshot(v_before),
                       'after', app_private.class_student_snapshot(v_after),
                       'ended_participation_ids', to_jsonb(v_ended), 'reason', v_reason));
  return app_private.class_student_dto(v_after);
end
$$;

-- CLASS-04: records the leave date at the source (or uses the stored one) and
-- adds a participation at the target in one transaction. Money, grades and
-- comments stay with their records; nothing is copied.
create function api.transfer_student(
  p_participation_id uuid,
  p_target_class_id uuid,
  p_leave_date date,
  p_join_date date,
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
  v_before app.participations := app_private.lock_participation(p_participation_id, p_expected_version);
  v_record app.class_students := app_private.lock_class_student(v_before.class_student_id, null);
  v_source app.participations := v_before;
  v_target_class app.classes;
  v_target app.participations;
begin
  if p_target_class_id = v_record.class_id then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  perform app_private.lock_class_for_students(v_record.class_id, false);
  if v_record.deleted_at is not null or v_before.ended_at is not null
    or isempty(v_before.effective_period)
  then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
  if v_before.leave_date is null then
    if p_leave_date is null or p_leave_date <= v_before.join_date then
      perform app_private.raise_api_error(400, 'validation_failed');
    end if;
    v_source.leave_date := p_leave_date;
    v_source := app_private.write_participation(v_source, false);
    perform app_private.record_version('participation', v_source.id, v_source.row_version,
      app_private.participation_snapshot(v_source), v_actor.id);
    perform app_private.on_participations_ended(array[v_source.id], v_actor.id);
  elsif p_leave_date is not null and p_leave_date <> v_before.leave_date then
    perform app_private.raise_api_error(409, 'participation_dates_locked');
  end if;

  v_target_class := app_private.lock_class_for_students(p_target_class_id, true);
  v_target := app_private.enroll(v_target_class, v_record.student_id, p_join_date, null, p_note,
    v_actor.id);

  perform app_private.write_audit(v_actor.id, 'app', 'class.student.transfer',
    jsonb_build_object('student_id', v_record.student_id, 'class_id', v_record.class_id,
                       'target_class_id', v_target_class.id, 'participation_id', v_source.id,
                       'target_participation_id', v_target.id),
    jsonb_build_object('source_before', app_private.participation_snapshot(v_before),
                       'source_after', app_private.participation_snapshot(v_source),
                       'target_after', app_private.participation_snapshot(v_target)));
  select * into v_record from app.class_students r where r.id = v_target.class_student_id;
  return app_private.class_student_dto(v_record);
end
$$;

-------------------------------------------------------------------------------
-- Effects on existing commands.
-------------------------------------------------------------------------------

-- CLASS-03 (replaces the classes version): stored join dates stay inside the
-- class dates; participations that have not ended follow the new end date,
-- ended ones keep theirs (an extension never revives them).
create or replace function app_private.apply_class_date_change(p_before app.classes, p_after app.classes)
returns void
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_before app.participations;
  v_row app.participations;
begin
  if exists (
    select 1
      from app.participations p
      join app.class_students r on r.id = p.class_student_id
     where r.class_id = p_after.id
       and not isempty(p.effective_period)
       and (p.join_date < p_after.start_date or p.join_date > p_after.end_date)
  ) then
    perform app_private.raise_api_error(409, 'participations_outside_dates');
  end if;

  for v_before in
    select p.*
      from app.participations p
      join app.class_students r on r.id = p.class_student_id
     where r.class_id = p_after.id
       and p.ended_at is null
       and not isempty(p.effective_period)
       and upper(p.effective_period) > now()
     order by p.id
       for update of p
  loop
    v_row := v_before;
    v_row.class_end_date := p_after.end_date;
    v_row := app_private.write_participation(v_row, false);
    perform app_private.record_version('participation', v_row.id, v_row.row_version,
      app_private.participation_snapshot(v_row), auth.uid());
  end loop;
end
$$;

-- STU-01 (replaces the students version): ends the student's current
-- participations and cancels future ones in every class, in the same command.
-- Class records are kept (not deleted); fees follow in GĐ 6 via the hook.
create or replace function api.soft_delete_student(p_id uuid, p_reason text, p_expected_version bigint)
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
  v_ended uuid[];
begin
  if v_before.deleted_at is not null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;

  v_ended := app_private.end_open_participations(
    array(select r.id from app.class_students r where r.student_id = v_before.id and r.deleted_at is null),
    'student_deleted', v_reason, v_actor.id);

  update app.students s
     set deleted_at = now(),
         deleted_by = v_actor.id,
         deleted_reason = v_reason,
         row_version = s.row_version + 1,
         updated_at = now()
   where s.id = v_before.id
  returning * into v_after;

  perform app_private.record_version('student', v_after.id, v_after.row_version,
    app_private.student_snapshot(v_after), v_actor.id, v_reason);
  perform app_private.write_audit(v_actor.id, 'app', 'student.soft_delete',
    jsonb_build_object('student_id', v_after.id),
    jsonb_build_object('before', app_private.student_snapshot(v_before),
                       'after', app_private.student_snapshot(v_after),
                       'ended_participation_ids', to_jsonb(v_ended), 'reason', v_reason));
  return app_private.student_dto(v_after);
end
$$;

-- Impact shown before deleting a student (STU-01): participations that end
-- now and future ones that are cancelled, per class.
create function api.student_delete_impact(p_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  perform app_private.require_manager();
  if not exists (select 1 from app.students s where s.id = p_id) then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  return jsonb_build_object(
    'activeParticipations', (select count(*) from app.participations p
                               join app.class_students r on r.id = p.class_student_id
                              where r.student_id = p_id and r.deleted_at is null
                                and app_private.participation_status(p) = 'active'),
    'futureParticipations', (select count(*) from app.participations p
                               join app.class_students r on r.id = p.class_student_id
                              where r.student_id = p_id and r.deleted_at is null
                                and app_private.participation_status(p) = 'not_started'),
    'classes', coalesce((select jsonb_agg(distinct c.name)
                           from app.class_students r
                           join app.classes c on c.id = r.class_id
                          where r.student_id = p_id and r.deleted_at is null), '[]')
  );
end
$$;

-------------------------------------------------------------------------------
-- Class lifecycle base (CLASS-05).
-------------------------------------------------------------------------------

create function app_private.record_class_lifecycle(
  p_before app.classes,
  p_after app.classes,
  p_kind text,
  p_reason text,
  p_actor_id uuid,
  p_details jsonb default '{}'
)
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  insert into app.class_lifecycle_events (class_id, kind, reason, actor_id)
  values (p_after.id, p_kind, p_reason, p_actor_id);
  perform app_private.record_version('class', p_after.id, p_after.row_version,
    app_private.class_snapshot(p_after), p_actor_id, p_reason);
  perform app_private.write_audit(p_actor_id, 'app', 'class.' || p_kind,
    jsonb_build_object('class_id', p_after.id),
    jsonb_strip_nulls(jsonb_build_object('before', app_private.class_snapshot(p_before),
      'after', app_private.class_snapshot(p_after), 'reason', p_reason)) || p_details);
  perform app_private.on_class_lifecycle(p_after, p_kind, p_actor_id);
end
$$;

-- Impact shown before closing or deleting a class.
create function api.class_lifecycle_impact(p_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  perform app_private.require_manager();
  if not exists (select 1 from app.classes c where c.id = p_id) then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  return jsonb_build_object(
    'activeParticipations', (select count(*) from app.participations p
                               join app.class_students r on r.id = p.class_student_id
                              where r.class_id = p_id and r.deleted_at is null
                                and app_private.participation_status(p) = 'active'),
    'futureParticipations', (select count(*) from app.participations p
                               join app.class_students r on r.id = p.class_student_id
                              where r.class_id = p_id and r.deleted_at is null
                                and app_private.participation_status(p) = 'not_started'),
    'activeAssignments', (select count(*) from app.class_assignments a
                           where a.class_id = p_id and a.effective_period @> now())
  );
end
$$;

-- Closing keeps dates, participations and assignments; it blocks enrollment.
create function api.close_class(p_id uuid, p_reason text, p_expected_version bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_manager();
  v_reason text := app_private.normalize_reason(p_reason);
  v_before app.classes;
  v_after app.classes;
begin
  if p_expected_version is null then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  v_before := app_private.lock_class(p_id, p_expected_version);
  if v_before.deleted_at is not null or v_before.admin_state <> 'open' then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
  update app.classes c
     set admin_state = 'closed', closed_at = now(), row_version = c.row_version + 1, updated_at = now()
   where c.id = v_before.id
  returning * into v_after;
  perform app_private.record_class_lifecycle(v_before, v_after, 'close', v_reason, v_actor.id);
  return app_private.class_dto(v_after);
end
$$;

-- Reopening needs an end date that has not passed; it revives nothing that
-- ended while the class was closed.
create function api.reopen_class(p_id uuid, p_expected_version bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_manager();
  v_before app.classes;
  v_after app.classes;
begin
  if p_expected_version is null then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  v_before := app_private.lock_class(p_id, p_expected_version);
  if v_before.deleted_at is not null or v_before.admin_state <> 'closed' then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
  if v_before.end_date < app_private.business_date(now()) then
    perform app_private.raise_api_error(409, 'class_ended');
  end if;
  update app.classes c
     set admin_state = 'open', closed_at = null, row_version = c.row_version + 1, updated_at = now()
   where c.id = v_before.id
  returning * into v_after;
  perform app_private.record_class_lifecycle(v_before, v_after, 'reopen', null, v_actor.id);
  return app_private.class_dto(v_after);
end
$$;

-- Soft delete: ends current participations and cancels future ones at now;
-- records, staff, academics and fees are kept. User rights stop at once.
create function api.soft_delete_class(p_id uuid, p_reason text, p_expected_version bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_manager();
  v_reason text := app_private.normalize_reason(p_reason);
  v_before app.classes;
  v_after app.classes;
  v_ended uuid[];
begin
  if p_expected_version is null then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  v_before := app_private.lock_class(p_id, p_expected_version);
  if v_before.deleted_at is not null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
  v_ended := app_private.end_open_participations(
    array(select r.id from app.class_students r where r.class_id = v_before.id and r.deleted_at is null),
    'class_deleted', v_reason, v_actor.id);
  update app.classes c
     set deleted_at = now(), deleted_by = v_actor.id, deleted_reason = v_reason,
         row_version = c.row_version + 1, updated_at = now()
   where c.id = v_before.id
  returning * into v_after;
  perform app_private.record_class_lifecycle(v_before, v_after, 'delete', v_reason, v_actor.id,
    jsonb_build_object('ended_participation_ids', to_jsonb(v_ended)));
  return app_private.class_dto(v_after);
end
$$;

-- Restore returns the class as closed, to be reviewed and reopened; ended and
-- cancelled participations stay as they are (CLASS-05).
create function api.restore_class(p_id uuid, p_expected_version bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_manager();
  v_before app.classes;
  v_after app.classes;
begin
  if p_expected_version is null then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  v_before := app_private.lock_class(p_id, p_expected_version);
  if v_before.deleted_at is null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
  update app.classes c
     set deleted_at = null, deleted_by = null, deleted_reason = null,
         admin_state = 'closed', closed_at = coalesce(c.closed_at, now()),
         row_version = c.row_version + 1, updated_at = now()
   where c.id = v_before.id
  returning * into v_after;
  perform app_private.record_class_lifecycle(v_before, v_after, 'restore', null, v_actor.id);
  return app_private.class_dto(v_after);
end
$$;

grant execute on function api.list_class_students(uuid, boolean) to authenticated;
grant execute on function api.list_student_classes(uuid) to authenticated;
grant execute on function api.enroll_student(uuid, uuid, date, date, text) to authenticated;
grant execute on function api.set_participation_leave_date(uuid, date, bigint) to authenticated;
grant execute on function api.set_participation_note(uuid, text, bigint) to authenticated;
grant execute on function api.cancel_participation(uuid, text, bigint) to authenticated;
grant execute on function api.soft_delete_class_student(uuid, text, bigint) to authenticated;
grant execute on function api.transfer_student(uuid, uuid, date, date, text, bigint) to authenticated;
grant execute on function api.student_delete_impact(uuid) to authenticated;
grant execute on function api.class_lifecycle_impact(uuid) to authenticated;
grant execute on function api.close_class(uuid, text, bigint) to authenticated;
grant execute on function api.reopen_class(uuid, bigint) to authenticated;
grant execute on function api.soft_delete_class(uuid, text, bigint) to authenticated;
grant execute on function api.restore_class(uuid, bigint) to authenticated;
