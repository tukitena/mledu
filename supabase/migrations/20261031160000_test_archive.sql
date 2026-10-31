-- GĐ 5, seventh feature: archiving and restoring a whole test (TEST-06).
--
-- Admin or a current teacher (never assistants or receptionists) archives a
-- test after seeing what it affects. In one transaction the test's results
-- and test comments are unpublished (the state before is kept in their
-- history), then the test is archived with a reason. Scores, components,
-- Absent, IELTS inputs and comments stay as they were. Restoring reuses the
-- same test and rows; everything stays unpublished until someone publishes
-- again. Other tests and comment batches are not touched.

-------------------------------------------------------------------------------
-- DTO: what archiving affects, and the archive state.
-------------------------------------------------------------------------------

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
    'commentCount', (select count(*) from app.comments x
                      where x.test_id = p_test.id and x.body is not null),
    'publishedCommentCount', (select count(*) from app.comments x
                               where x.test_id = p_test.id and x.published_at is not null),
    'deleted', p_test.deleted_at is not null,
    'deletedAt', p_test.deleted_at,
    'deletedReason', p_test.deleted_reason,
    'createdAt', p_test.created_at,
    'createdByName', a.full_name,
    'updatedAt', p_test.updated_at,
    'rowVersion', p_test.row_version
  )
    from app.test_config_versions c, app.account_profiles a
   where c.id = p_test.current_config_id and a.id = p_test.created_by
$$;

-- Archived tests can be listed for restoring; the rights say who may archive.
drop function api.list_class_tests(uuid);
create function api.list_class_tests(p_class_id uuid, p_include_archived boolean default false)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_test_reader(p_class_id);
  v_open boolean := exists (select 1 from app.classes c where c.id = p_class_id and c.deleted_at is null);
  v_role text := app_private.class_role(v_actor.id, p_class_id);
begin
  return jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(app_private.test_dto(t) order by t.test_on desc, t.created_at desc, t.id)
        from app.tests t
       where t.class_id = p_class_id
         and (coalesce(p_include_archived, false) or t.deleted_at is null)
    ), '[]'),
    'canEdit', v_open and (v_actor.account_type = 'admin' or v_role is not null),
    'canChangeDisplay', v_open and (v_actor.account_type = 'admin' or v_role = 'teacher'),
    'canArchive', app_private.can_publish(v_actor, p_class_id));
end
$$;

-------------------------------------------------------------------------------
-- Commands.
-------------------------------------------------------------------------------

-- Locks a test for archive/restore: exclusive, so result/comment entry and
-- publication (shared lock) finish first or wait and then see the new state.
create function app_private.lock_test_any(p_id uuid, p_expected_version bigint)
returns app.tests
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_test app.tests;
begin
  select * into v_test from app.tests t where t.id = p_id for update;
  if not found then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  if p_expected_version is null or v_test.row_version <> p_expected_version then
    perform app_private.raise_api_error(409, 'version_conflict');
  end if;
  return v_test;
end
$$;

create function api.archive_test(p_id uuid, p_reason text, p_expected_version bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_class_id uuid := (select t.class_id from app.tests t where t.id = p_id);
  v_actor app.account_profiles;
  v_reason text;
  v_before app.tests;
  v_after app.tests;
  v_result app.test_results;
  v_results jsonb := '[]';
  v_comments jsonb;
begin
  if v_class_id is null then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  v_actor := app_private.require_test_editor(v_class_id, p_display => true);
  v_reason := app_private.clean_text(p_reason, 1000);
  v_before := app_private.lock_test_any(p_id, p_expected_version);
  if v_before.deleted_at is not null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;

  -- Exception of ACAD-01: archiving unpublishes scores and test comments itself.
  for v_result in
    select * from app.test_results x
     where x.test_id = v_before.id and x.published_at is not null
     order by x.student_id
       for update
  loop
    update app.test_results x
       set published_at = null, published_by = null, row_version = x.row_version + 1
     where x.id = v_result.id
    returning * into v_result;
    perform app_private.record_version('test_result', v_result.id, v_result.row_version,
      app_private.result_snapshot(v_result), v_actor.id, v_reason);
    v_results := v_results || jsonb_build_array(jsonb_build_object(
      'result_id', v_result.id, 'student_id', v_result.student_id));
  end loop;
  v_comments := app_private.unpublish_comments(v_before.id, null, v_actor.id);

  update app.tests t
     set deleted_at = now(), deleted_by = v_actor.id, deleted_reason = v_reason,
         row_version = t.row_version + 1, updated_at = now()
   where t.id = v_before.id
  returning * into v_after;
  perform app_private.record_version('test', v_after.id, v_after.row_version,
    app_private.test_snapshot(v_after), v_actor.id, v_reason);
  perform app_private.write_audit(v_actor.id, 'app', 'test.archive',
    jsonb_build_object('class_id', v_class_id, 'test_id', v_after.id),
    jsonb_build_object('before', app_private.test_snapshot(v_before),
      'after', app_private.test_snapshot(v_after), 'reason', v_reason,
      'unpublished_results', v_results, 'unpublished_comments', v_comments));
  return app_private.test_dto(v_after);
end
$$;

-- Same test, results and comments; nothing is published again.
create function api.restore_test(p_id uuid, p_expected_version bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_class_id uuid := (select t.class_id from app.tests t where t.id = p_id);
  v_actor app.account_profiles;
  v_before app.tests;
  v_after app.tests;
begin
  if v_class_id is null then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  v_actor := app_private.require_test_editor(v_class_id, p_display => true);
  v_before := app_private.lock_test_any(p_id, p_expected_version);
  if v_before.deleted_at is null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
  update app.tests t
     set deleted_at = null, deleted_by = null, deleted_reason = null,
         row_version = t.row_version + 1, updated_at = now()
   where t.id = v_before.id
  returning * into v_after;
  perform app_private.record_change('test', v_after.id, v_after.row_version,
    app_private.test_snapshot(v_before), app_private.test_snapshot(v_after), v_actor.id,
    'test.restore', jsonb_build_object('class_id', v_class_id, 'test_id', v_after.id));
  return app_private.test_dto(v_after);
end
$$;

revoke all on function app_private.lock_test_any(uuid, bigint) from public, anon, authenticated;
revoke all on function
  api.list_class_tests(uuid, boolean),
  api.archive_test(uuid, text, bigint),
  api.restore_test(uuid, bigint)
  from public, anon;
grant execute on function
  api.list_class_tests(uuid, boolean),
  api.archive_test(uuid, text, bigint),
  api.restore_test(uuid, bigint)
  to authenticated;
