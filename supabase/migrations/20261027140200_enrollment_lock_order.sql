-- All enrollment commands acquire parent locks before children:
-- classes (SHARE; both classes for transfer), student (SHARE), student advisory
-- lock, class record, participation. Class lifecycle/date changes hold the
-- class lock before touching participations; student deletion holds the
-- student lock before touching participations. Neither can form a cycle.
-- The student advisory lock also serializes transfers in opposite directions.
create or replace function app_private.lock_class_student(p_id uuid, p_expected_version bigint)
returns app.class_students
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_record app.class_students;
begin
  select * into v_record from app.class_students r where r.id = p_id;
  if not found then perform app_private.raise_api_error(404, 'not_found'); end if;
  perform app_private.lock_class_for_students(v_record.class_id, false);
  perform 1 from app.students s where s.id = v_record.student_id for share;
  perform pg_advisory_xact_lock(hashtextextended('enrollment_student:' || v_record.student_id, 0));
  select * into v_record from app.class_students r where r.id = p_id for update;
  if p_expected_version is not null and v_record.row_version <> p_expected_version then
    perform app_private.raise_api_error(409, 'version_conflict');
  end if;
  return v_record;
end
$$;

create or replace function app_private.lock_participation(p_id uuid, p_expected_version bigint)
returns app.participations
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_row app.participations;
begin
  select * into v_row from app.participations p where p.id = p_id;
  if not found then perform app_private.raise_api_error(404, 'not_found'); end if;
  perform app_private.lock_class_student(v_row.class_student_id, null);
  select * into v_row from app.participations p where p.id = p_id for update;
  if p_expected_version is null or v_row.row_version <> p_expected_version then
    perform app_private.raise_api_error(409, 'version_conflict');
  end if;
  return v_row;
end
$$;

create or replace function app_private.enroll(
  p_class app.classes, p_student_id uuid, p_join_date date, p_leave_date date,
  p_note text, p_actor_id uuid
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
  if not found then perform app_private.raise_api_error(404, 'not_found'); end if;
  if v_student.deleted_at is not null then
    perform app_private.raise_api_error(409, 'student_deleted');
  end if;
  perform pg_advisory_xact_lock(hashtextextended('enrollment_student:' || p_student_id, 0));
  perform pg_advisory_xact_lock(hashtextextended('class_student:' || p_class.id || ':' || p_student_id, 0));
  select * into v_record from app.class_students r
   where r.class_id = p_class.id and r.student_id = p_student_id and r.deleted_at is null for update;
  if not found then
    insert into app.class_students (class_id, student_id, created_by)
    values (p_class.id, p_student_id, p_actor_id) returning * into v_record;
    perform app_private.record_version('class_student', v_record.id, v_record.row_version,
      app_private.class_student_snapshot(v_record), p_actor_id);
  end if;
  v_row.not_before := (select max(r.deleted_at) from app.class_students r
    where r.class_id = p_class.id and r.student_id = p_student_id and r.deleted_at is not null);
  if v_row.not_before <= app_private.day_start(p_join_date) then v_row.not_before := null; end if;
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

create or replace function api.transfer_student(
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
  v_before app.participations;
  v_record app.class_students;
  v_source app.participations;
  v_target_class app.classes;
  v_target app.participations;
begin
  select * into v_before from app.participations p where p.id = p_participation_id;
  if not found then perform app_private.raise_api_error(404, 'not_found'); end if;
  select * into v_record from app.class_students r where r.id = v_before.class_student_id;
  -- Both class locks precede student/record/participation locks.
  perform 1 from app.classes c where c.id in (v_record.class_id, p_target_class_id)
    order by c.id for share;
  v_before := app_private.lock_participation(p_participation_id, p_expected_version);
  v_record := app_private.lock_class_student(v_before.class_student_id, null);
  v_source := v_before;
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
