-- CLASS-03: optional standard school year. Existing classes keep NULL.
-- No relation between the school year label and the operational class dates.
alter table app.classes add column school_year_start integer;
alter table app.classes add constraint classes_school_year_start_check
  check (school_year_start between 1000 and 9998);
create index classes_school_year_start_idx on app.classes (school_year_start);
comment on column app.classes.school_year_start is
  'Optional first year of YYYY–YYYY+1 (1000..9998). NULL = no school year; independent of class dates.';

create or replace function app_private.class_snapshot(p_class app.classes)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'name', p_class.name,
    'subject_id', p_class.subject_id,
    'grade_id', p_class.grade_id,
    'school_year_start', p_class.school_year_start,
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

create or replace function app_private.class_dto(p_class app.classes)
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
    'schoolYearStart', p_class.school_year_start,
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

drop function api.list_classes(text,boolean,integer,integer);
create function api.list_classes(
  p_search text default null,
  p_deleted boolean default false,
  p_limit integer default 20,
  p_offset integer default 0,
  p_school_year text default 'all'
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
  if p_school_year is null or (p_school_year not in ('all', 'none')
    and (p_school_year !~ '^[1-9][0-9]{3}$' or p_school_year > '9998')) then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  if p_limit not between 1 and 100 or p_offset < 0 or char_length(coalesce(p_search, '')) > 200 then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  if coalesce(p_deleted, false) and not v_manager then
    perform app_private.raise_api_error(403, 'forbidden');
  end if;

  with readable as (
    select c
      from app.classes c
     where (c.deleted_at is not null) = coalesce(p_deleted, false)
       and (v_manager or app_private.class_role(v_actor.id, c.id) is not null)
  ), matching as (
    select r.c from readable r
    where (v_key = '' or strpos((r.c).name_key, v_key) > 0)
      and (p_school_year = 'all'
        or (p_school_year = 'none' and (r.c).school_year_start is null)
        or (r.c).school_year_start::text = p_school_year)
  )
  select jsonb_build_object(
    'schoolYears', coalesce((select jsonb_agg(y.year order by y.year desc)
      from (select distinct (r.c).school_year_start as year from readable r
            where (r.c).school_year_start is not null) y), '[]'::jsonb),
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

drop function api.create_class(text,uuid,uuid,date,date,text);
create function api.create_class(
  p_name text,
  p_subject_id uuid,
  p_grade_id uuid,
  p_start_date date,
  p_end_date date,
  p_note text default null,
  p_school_year_start integer default null
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
  if p_school_year_start is not null and p_school_year_start not between 1000 and 9998 then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  perform app_private.check_class_catalog(p_subject_id, 'subject', null);
  perform app_private.check_class_catalog(p_grade_id, 'grade', null);

  insert into app.classes (name, name_key, subject_id, grade_id, start_date, end_date, note, school_year_start, created_by)
  values (v_name, app_private.name_key(v_name), p_subject_id, p_grade_id, p_start_date, p_end_date,
          v_note, p_school_year_start, v_actor.id)
  returning * into v_class;

  perform app_private.record_change('class', v_class.id, v_class.row_version, null,
    app_private.class_snapshot(v_class), v_actor.id, 'class.create',
    jsonb_build_object('class_id', v_class.id));
  return app_private.class_dto(v_class);
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
  p_expected_version bigint,
  p_school_year_start integer
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
  if p_school_year_start is not null and p_school_year_start not between 1000 and 9998 then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
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
         school_year_start = p_school_year_start,
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

-- Preserve the year when an older caller omits the new field. Lock before
-- reading the preserved value so concurrent writes cannot restore a stale year.
create or replace function api.update_class(
  p_id uuid, p_name text, p_subject_id uuid, p_grade_id uuid,
  p_start_date date, p_end_date date, p_note text, p_expected_version bigint
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_actor app.account_profiles := app_private.require_manager();
  v_class app.classes;
begin
  if p_expected_version is null then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  v_class := app_private.lock_class(p_id, p_expected_version);
  return api.update_class(p_id,p_name,p_subject_id,p_grade_id,p_start_date,p_end_date,
    p_note,p_expected_version,v_class.school_year_start);
end
$$;

revoke all on function api.list_classes(text,boolean,integer,integer,text),
  api.create_class(text,uuid,uuid,date,date,text,integer),
  api.update_class(uuid,text,uuid,uuid,date,date,text,bigint,integer)
  from public, anon;
grant execute on function api.list_classes(text,boolean,integer,integer,text),
  api.create_class(text,uuid,uuid,date,date,text,integer),
  api.update_class(uuid,text,uuid,uuid,date,date,text,bigint,integer)
  to authenticated;
notify pgrst, 'reload schema';
