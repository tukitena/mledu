-- STU-04: codes remain stable internal/Excel identifiers, never a list search key.
create or replace function api.list_students(
  p_search text default null,
  p_status text default 'active',
  p_limit integer default 20,
  p_offset integer default 0
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_account();
  v_status text := coalesce(p_status, 'active');
  v_search text := nullif(btrim(coalesce(p_search, '')), '');
  v_key text := app_private.name_key(coalesce(v_search, ''));
  v_digits text;
  v_result jsonb;
begin
  if v_status not in ('active', 'deleted') or p_limit not between 1 and 100 or p_offset < 0
    or char_length(coalesce(v_search, '')) > 200
  then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  if v_status = 'deleted' and v_actor.account_type not in ('admin', 'receptionist') then
    perform app_private.raise_api_error(403, 'forbidden');
  end if;
  -- A search made of digits and phone separators also matches phone keys.
  if v_search ~ '^\+?[0-9\s.()-]{3,}$' then
    v_digits := regexp_replace(v_search, '[\s.()-]', '', 'g');
    v_digits := case
      when v_digits like '+84%' then '0' || substr(v_digits, 4)
      when v_digits like '0084%' then '0' || substr(v_digits, 5)
      else v_digits end;
  end if;

  with matching as (
    select s
      from app.students s
     where (v_status = 'active') = (s.deleted_at is null)
       and (v_search is null
            or strpos(s.name_key, v_key) > 0
            or (v_digits is not null and exists (
                  select 1 from app.student_contacts c
                   where c.student_id = s.id and strpos(c.phone, v_digits) > 0)))
  )
  select jsonb_build_object(
    'total', (select count(*) from matching),
    'items', coalesce((
      select jsonb_agg(app_private.student_dto(p.s) order by (p.s).name_key, (p.s).code)
        from (select m.s from matching m order by (m.s).name_key, (m.s).code
              limit p_limit offset p_offset) p
    ), '[]')
  ) into v_result;
  return v_result;
end
$$;

revoke all on function api.list_students(text, text, integer, integer) from public, anon;
grant execute on function api.list_students(text, text, integer, integer) to authenticated;
