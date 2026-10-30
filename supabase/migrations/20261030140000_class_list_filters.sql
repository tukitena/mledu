-- CAT-01, SCHED-03/05: display-name length, then deterministic lexical order.

create or replace function api.list_catalog_entries(p_kind text, p_include_archived boolean default false)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_account();
  v_kind text := app_private.check_catalog_kind(p_kind);
begin
  if coalesce(p_include_archived, false) and v_actor.account_type <> 'admin' then
    perform app_private.raise_api_error(403, 'forbidden');
  end if;
  return coalesce((
    select jsonb_agg(app_private.catalog_entry_dto(e) order by char_length(e.name), e.name_key collate "C", e.name collate "C", e.id)
      from app.catalog_entries e
     where e.kind = v_kind
       and (coalesce(p_include_archived, false) or e.deleted_at is null)
  ), '[]');
end
$$;

create or replace function api.list_sites(p_include_archived boolean default false)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_account();
begin
  if coalesce(p_include_archived, false) and v_actor.account_type not in ('admin', 'receptionist') then
    perform app_private.raise_api_error(403, 'forbidden');
  end if;
  return coalesce((
    select jsonb_agg(app_private.site_dto(s) order by char_length(s.name), s.name_key collate "C", s.name collate "C", s.id)
      from app.sites s
     where coalesce(p_include_archived, false) or s.deleted_at is null
  ), '[]');
end
$$;

create or replace function api.list_rooms(p_site_id uuid default null, p_include_archived boolean default false)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_account();
begin
  if coalesce(p_include_archived, false) and v_actor.account_type not in ('admin', 'receptionist') then
    perform app_private.raise_api_error(403, 'forbidden');
  end if;
  return coalesce((
    select jsonb_agg(app_private.room_dto(r)
             order by char_length(r.name), r.name_key collate "C", r.name collate "C", r.id)
      from app.rooms r
      join app.sites s on s.id = r.site_id
     where (p_site_id is null or r.site_id = p_site_id)
       and (coalesce(p_include_archived, false) or (r.deleted_at is null and s.deleted_at is null))
  ), '[]');
end
$$;

-- CLASS-03: derive every option from the authorized set before applying filters.
drop function api.list_classes(text,boolean,integer,integer,text);
create function api.list_classes(
  p_search text default null,
  p_deleted boolean default false,
  p_limit integer default 20,
  p_offset integer default 0,
  p_school_year text default 'all',
  p_grade_id uuid default null,
  p_subject_id uuid default null,
  p_status text default 'all',
  p_staff_id uuid default null
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
  v_today date := app_private.business_date(now());
  v_result jsonb;
begin
  if p_school_year is null or (p_school_year not in ('all', 'none')
    and (p_school_year !~ '^[1-9][0-9]{3}$' or p_school_year > '9998'))
    or p_status is null or p_status not in ('all','open','closed','upcoming','running','ended')
    or p_limit is null or p_offset is null or p_limit not between 1 and 100
    or p_offset < 0 or char_length(coalesce(p_search, '')) > 200 then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  if coalesce(p_deleted, false) and not v_manager then
    perform app_private.raise_api_error(403, 'forbidden');
  end if;

  with readable as materialized (
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
      and (p_grade_id is null or (r.c).grade_id = p_grade_id)
      and (p_subject_id is null or (r.c).subject_id = p_subject_id)
      and (p_status = 'all' or (r.c).admin_state::text = p_status
        or (p_status = 'upcoming' and v_today < (r.c).start_date)
        or (p_status = 'running' and v_today between (r.c).start_date and (r.c).end_date)
        or (p_status = 'ended' and v_today > (r.c).end_date))
      and (p_staff_id is null or exists (
        select 1 from app.class_assignments a
         where a.class_id = (r.c).id and a.account_id = p_staff_id
           and a.effective_period @> now()))
  )
  select jsonb_build_object(
    'schoolYears', coalesce((select jsonb_agg(y.year order by y.year desc)
      from (select distinct (r.c).school_year_start as year from readable r
            where (r.c).school_year_start is not null) y), '[]'::jsonb),
    'filterOptions', jsonb_build_object(
      'grades', coalesce((select jsonb_agg(app_private.catalog_ref(e.id)
          order by char_length(e.name), e.name_key collate "C", e.name collate "C", e.id)
        from app.catalog_entries e where e.id in (select (r.c).grade_id from readable r)), '[]'::jsonb),
      'subjects', coalesce((select jsonb_agg(app_private.catalog_ref(e.id)
          order by char_length(e.name), e.name_key collate "C", e.name collate "C", e.id)
        from app.catalog_entries e where e.id in (select (r.c).subject_id from readable r)), '[]'::jsonb),
      'staff', coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'fullName',p.full_name)
          order by char_length(p.full_name), app_private.name_key(p.full_name) collate "C", p.full_name collate "C", p.id)
        from app.account_profiles p where exists (
          select 1 from app.class_assignments a
           where a.account_id = p.id and a.effective_period @> now()
             and a.class_id in (select (r.c).id from readable r))), '[]'::jsonb)
    ),
    'total', (select count(*) from matching),
    'items', coalesce((
      select jsonb_agg(app_private.class_dto(p.c)
        order by char_length((p.c).name), (p.c).name_key collate "C", (p.c).name collate "C", (p.c).id)
        from (select m.c from matching m
          order by char_length((m.c).name), (m.c).name_key collate "C", (m.c).name collate "C", (m.c).id
          limit p_limit offset p_offset) p
    ), '[]'::jsonb)
  ) into v_result;
  return v_result;
end
$$;

revoke all on function api.list_classes(text,boolean,integer,integer,text,uuid,uuid,text,uuid) from public, anon;
grant execute on function api.list_classes(text,boolean,integer,integer,text,uuid,uuid,text,uuid) to authenticated;
notify pgrst, 'reload schema';
