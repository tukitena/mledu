-- GĐ 5, fourth feature: publishing and unpublishing results (ACAD-01, with the
-- publication rules of TEST-01/04).
--
-- The unit is the result of one student in one test. Admin or a current
-- teacher of the class publishes one student or the whole class of one test;
-- assistants and receptionists cannot. Only complete results (or Absent) are
-- published. Publishing the class skips students without a complete result
-- and returns them; nothing is created for them and a later entry is never
-- published automatically. Unpublishing is the only way to unlock a result.
-- Comments have their own publication (comments feature); this changes none.

-------------------------------------------------------------------------------
-- DTOs: who published, how many results are published, and the caller's right.
-------------------------------------------------------------------------------

create or replace function app_private.result_dto(p_result app.test_results)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_result.id,
    'absent', p_result.result_kind = 'absent',
    'score', p_result.numeric_score,
    'correctAnswers', p_result.correct_answers,
    'level', (select l.code from app.test_letter_levels l where l.id = p_result.letter_level_id),
    'components', app_private.result_components(p_result.id),
    'complete', app_private.result_complete(p_result),
    'published', p_result.published_at is not null,
    'publishedAt', p_result.published_at,
    'publishedByName', (select b.full_name from app.account_profiles b where b.id = p_result.published_by),
    'rowVersion', p_result.row_version,
    'updatedAt', p_result.updated_at,
    'updatedByName', a.full_name
  )
    from app.account_profiles a
   where a.id = p_result.updated_by
$$;

create or replace function app_private.test_dto(p_test app.tests)
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
    'resultCount', (select count(*) from app.test_results x
                     where x.test_id = p_test.id and x.deleted_at is null),
    'publishedCount', (select count(*) from app.test_results x
                        where x.test_id = p_test.id and x.published_at is not null),
    'deleted', p_test.deleted_at is not null,
    'createdAt', p_test.created_at,
    'createdByName', a.full_name,
    'updatedAt', p_test.updated_at,
    'rowVersion', p_test.row_version
  )
    from app.test_config_versions c, app.account_profiles a
   where c.id = p_test.current_config_id and a.id = p_test.created_by
$$;

-- Publication right of ACAD-01: Admin or a current teacher (never assistants).
create function app_private.can_publish(p_actor app.account_profiles, p_class_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (select 1 from app.classes c where c.id = p_class_id and c.deleted_at is null)
     and (p_actor.account_type = 'admin'
          or app_private.class_role(p_actor.id, p_class_id) = 'teacher')
$$;

create or replace function app_private.test_results_dto(p_test app.tests, p_actor app.account_profiles)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'test', app_private.test_dto(p_test),
    'students', app_private.test_roster(p_test),
    'canEdit', p_test.deleted_at is null
      and exists (select 1 from app.classes c where c.id = p_test.class_id and c.deleted_at is null)
      and (p_actor.account_type = 'admin' or app_private.class_role(p_actor.id, p_test.class_id) is not null),
    'canPublish', p_test.deleted_at is null and app_private.can_publish(p_actor, p_test.class_id))
$$;

-------------------------------------------------------------------------------
-- Command.
-------------------------------------------------------------------------------

-- p_student_id NULL = the whole class of this test. Returns the entry grid with
-- {changed, missing: [{studentId, fullName}]}. Publishing one student needs a
-- complete result (result_incomplete). Publishing the class with no complete
-- result at all is refused (nothing_eligible) and writes nothing. Each changed
-- result gets a new version (stale grids then conflict); one audit per command.
create function api.publish_test_results(p_test_id uuid, p_student_id uuid, p_publish boolean)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_class_id uuid := (select t.class_id from app.tests t where t.id = p_test_id);
  v_actor app.account_profiles;
  v_test app.tests;
  v_result app.test_results;
  v_after app.test_results;
  v_changed jsonb := '[]';
  v_missing jsonb;
  v_already int := 0;
begin
  if v_class_id is null then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  v_actor := app_private.require_test_editor(v_class_id, p_display => true);
  if p_publish is null then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  -- Shared like result entry: a date change or archiving waits.
  select * into v_test from app.tests t where t.id = p_test_id for share;
  if v_test.deleted_at is not null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;

  if p_student_id is not null then
    select * into v_result from app.test_results x
     where x.test_id = v_test.id and x.student_id = p_student_id
       for update;
    if p_publish and (v_result.id is null or not app_private.result_complete(v_result)) then
      perform app_private.raise_api_error(409, 'result_incomplete');
    end if;
    if not p_publish and v_result.id is null then
      perform app_private.raise_api_error(404, 'not_found');
    end if;
  end if;

  -- Same order as result entry (student id).
  for v_result in
    select * from app.test_results x
     where x.test_id = v_test.id
       and (p_student_id is null or x.student_id = p_student_id)
       and x.deleted_at is null
     order by x.student_id
       for update
  loop
    if p_publish then
      if v_result.published_at is not null then
        v_already := v_already + 1;
        continue;
      end if;
      continue when not app_private.result_complete(v_result);
    else
      continue when v_result.published_at is null;
    end if;
    update app.test_results x
       set published_at = case when p_publish then now() end,
           published_by = case when p_publish then v_actor.id end,
           row_version = x.row_version + 1
     where x.id = v_result.id
    returning * into v_after;
    perform app_private.record_version('test_result', v_after.id, v_after.row_version,
      app_private.result_snapshot(v_after), v_actor.id);
    v_changed := v_changed || jsonb_build_array(jsonb_build_object(
      'result_id', v_after.id, 'student_id', v_after.student_id));
  end loop;

  -- Students of the roster left out because their result is missing or incomplete.
  if p_publish and p_student_id is null then
    select coalesce(jsonb_agg(jsonb_build_object('studentId', s.id, 'fullName', s.full_name)
                              order by s.name_key, s.id), '[]')
      into v_missing
      from app.students s
      left join app.test_results x on x.student_id = s.id and x.test_id = v_test.id
     where s.id in (select app_private.test_roster_ids(v_test))
       and (x.id is null or x.published_at is null)
       and (x.id is null or not app_private.result_complete(x));
    if jsonb_array_length(v_changed) = 0 and v_already = 0 then
      perform app_private.raise_api_error(409, 'nothing_eligible');
    end if;
  end if;

  if jsonb_array_length(v_changed) > 0 then
    perform app_private.write_audit(v_actor.id, 'app',
      case when p_publish then 'test_result.publish' else 'test_result.unpublish' end,
      jsonb_strip_nulls(jsonb_build_object('class_id', v_class_id, 'test_id', v_test.id,
        'student_id', p_student_id)),
      jsonb_strip_nulls(jsonb_build_object(
        'scope', case when p_student_id is null then 'class' else 'student' end,
        'before', jsonb_build_object('published', not p_publish),
        'after', jsonb_build_object('published', p_publish),
        'results', v_changed,
        'missing', v_missing)));
  end if;
  return app_private.test_results_dto(v_test, v_actor) || jsonb_build_object(
    'changed', jsonb_array_length(v_changed),
    'missing', coalesce(v_missing, '[]'));
end
$$;

revoke all on function
  app_private.can_publish(app.account_profiles, uuid)
  from public, anon, authenticated;
revoke all on function api.publish_test_results(uuid, uuid, boolean) from public, anon;
grant execute on function api.publish_test_results(uuid, uuid, boolean) to authenticated;
