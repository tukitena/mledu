-- A preview of one class must not be invalidated by unrelated classes or staff.
-- Include the class, its reservations/patterns, rooms mentioned in the command,
-- and the other assignments/sessions of its staff. Apply still checks the final
-- room exclusion and current permissions, even when the fingerprint matches.
-- Centre-wide holiday previews intentionally retain a centre-wide scope.
create or replace function app_private.schedule_fingerprint(p_class_id uuid,p_change jsonb) returns text
language sql stable set search_path = '' as $$
  with own_staff as (
    select distinct account_id from app.class_assignments where class_id=p_class_id
  ), related_classes as (
    select p_class_id id where p_class_id is not null
    union select class_id from app.class_assignments where account_id in (select account_id from own_staff)
  ), room_ids as (
    select room_id id from app.class_sessions where class_id=p_class_id and room_id is not null
    union select (s.slot->>'roomId')::uuid from app.weekly_schedules w
      cross join lateral jsonb_array_elements(w.slots) s(slot)
      where w.class_id=p_class_id and s.slot->>'roomId' is not null
    union select (j.value#>>'{}')::uuid from jsonb_path_query(p_change,'$.**.roomId') j(value)
      where jsonb_typeof(j.value)='string'
  )
  select md5(jsonb_build_array(p_class_id,p_change,
    (select jsonb_agg(to_jsonb(x) order by id) from app.class_sessions x
      where p_class_id is null or class_id in (select id from related_classes) or room_id in (select id from room_ids)),
    (select jsonb_agg(to_jsonb(x) order by revision) from app.weekly_schedules x
      where p_class_id is null or class_id=p_class_id),
    (select jsonb_agg(to_jsonb(x) order by day) from app.holidays x),
    (select jsonb_agg(to_jsonb(x) order by id) from app.classes x
      where p_class_id is null or id in (select id from related_classes)),
    (select jsonb_agg(to_jsonb(x) order by id) from app.class_assignments x
      where p_class_id is null or class_id=p_class_id or account_id in (select account_id from own_staff)),
    (select jsonb_agg(to_jsonb(x) order by id) from app.rooms x
      where p_class_id is null or id in (select id from room_ids)),
    (select jsonb_agg(to_jsonb(x) order by id) from app.sites x
      where p_class_id is null or id in (select site_id from app.rooms where id in (select id from room_ids)))
  )::text)
$$;
revoke all on function app_private.schedule_fingerprint(uuid,jsonb) from public,anon,authenticated;
