-- ATT-01. Academic identity is student + actual session, never class_student.
create table app.attendance (
  session_id uuid not null references app.class_sessions(id),
  student_id uuid not null references app.students(id),
  present boolean not null,
  note text check (note is null or (note is nfc normalized and char_length(note)<=1000)),
  row_version bigint not null default 1,
  updated_at timestamptz not null default now(),
  updated_by uuid not null references app.account_profiles(id),
  primary key(session_id,student_id)
);
alter table app.attendance enable row level security;
revoke all on app.attendance from public,anon,authenticated;

create function app_private.attendance_roster(p_session app.class_sessions) returns jsonb
language sql stable set search_path = '' as $$
 select coalesce(jsonb_agg(jsonb_build_object('studentId',s.id,'code',s.code,'fullName',s.full_name,
   'present',a.present,'note',a.note) order by s.name_key,s.id),'[]')
 from app.students s left join app.attendance a on a.student_id=s.id and a.session_id=p_session.id
 where exists(select 1 from app.class_students r join app.participations p on p.class_student_id=r.id
   where r.student_id=s.id and r.class_id=p_session.class_id and p.effective_period @> p_session.starts_at)
$$;

create function app_private.attendance_dto(p_session app.class_sessions) returns jsonb
language sql stable set search_path = '' as $$
 select jsonb_build_object('session',app_private.session_dto(p_session),
   'students',app_private.attendance_roster(p_session),
   'fingerprint',md5(jsonb_build_array(p_session.id,p_session.row_version,p_session.attendance_version,
     app_private.attendance_roster(p_session))::text))
$$;

create function api.get_attendance(p_session_id uuid) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare v_session app.class_sessions;
begin
 select * into v_session from app.class_sessions where id=p_session_id;
 if not found then perform app_private.raise_api_error(404,'not_found'); end if;
 perform app_private.require_class_reader(v_session.class_id);
 return app_private.attendance_dto(v_session);
end $$;

-- Client submits the complete reviewed roster with flags; backend rejects a
-- changed roster, duplicate or foreign student, NULL and extra/missing rows.
create function api.save_attendance(p_session_id uuid,p_students jsonb,p_fingerprint text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare v_session app.class_sessions; v_actor app.account_profiles; v_roster jsonb; v_input jsonb;
  v_before jsonb; v_after jsonb; v_class_id uuid;
begin
 perform app_private.lock_scheduling();
 select class_id into v_class_id from app.class_sessions where id=p_session_id;
 if not found then perform app_private.raise_api_error(404,'not_found'); end if;
 v_actor:=app_private.require_account(p_lock => true);
 perform app_private.require_class_reader(v_class_id);
 -- Same class-before-session order as participation/lifecycle commands.
 perform 1 from app.classes where id=v_class_id for update;
 perform app_private.require_account();
 if v_actor.account_type='user' then
   perform app_private.lock_student_edit_assignment(v_actor.id,array[v_class_id]);
 end if;
 select * into v_session from app.class_sessions where id=p_session_id for update;
 if exists(select 1 from app.classes where id=v_class_id and deleted_at is not null) then
   perform app_private.raise_api_error(409,'invalid_state');
 end if;
 if v_session.status<>'scheduled' then perform app_private.raise_api_error(409,'invalid_state'); end if;
 if v_session.starts_at>=clock_timestamp() then perform app_private.raise_api_error(409,'attendance_not_started'); end if;
 if p_fingerprint is null or p_fingerprint is distinct from app_private.attendance_dto(v_session)->>'fingerprint' then
   perform app_private.raise_api_error(409,'version_conflict');
 end if;
 if jsonb_typeof(p_students) is distinct from 'array' then perform app_private.raise_api_error(400,'validation_failed'); end if;
 v_roster:=app_private.attendance_roster(v_session);
 if jsonb_array_length(v_roster)<>jsonb_array_length(p_students) or
   (select count(distinct x->>'studentId') from jsonb_array_elements(p_students) x)<>jsonb_array_length(p_students) then
   perform app_private.raise_api_error(400,'validation_failed');
 end if;
 for v_input in select value from jsonb_array_elements(p_students) loop
   if jsonb_typeof(v_input->'present') is distinct from 'boolean' or
      not exists(select 1 from jsonb_array_elements(v_roster) r where r->>'studentId'=v_input->>'studentId') then
     perform app_private.raise_api_error(400,'validation_failed');
   end if;
   -- Unicode length is checked in DB in addition to the browser/API contract.
   if (v_input->>'note') is not null and char_length(v_input->>'note')>1000 then
     perform app_private.raise_api_error(400,'validation_failed');
   end if;
   select to_jsonb(a) into v_before from app.attendance a where session_id=p_session_id and student_id=(v_input->>'studentId')::uuid;
   insert into app.attendance(session_id,student_id,present,note,updated_by)
   values(p_session_id,(v_input->>'studentId')::uuid,(v_input->>'present')::boolean,
     app_private.clean_optional_text(v_input->>'note',1000),v_actor.id)
   on conflict(session_id,student_id) do update set present=excluded.present,note=excluded.note,
     row_version=app.attendance.row_version+1,updated_at=clock_timestamp(),updated_by=v_actor.id
   returning to_jsonb(app.attendance.*) into v_after;
   perform app_private.record_version('attendance',md5(p_session_id::text||':'||(v_input->>'studentId'))::uuid,
     (v_after->>'row_version')::bigint,v_after,v_actor.id);
 end loop;
 update app.class_sessions set attendance_version=attendance_version+1 where id=p_session_id returning * into v_session;
 perform app_private.write_audit(v_actor.id,'app','attendance.save',jsonb_build_object('class_id',v_class_id,'session_id',p_session_id),
   jsonb_build_object('before',v_roster,'after',app_private.attendance_roster(v_session)));
 return app_private.attendance_dto(v_session);
end $$;

revoke all on function app_private.attendance_roster(app.class_sessions),app_private.attendance_dto(app.class_sessions) from public,anon,authenticated;
revoke all on function api.get_attendance(uuid),api.save_attendance(uuid,jsonb,text) from public,anon;
grant execute on function api.get_attendance(uuid),api.save_attendance(uuid,jsonb,text) to authenticated;
