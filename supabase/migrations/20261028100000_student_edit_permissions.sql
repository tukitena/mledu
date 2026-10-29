-- STU-04/STU-03, approved 2026-10-28. Edit rights are independent of management.
-- Do not widen require_manager: creation, deletion, restoration, cancellation,
-- transfer and re-enrollment still require Admin/Receptionist.

create function app_private.can_edit_student(p_student app.students, p_actor_id uuid)
returns boolean
language sql stable set search_path = ''
as $$
  select p_student.deleted_at is null and exists (
    select 1 from app.account_profiles a
    where a.id = p_actor_id and a.is_enabled and a.deleted_at is null
      and not a.must_change_password
      and (a.account_type in ('admin', 'receptionist') or exists (
        select 1 from app.class_students r
        where r.student_id = p_student.id and r.deleted_at is null
          and app_private.class_role(a.id, r.class_id) is not null
      ))
  )
$$;

create function app_private.can_edit_class_student(p_record app.class_students, p_actor_id uuid)
returns boolean
language sql stable set search_path = ''
as $$
  select p_record.deleted_at is null and exists (
    select 1 from app.account_profiles a, app.students s, app.classes c
    where a.id = p_actor_id and a.is_enabled and a.deleted_at is null
      and not a.must_change_password
      and s.id = p_record.student_id and s.deleted_at is null
      and c.id = p_record.class_id and c.deleted_at is null
      and (a.account_type in ('admin', 'receptionist')
           or app_private.class_role(a.id, c.id) is not null)
  )
$$;

-- The class is already locked by the caller. Lock the assignment so revocation
-- cannot commit between authorization and the write. Check again after any wait.
create function app_private.lock_student_edit_assignment(p_actor_id uuid, p_class_ids uuid[])
returns void
language plpgsql volatile set search_path = ''
as $$
declare v_assignment app.class_assignments;
begin
  for v_assignment in
    select a.* from app.class_assignments a
    where a.account_id = p_actor_id and a.class_id = any(p_class_ids)
      and a.effective_period @> clock_timestamp()
    order by a.id for share
  loop
    if v_assignment.effective_period @> clock_timestamp() then return; end if;
  end loop;
  perform app_private.raise_api_error(403, 'forbidden');
end
$$;

create function app_private.lock_student_for_edit(
  p_id uuid, p_expected_version bigint, p_actor app.account_profiles
)
returns app.students
language plpgsql volatile set search_path = ''
as $$
declare
  v_classes uuid[];
  v_student app.students;
begin
  if p_actor.account_type in ('admin', 'receptionist') then
    return app_private.lock_student(p_id, p_expected_version);
  end if;
  -- All class locks precede the student lock, as in enrollment/lifecycle RPCs.
  select array_agg(locked.id) into v_classes from (
    select c.id from app.classes c
    where c.deleted_at is null and app_private.class_role(p_actor.id, c.id) is not null
      and exists (select 1 from app.class_students r
                  where r.class_id = c.id and r.student_id = p_id and r.deleted_at is null)
    order by c.id for share of c
  ) locked;
  if coalesce(cardinality(v_classes), 0) = 0 then
    perform app_private.raise_api_error(403, 'forbidden');
  end if;
  v_student := app_private.lock_student(p_id, p_expected_version);
  if v_student.deleted_at is not null then
    perform app_private.raise_api_error(403, 'forbidden');
  end if;
  -- Lock/re-read links after the student lock: a concurrent archive must not
  -- authorize an edit. Only classes already locked above can confer this right.
  select array_agg(locked.class_id) into v_classes from (
    select r.class_id from app.class_students r
    where r.student_id = p_id and r.class_id = any(v_classes) and r.deleted_at is null
    order by r.id for share of r
  ) locked;
  perform app_private.lock_student_edit_assignment(p_actor.id, v_classes);
  return v_student;
end
$$;

create function app_private.lock_participation_for_edit(
  p_id uuid, p_expected_version bigint, p_actor app.account_profiles
)
returns app.participations
language plpgsql volatile set search_path = ''
as $$
declare
  v_part app.participations;
  v_record app.class_students;
begin
  select * into v_part from app.participations where id = p_id;
  if not found then perform app_private.raise_api_error(404, 'not_found'); end if;
  select * into v_record from app.class_students where id = v_part.class_student_id;
  if p_actor.account_type = 'user'
    and not app_private.can_edit_class_student(v_record, p_actor.id)
  then perform app_private.raise_api_error(403, 'forbidden'); end if;

  -- Existing helper locks class -> student -> record -> participation.
  v_part := app_private.lock_participation(p_id, p_expected_version);
  select * into v_record from app.class_students where id = v_part.class_student_id;
  if v_record.deleted_at is not null
    or exists (select 1 from app.students s where s.id = v_record.student_id and s.deleted_at is not null)
  then
    perform app_private.raise_api_error(
      case when p_actor.account_type = 'user' then 403 else 409 end,
      case when p_actor.account_type = 'user' then 'forbidden' else 'invalid_state' end);
  end if;
  if p_actor.account_type = 'user' then
    perform app_private.lock_student_edit_assignment(p_actor.id, array[v_record.class_id]);
  end if;
  return v_part;
end
$$;

revoke all on function app_private.can_edit_student(app.students, uuid),
  app_private.can_edit_class_student(app.class_students, uuid),
  app_private.lock_student_edit_assignment(uuid, uuid[]),
  app_private.lock_student_for_edit(uuid, bigint, app.account_profiles),
  app_private.lock_participation_for_edit(uuid, bigint, app.account_profiles)
  from public, anon, authenticated;

create or replace function app_private.student_dto(p_student app.students)
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
    'canEdit', app_private.can_edit_student(p_student, auth.uid()),
    'rowVersion', p_student.row_version
  )
$$;

create or replace function app_private.class_student_dto(p_record app.class_students)
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
    'canEdit', app_private.can_edit_class_student(p_record, auth.uid()),
    'rowVersion', p_record.row_version
  )
    from app.classes c, app.students s
   where c.id = p_record.class_id and s.id = p_record.student_id
$$;

create or replace function api.update_student(
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
  v_actor app.account_profiles := app_private.require_account(p_lock => true);
  v_input app_private.student_input := app_private.clean_student_input(p_full_name, p_parent_name,
    p_parent_phones, p_student_phones, p_birth_date, p_school, p_general_note);
  v_before app.students := app_private.lock_student_for_edit(p_id, p_expected_version, v_actor);
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

create or replace function api.set_participation_leave_date(p_id uuid, p_leave_date date, p_expected_version bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_account(p_lock => true);
  v_before app.participations := app_private.lock_participation_for_edit(p_id, p_expected_version, v_actor);
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

create or replace function api.set_participation_note(p_id uuid, p_note text, p_expected_version bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_account(p_lock => true);
  v_before app.participations := app_private.lock_participation_for_edit(p_id, p_expected_version, v_actor);
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

