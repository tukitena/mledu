-- Participation history constrains future class edits (CLASS-03) too.
create or replace function app_private.class_has_activity(p_class app.classes)
returns boolean
language sql
stable
set search_path = ''
as $$
  select app_private.business_date(now()) >= p_class.start_date
    or exists (select 1 from app.class_students r
                 join app.participations p on p.class_student_id = r.id
                where r.class_id = p_class.id)
$$;

-- All participations of a re-added record share the deletion boundary, not
-- just its first participation. A backdated later enrollment cannot rewrite
-- attendance/parent-lookup history before the prior record was deleted.
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
