-- Human-readable disambiguation after hiding internal student codes (STU-04/UX-01).
-- Called only by existing authorized class/student RPCs; no new execution grants.
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
                                  'parentPhones', to_jsonb(app_private.student_phones(s.id, 'parent')),
                                  'birthDate', s.birth_date,
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
