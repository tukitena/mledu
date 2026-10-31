-- GĐ 5, sixth feature: comments (COMMENT-01-03) and their publication (ACAD-01).
--
-- A comment is plain text of at most 1,000 characters for one student, either
-- on a test (one per student and test) or in a comment batch of the class (one
-- per student and batch; a batch has only a name). Comments have their own
-- publication, independent of scores and of other tests/batches. Admin and
-- current teachers/assistants enter comments; only Admin and current teachers
-- publish, unpublish, archive or restore a batch. A published comment is locked
-- until it is unpublished. Archiving a batch unpublishes its comments in the
-- same transaction (the state before is kept in history); restoring brings
-- everything back unpublished, with the same ids.
--
-- commented_at is the system time the current text was first written (kept by
-- edits, set again when a cleared comment is written again). It is the history
-- filter of COMMENT-02; batches have no date of their own.

-------------------------------------------------------------------------------
-- Tables.
-------------------------------------------------------------------------------

create table app.comment_batches (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references app.classes (id),
  -- Duplicate names are allowed in a class (TEST-05 rule shared with batches).
  name text not null,
  name_key text not null,
  row_version bigint not null default 1,
  created_at timestamptz not null default now(),
  created_by uuid not null references app.account_profiles (id),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  deleted_by uuid references app.account_profiles (id),
  deleted_reason text,
  constraint comment_batches_name_check check (
    name = btrim(name) and name is nfc normalized and char_length(name) between 1 and 200
  ),
  constraint comment_batches_name_key_check check (name_key = app_private.name_key(name)),
  constraint comment_batches_row_version_check check (row_version >= 1),
  constraint comment_batches_deleted_check check (
    (deleted_at is null and deleted_by is null and deleted_reason is null)
    or (deleted_at is not null and deleted_by is not null
        and char_length(deleted_reason) between 1 and 1000)
  )
);

create index comment_batches_class_idx on app.comment_batches (class_id, created_at desc);

comment on table app.comment_batches is
  'Comment batch of a class (COMMENT-02): a name only, independent of tests.';

create table app.comments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references app.students (id),
  test_id uuid references app.tests (id),
  batch_id uuid references app.comment_batches (id),
  -- NULL once cleared; writing again reuses the same row.
  body text,
  commented_at timestamptz,
  published_at timestamptz,
  published_by uuid references app.account_profiles (id),
  row_version bigint not null default 1,
  created_at timestamptz not null default now(),
  created_by uuid not null references app.account_profiles (id),
  updated_at timestamptz not null default now(),
  updated_by uuid not null references app.account_profiles (id),
  constraint comments_target_check check (num_nonnulls(test_id, batch_id) = 1),
  constraint comments_student_test_key unique (student_id, test_id),
  constraint comments_student_batch_key unique (student_id, batch_id),
  -- Plain text: NFC, trimmed, 1 to 1,000 characters (counted, never cut).
  constraint comments_body_check check (
    body is null
    or (body = btrim(body) and body is nfc normalized and char_length(body) between 1 and 1000)
  ),
  constraint comments_state_check check (
    (body is null) = (commented_at is null)
    and (published_at is null) = (published_by is null)
    and (body is not null or published_at is null)
  ),
  constraint comments_row_version_check check (row_version >= 1)
);

create index comments_test_idx on app.comments (test_id) where test_id is not null;
create index comments_batch_idx on app.comments (batch_id) where batch_id is not null;

comment on table app.comments is
  'Plain-text comment of a student on a test or in a batch (COMMENT-01), published on its own.';

create trigger comment_batches_no_delete
  before delete on app.comment_batches
  for each row execute function app_private.reject_change();
create trigger comment_batches_no_truncate
  before truncate on app.comment_batches
  for each statement execute function app_private.reject_change();
create trigger comments_no_delete
  before delete on app.comments
  for each row execute function app_private.reject_change();
create trigger comments_no_truncate
  before truncate on app.comments
  for each statement execute function app_private.reject_change();

alter table app.comment_batches enable row level security;
alter table app.comments enable row level security;
revoke all on table app.comment_batches, app.comments from public, anon, authenticated;

-------------------------------------------------------------------------------
-- Snapshots and DTOs (packages/contracts/src/comments.ts).
-------------------------------------------------------------------------------

create function app_private.comment_snapshot(p_comment app.comments)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'student_id', p_comment.student_id,
    'test_id', p_comment.test_id,
    'batch_id', p_comment.batch_id,
    'body', p_comment.body,
    'commented_at', p_comment.commented_at,
    'published_at', p_comment.published_at,
    'published_by', p_comment.published_by
  )
$$;

create function app_private.comment_dto(p_comment app.comments)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_comment.id,
    'body', p_comment.body,
    'commentedAt', p_comment.commented_at,
    'published', p_comment.published_at is not null,
    'publishedAt', p_comment.published_at,
    'publishedByName', (select b.full_name from app.account_profiles b where b.id = p_comment.published_by),
    'rowVersion', p_comment.row_version,
    'updatedAt', p_comment.updated_at,
    'updatedByName', a.full_name
  )
    from app.account_profiles a
   where a.id = p_comment.updated_by
$$;

create function app_private.comment_batch_snapshot(p_batch app.comment_batches)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'class_id', p_batch.class_id,
    'name', p_batch.name,
    'deleted_at', p_batch.deleted_at,
    'deleted_by', p_batch.deleted_by,
    'deleted_reason', p_batch.deleted_reason
  )
$$;

create function app_private.comment_batch_dto(p_batch app.comment_batches)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_batch.id,
    'classId', p_batch.class_id,
    'name', p_batch.name,
    'commentCount', (select count(*) from app.comments x
                      where x.batch_id = p_batch.id and x.body is not null),
    'publishedCount', (select count(*) from app.comments x
                        where x.batch_id = p_batch.id and x.published_at is not null),
    'deleted', p_batch.deleted_at is not null,
    'deletedAt', p_batch.deleted_at,
    'deletedReason', p_batch.deleted_reason,
    'createdAt', p_batch.created_at,
    'createdByName', a.full_name,
    'updatedAt', p_batch.updated_at,
    'rowVersion', p_batch.row_version
  )
    from app.account_profiles a
   where a.id = p_batch.created_by
$$;

-------------------------------------------------------------------------------
-- Rosters. Test: participation meeting the test day (as results). Batch: a
-- participation in effect now. Students already holding a comment stay listed.
-------------------------------------------------------------------------------

create function app_private.test_day_participant(p_test app.tests, p_student_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1 from app.class_students r
      join app.participations p on p.class_student_id = r.id
     where r.class_id = p_test.class_id and r.student_id = p_student_id
       and p.effective_period && tstzrange(app_private.day_start(p_test.test_on),
                                           app_private.day_start(p_test.test_on + 1), '[)'))
$$;

create function app_private.current_participant(p_class_id uuid, p_student_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1 from app.class_students r
      join app.participations p on p.class_student_id = r.id
     where r.class_id = p_class_id and r.student_id = p_student_id
       and r.deleted_at is null
       and p.effective_period @> now())
$$;

create function app_private.comment_roster_ids(p_test_id uuid, p_batch_id uuid)
returns setof uuid
language sql
stable
set search_path = ''
as $$
  select r.student_id
    from app.tests t
    join app.class_students r on r.class_id = t.class_id
    join app.participations p on p.class_student_id = r.id
   where t.id = p_test_id
     and p.effective_period && tstzrange(app_private.day_start(t.test_on),
                                         app_private.day_start(t.test_on + 1), '[)')
  union
  select r.student_id
    from app.comment_batches b
    join app.class_students r on r.class_id = b.class_id and r.deleted_at is null
    join app.participations p on p.class_student_id = r.id
   where b.id = p_batch_id and p.effective_period @> now()
  union
  select x.student_id from app.comments x
   where x.body is not null
     and (x.test_id = p_test_id or x.batch_id = p_batch_id)
$$;

-- Comments of one test or one batch with the caller's rights.
create function app_private.comments_dto(p_test_id uuid, p_batch_id uuid, p_actor app.account_profiles)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_class_id uuid;
  v_target jsonb;
  v_open boolean;
begin
  if p_test_id is not null then
    select t.class_id, jsonb_build_object('kind', 'test', 'id', t.id, 'name', t.name,
             'testOn', t.test_on, 'deleted', t.deleted_at is not null),
           t.deleted_at is null
      into v_class_id, v_target, v_open
      from app.tests t where t.id = p_test_id;
  else
    select b.class_id, jsonb_build_object('kind', 'batch', 'id', b.id, 'name', b.name,
             'testOn', null, 'deleted', b.deleted_at is not null),
           b.deleted_at is null
      into v_class_id, v_target, v_open
      from app.comment_batches b where b.id = p_batch_id;
  end if;
  v_open := v_open and exists (select 1 from app.classes c where c.id = v_class_id and c.deleted_at is null);
  return jsonb_build_object(
    'target', v_target,
    'students', coalesce((
      select jsonb_agg(jsonb_build_object(
               'studentId', s.id,
               'code', s.code,
               'fullName', s.full_name,
               'comment', case when x.body is not null then app_private.comment_dto(x) end)
             order by s.name_key, s.id)
        from app.students s
        left join app.comments x on x.student_id = s.id
             and (x.test_id = p_test_id or x.batch_id = p_batch_id)
       where s.id in (select app_private.comment_roster_ids(p_test_id, p_batch_id))), '[]'),
    'canEdit', v_open and (p_actor.account_type = 'admin'
                           or app_private.class_role(p_actor.id, v_class_id) is not null),
    'canPublish', v_open and app_private.can_publish(p_actor, v_class_id));
end
$$;

-- Resolves a target ('test' | 'batch'), returning its class; 404 when unknown.
create function app_private.comment_target_class(p_kind text, p_id uuid)
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_class_id uuid;
begin
  if p_kind = 'test' then
    select t.class_id into v_class_id from app.tests t where t.id = p_id;
  elsif p_kind = 'batch' then
    select b.class_id into v_class_id from app.comment_batches b where b.id = p_id;
  else
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  if v_class_id is null then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  return v_class_id;
end
$$;

-- Locks the target (shared: comments may be saved together, while archiving
-- or a date change waits) and refuses archived ones.
create function app_private.lock_comment_target(p_kind text, p_id uuid)
returns void
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_deleted timestamptz;
begin
  if p_kind = 'test' then
    select t.deleted_at into v_deleted from app.tests t where t.id = p_id for share;
  else
    select b.deleted_at into v_deleted from app.comment_batches b where b.id = p_id for share;
  end if;
  if v_deleted is not null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
end
$$;

-------------------------------------------------------------------------------
-- Batches (COMMENT-02/03).
-------------------------------------------------------------------------------

create function api.list_comment_batches(p_class_id uuid, p_include_archived boolean)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_test_reader(p_class_id);
  v_open boolean := exists (select 1 from app.classes c where c.id = p_class_id and c.deleted_at is null);
begin
  return jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(app_private.comment_batch_dto(b) order by b.created_at desc, b.id)
        from app.comment_batches b
       where b.class_id = p_class_id and (coalesce(p_include_archived, false) or b.deleted_at is null)
    ), '[]'),
    'canEdit', v_open and (v_actor.account_type = 'admin'
                           or app_private.class_role(v_actor.id, p_class_id) is not null),
    'canManage', app_private.can_publish(v_actor, p_class_id));
end
$$;

create function api.create_comment_batch(p_class_id uuid, p_name text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_test_editor(p_class_id);
  v_name text := app_private.clean_text(p_name, 200);
  v_batch app.comment_batches;
begin
  insert into app.comment_batches (class_id, name, name_key, created_by)
  values (p_class_id, v_name, app_private.name_key(v_name), v_actor.id)
  returning * into v_batch;
  perform app_private.record_change('comment_batch', v_batch.id, v_batch.row_version, null,
    app_private.comment_batch_snapshot(v_batch), v_actor.id, 'comment_batch.create',
    jsonb_build_object('class_id', p_class_id, 'comment_batch_id', v_batch.id));
  return app_private.comment_batch_dto(v_batch);
end
$$;

create function app_private.lock_comment_batch(p_id uuid, p_expected_version bigint)
returns app.comment_batches
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_batch app.comment_batches;
begin
  select * into v_batch from app.comment_batches b where b.id = p_id for update;
  if not found then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  if p_expected_version is null or v_batch.row_version <> p_expected_version then
    perform app_private.raise_api_error(409, 'version_conflict');
  end if;
  return v_batch;
end
$$;

-- The name may change while comments are published; nothing else changes.
create function api.update_comment_batch(p_id uuid, p_name text, p_expected_version bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_class_id uuid := app_private.comment_target_class('batch', p_id);
  v_actor app.account_profiles := app_private.require_test_editor(v_class_id);
  v_name text := app_private.clean_text(p_name, 200);
  v_before app.comment_batches;
  v_after app.comment_batches;
begin
  v_before := app_private.lock_comment_batch(p_id, p_expected_version);
  if v_before.deleted_at is not null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
  if v_before.name = v_name then
    return app_private.comment_batch_dto(v_before);
  end if;
  update app.comment_batches b
     set name = v_name, name_key = app_private.name_key(v_name),
         row_version = b.row_version + 1, updated_at = now()
   where b.id = p_id
  returning * into v_after;
  perform app_private.record_change('comment_batch', v_after.id, v_after.row_version,
    app_private.comment_batch_snapshot(v_before), app_private.comment_batch_snapshot(v_after),
    v_actor.id, 'comment_batch.update',
    jsonb_build_object('class_id', v_class_id, 'comment_batch_id', v_after.id));
  return app_private.comment_batch_dto(v_after);
end
$$;

-- Unpublishes every published comment of a target in use, keeping a version
-- of each with the state before. Returns [{comment_id, student_id}].
create function app_private.unpublish_comments(p_test_id uuid, p_batch_id uuid, p_actor_id uuid)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_comment app.comments;
  v_changed jsonb := '[]';
begin
  for v_comment in
    select * from app.comments x
     where (x.test_id = p_test_id or x.batch_id = p_batch_id) and x.published_at is not null
     order by x.student_id
       for update
  loop
    update app.comments x
       set published_at = null, published_by = null, row_version = x.row_version + 1
     where x.id = v_comment.id
    returning * into v_comment;
    perform app_private.record_version('comment', v_comment.id, v_comment.row_version,
      app_private.comment_snapshot(v_comment), p_actor_id);
    v_changed := v_changed || jsonb_build_array(jsonb_build_object(
      'comment_id', v_comment.id, 'student_id', v_comment.student_id));
  end loop;
  return v_changed;
end
$$;

-- COMMENT-03: Admin or a current teacher; comments are unpublished first, in
-- the same transaction, and kept with their text and history.
create function api.archive_comment_batch(p_id uuid, p_reason text, p_expected_version bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_class_id uuid := app_private.comment_target_class('batch', p_id);
  v_actor app.account_profiles := app_private.require_test_editor(v_class_id, p_display => true);
  v_reason text := app_private.clean_text(p_reason, 1000);
  v_before app.comment_batches;
  v_after app.comment_batches;
  v_unpublished jsonb;
begin
  v_before := app_private.lock_comment_batch(p_id, p_expected_version);
  if v_before.deleted_at is not null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
  v_unpublished := app_private.unpublish_comments(null, v_before.id, v_actor.id);
  update app.comment_batches b
     set deleted_at = now(), deleted_by = v_actor.id, deleted_reason = v_reason,
         row_version = b.row_version + 1, updated_at = now()
   where b.id = p_id
  returning * into v_after;
  perform app_private.record_version('comment_batch', v_after.id, v_after.row_version,
    app_private.comment_batch_snapshot(v_after), v_actor.id, v_reason);
  perform app_private.write_audit(v_actor.id, 'app', 'comment_batch.archive',
    jsonb_build_object('class_id', v_class_id, 'comment_batch_id', v_after.id),
    jsonb_build_object('before', app_private.comment_batch_snapshot(v_before),
      'after', app_private.comment_batch_snapshot(v_after), 'reason', v_reason,
      'unpublished_comments', v_unpublished));
  return app_private.comment_batch_dto(v_after);
end
$$;

-- Same ids and texts; everything stays unpublished until published again.
create function api.restore_comment_batch(p_id uuid, p_expected_version bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_class_id uuid := app_private.comment_target_class('batch', p_id);
  v_actor app.account_profiles := app_private.require_test_editor(v_class_id, p_display => true);
  v_before app.comment_batches;
  v_after app.comment_batches;
begin
  v_before := app_private.lock_comment_batch(p_id, p_expected_version);
  if v_before.deleted_at is null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
  update app.comment_batches b
     set deleted_at = null, deleted_by = null, deleted_reason = null,
         row_version = b.row_version + 1, updated_at = now()
   where b.id = p_id
  returning * into v_after;
  perform app_private.record_change('comment_batch', v_after.id, v_after.row_version,
    app_private.comment_batch_snapshot(v_before), app_private.comment_batch_snapshot(v_after),
    v_actor.id, 'comment_batch.restore',
    jsonb_build_object('class_id', v_class_id, 'comment_batch_id', v_after.id));
  return app_private.comment_batch_dto(v_after);
end
$$;

-------------------------------------------------------------------------------
-- Comments (COMMENT-01) of a target: p_kind 'test' or 'batch'.
-------------------------------------------------------------------------------

create function api.get_comments(p_kind text, p_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_class_id uuid := app_private.comment_target_class(p_kind, p_id);
  v_actor app.account_profiles := app_private.require_test_reader(v_class_id);
begin
  return app_private.comments_dto(case when p_kind = 'test' then p_id end,
                                  case when p_kind = 'batch' then p_id end, v_actor);
end
$$;

-- Items: {studentId, expectedVersion (null when no comment in use), body:
-- text | null to clear}. One transaction and one audit; published comments
-- are locked (ACAD-01); unchanged items write nothing.
create function api.save_comments(p_kind text, p_id uuid, p_items jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_class_id uuid := app_private.comment_target_class(p_kind, p_id);
  v_actor app.account_profiles;
  v_test_id uuid := case when p_kind = 'test' then p_id end;
  v_batch_id uuid := case when p_kind = 'batch' then p_id end;
  v_test app.tests;
  v_item jsonb;
  v_student_id uuid;
  v_body text;
  v_before app.comments;
  v_after app.comments;
  v_in_use boolean;
  v_before_list jsonb := '[]';
  v_after_list jsonb := '[]';
begin
  v_actor := app_private.require_test_editor(v_class_id);
  perform app_private.lock_comment_target(p_kind, p_id);
  select * into v_test from app.tests t where t.id = v_test_id;
  if jsonb_typeof(p_items) is distinct from 'array'
    or jsonb_array_length(p_items) not between 1 and 1000
    or exists (select 1 from jsonb_array_elements(p_items) x where jsonb_typeof(x) <> 'object'
                  or not (x ? 'studentId') or not (x ? 'body') or not (x ? 'expectedVersion')
                  or jsonb_typeof(x -> 'body') not in ('string', 'null')
                  or jsonb_typeof(x -> 'expectedVersion') not in ('number', 'null'))
    or (select count(distinct x ->> 'studentId') from jsonb_array_elements(p_items) x)
       <> jsonb_array_length(p_items)
  then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;

  for v_item in
    select x from jsonb_array_elements(p_items) x order by x ->> 'studentId'
  loop
    begin
      v_student_id := (v_item ->> 'studentId')::uuid;
    exception when invalid_text_representation then
      perform app_private.raise_api_error(400, 'validation_failed');
    end;
    v_body := case when v_item -> 'body' = 'null'::jsonb then null
                   else app_private.clean_optional_text(v_item ->> 'body', 1000) end;

    select * into v_before from app.comments x
     where x.student_id = v_student_id
       and (x.test_id = v_test_id or x.batch_id = v_batch_id)
       for update;
    v_in_use := v_before.id is not null and v_before.body is not null;
    -- Test: participation on the test day. Batch: in effect now, or already holding one.
    if not v_in_use and not (case when v_test_id is not null
                                  then app_private.test_day_participant(v_test, v_student_id)
                                  else app_private.current_participant(v_class_id, v_student_id) end)
    then
      perform app_private.raise_api_error(400, 'validation_failed');
    end if;
    if (v_item -> 'expectedVersion' = 'null'::jsonb and v_in_use)
      or (v_item -> 'expectedVersion' <> 'null'::jsonb
          and (v_before.id is null or v_before.row_version <> (v_item ->> 'expectedVersion')::bigint))
    then
      perform app_private.raise_api_error(409, 'version_conflict');
    end if;
    if v_before.published_at is not null then
      perform app_private.raise_api_error(409, 'comment_published');
    end if;
    continue when v_before.body is not distinct from v_body
      or (v_body is null and not v_in_use);

    if v_before.id is null then
      insert into app.comments (student_id, test_id, batch_id, body, commented_at, created_by, updated_by)
      values (v_student_id, v_test_id, v_batch_id, v_body, now(), v_actor.id, v_actor.id)
      returning * into v_after;
    else
      update app.comments x
         set body = v_body,
             commented_at = case when v_body is null then null
                                 else coalesce(x.commented_at, now()) end,
             row_version = x.row_version + 1, updated_at = now(), updated_by = v_actor.id
       where x.id = v_before.id
      returning * into v_after;
    end if;
    perform app_private.record_version('comment', v_after.id, v_after.row_version,
      app_private.comment_snapshot(v_after), v_actor.id);
    v_before_list := v_before_list || jsonb_build_array(jsonb_build_object(
      'comment_id', v_after.id, 'student_id', v_student_id, 'body',
      case when v_in_use then v_before.body end));
    v_after_list := v_after_list || jsonb_build_array(jsonb_build_object(
      'comment_id', v_after.id, 'student_id', v_student_id, 'body', v_after.body));
  end loop;

  if jsonb_array_length(v_after_list) > 0 then
    perform app_private.write_audit(v_actor.id, 'app', 'comment.save',
      jsonb_strip_nulls(jsonb_build_object('class_id', v_class_id, 'test_id', v_test_id,
        'comment_batch_id', v_batch_id)),
      jsonb_build_object('before', v_before_list, 'after', v_after_list));
  end if;
  return app_private.comments_dto(v_test_id, v_batch_id, v_actor);
end
$$;

-- ACAD-01 for comments: one student (p_student_id) or the whole target. Only
-- comments with text are published; the class publish lists students without
-- one and refuses when nobody has one (nothing_eligible). Scores are untouched.
create function api.publish_comments(p_kind text, p_id uuid, p_student_id uuid, p_publish boolean)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_class_id uuid := app_private.comment_target_class(p_kind, p_id);
  v_actor app.account_profiles;
  v_test_id uuid := case when p_kind = 'test' then p_id end;
  v_batch_id uuid := case when p_kind = 'batch' then p_id end;
  v_comment app.comments;
  v_changed jsonb := '[]';
  v_missing jsonb;
  v_already int := 0;
begin
  v_actor := app_private.require_test_editor(v_class_id, p_display => true);
  if p_publish is null then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  perform app_private.lock_comment_target(p_kind, p_id);
  if p_student_id is not null and p_publish and not exists (
    select 1 from app.comments x
     where x.student_id = p_student_id and (x.test_id = v_test_id or x.batch_id = v_batch_id)
       and x.body is not null)
  then
    perform app_private.raise_api_error(409, 'nothing_eligible');
  end if;

  for v_comment in
    select * from app.comments x
     where (x.test_id = v_test_id or x.batch_id = v_batch_id)
       and (p_student_id is null or x.student_id = p_student_id)
       and x.body is not null
     order by x.student_id
       for update
  loop
    if p_publish then
      if v_comment.published_at is not null then
        v_already := v_already + 1;
        continue;
      end if;
    else
      continue when v_comment.published_at is null;
    end if;
    update app.comments x
       set published_at = case when p_publish then now() end,
           published_by = case when p_publish then v_actor.id end,
           row_version = x.row_version + 1
     where x.id = v_comment.id
    returning * into v_comment;
    perform app_private.record_version('comment', v_comment.id, v_comment.row_version,
      app_private.comment_snapshot(v_comment), v_actor.id);
    v_changed := v_changed || jsonb_build_array(jsonb_build_object(
      'comment_id', v_comment.id, 'student_id', v_comment.student_id));
  end loop;

  if p_publish and p_student_id is null then
    select coalesce(jsonb_agg(jsonb_build_object('studentId', s.id, 'fullName', s.full_name)
                              order by s.name_key, s.id), '[]')
      into v_missing
      from app.students s
     where s.id in (select app_private.comment_roster_ids(v_test_id, v_batch_id))
       and not exists (select 1 from app.comments x
                        where x.student_id = s.id and x.body is not null
                          and (x.test_id = v_test_id or x.batch_id = v_batch_id));
    if jsonb_array_length(v_changed) = 0 and v_already = 0 then
      perform app_private.raise_api_error(409, 'nothing_eligible');
    end if;
  end if;

  if jsonb_array_length(v_changed) > 0 then
    perform app_private.write_audit(v_actor.id, 'app',
      case when p_publish then 'comment.publish' else 'comment.unpublish' end,
      jsonb_strip_nulls(jsonb_build_object('class_id', v_class_id, 'test_id', v_test_id,
        'comment_batch_id', v_batch_id, 'student_id', p_student_id)),
      jsonb_strip_nulls(jsonb_build_object(
        'scope', case when p_student_id is null then 'class' else 'student' end,
        'before', jsonb_build_object('published', not p_publish),
        'after', jsonb_build_object('published', p_publish),
        'comments', v_changed,
        'missing', v_missing)));
  end if;
  return app_private.comments_dto(v_test_id, v_batch_id, v_actor) || jsonb_build_object(
    'changed', jsonb_array_length(v_changed),
    'missing', coalesce(v_missing, '[]'));
end
$$;

-------------------------------------------------------------------------------
-- TEST-05: a new test date may not leave out a student holding a result or a
-- comment of that test.
-------------------------------------------------------------------------------

create or replace function app_private.check_result_participation(p_test app.tests)
returns void
language plpgsql
stable
set search_path = ''
as $$
declare
  v_outside jsonb;
begin
  select jsonb_agg(jsonb_build_object('path', 'studentName', 'message', s.full_name)
                   order by s.name_key, s.id)
    into v_outside
    from app.students s
   where s.id in (select x.student_id from app.test_results x
                   where x.test_id = p_test.id and x.deleted_at is null
                  union
                  select c.student_id from app.comments c
                   where c.test_id = p_test.id and c.body is not null)
     and not app_private.test_day_participant(p_test, s.id);
  if v_outside is not null then
    perform app_private.raise_api_conflict('test_date_excludes_results', v_outside);
  end if;
end
$$;

-- Tests in the class list also count comments in use.
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
    'deleted', p_test.deleted_at is not null,
    'createdAt', p_test.created_at,
    'createdByName', a.full_name,
    'updatedAt', p_test.updated_at,
    'rowVersion', p_test.row_version
  )
    from app.test_config_versions c, app.account_profiles a
   where c.id = p_test.current_config_id and a.id = p_test.created_by
$$;

revoke all on function
  app_private.comment_snapshot(app.comments),
  app_private.comment_dto(app.comments),
  app_private.comment_batch_snapshot(app.comment_batches),
  app_private.comment_batch_dto(app.comment_batches),
  app_private.test_day_participant(app.tests, uuid),
  app_private.current_participant(uuid, uuid),
  app_private.comment_roster_ids(uuid, uuid),
  app_private.comments_dto(uuid, uuid, app.account_profiles),
  app_private.comment_target_class(text, uuid),
  app_private.lock_comment_target(text, uuid),
  app_private.lock_comment_batch(uuid, bigint),
  app_private.unpublish_comments(uuid, uuid, uuid)
  from public, anon, authenticated;
revoke all on function
  api.list_comment_batches(uuid, boolean),
  api.create_comment_batch(uuid, text),
  api.update_comment_batch(uuid, text, bigint),
  api.archive_comment_batch(uuid, text, bigint),
  api.restore_comment_batch(uuid, bigint),
  api.get_comments(text, uuid),
  api.save_comments(text, uuid, jsonb),
  api.publish_comments(text, uuid, uuid, boolean)
  from public, anon;
grant execute on function
  api.list_comment_batches(uuid, boolean),
  api.create_comment_batch(uuid, text),
  api.update_comment_batch(uuid, text, bigint),
  api.archive_comment_batch(uuid, text, bigint),
  api.restore_comment_batch(uuid, bigint),
  api.get_comments(text, uuid),
  api.save_comments(text, uuid, jsonb),
  api.publish_comments(text, uuid, uuid, boolean)
  to authenticated;
