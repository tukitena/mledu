-- GĐ4 / SCHED-01–06. Business history is permanent; audit is separate.
create table app.weekly_schedules (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references app.classes(id),
  applies_on date not null,
  slots jsonb not null check (jsonb_typeof(slots) = 'array'),
  revision bigint generated always as identity unique,
  created_at timestamptz not null default now(),
  created_by uuid not null references app.account_profiles(id)
);
create index weekly_schedules_class_idx on app.weekly_schedules(class_id, applies_on, revision);
create trigger weekly_schedules_immutable before update or delete on app.weekly_schedules
for each row execute function app_private.reject_change();

create table app.holidays (
  day date primary key,
  name text not null check (char_length(name) between 1 and 200),
  active boolean not null,
  row_version bigint not null default 1
);

create table app.class_sessions (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references app.classes(id),
  kind text not null check (kind in ('weekly','makeup')),
  original_day date not null,
  original_start time not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  room_id uuid references app.rooms(id),
  room_name text,
  site_name text,
  site_address text,
  status text not null check (status in ('scheduled','off','holiday','removed_schedule','removed_class')),
  -- A manual exception survives subsequent weekly regeneration.
  is_exception boolean not null default false,
  -- Preserve the state underneath a class closure or holiday.
  resume_status text check (resume_status in ('scheduled','off','holiday')),
  holiday_status text check (holiday_status in ('scheduled','off')),
  row_version bigint not null default 1,
  attendance_version bigint not null default 0,
  created_at timestamptz not null default now(),
  constraint sessions_time_check check (
    ends_at > starts_at and
    (starts_at at time zone 'Asia/Ho_Chi_Minh')::date = (ends_at at time zone 'Asia/Ho_Chi_Minh')::date
  ),
  constraint sessions_no_room_overlap exclude using gist
    (room_id with =, tstzrange(starts_at, ends_at, '[)') with &&)
    where (status = 'scheduled' and room_id is not null)
);
create unique index sessions_weekly_occurrence on app.class_sessions(class_id, original_day, original_start)
where kind = 'weekly';
create index sessions_class_time_idx on app.class_sessions(class_id, starts_at);

alter table app.weekly_schedules enable row level security;
alter table app.class_sessions enable row level security;
alter table app.holidays enable row level security;
revoke all on app.weekly_schedules, app.class_sessions, app.holidays from public, anon, authenticated;

-- Schedules and catalog/lifecycle commands share a lock BEFORE acquiring actor,
-- class or room locks. Exclusion remains the final DB protection. This bounded
-- centre currently favours predictable atomic bulk changes over write throughput.
create function app_private.lock_scheduling() returns void language sql volatile
set search_path = '' as $$ select pg_advisory_xact_lock(71440004) $$;

create or replace function app_private.require_manager()
returns app.account_profiles language plpgsql volatile set search_path = '' as $$
declare v_actor app.account_profiles;
begin
  perform app_private.lock_scheduling();
  v_actor := app_private.require_account(p_lock => true);
  if v_actor.account_type not in ('admin','receptionist') then
    perform app_private.raise_api_error(403,'forbidden');
  end if;
  return v_actor;
end $$;

create function app_private.require_scheduler(p_class_id uuid)
returns app.account_profiles language plpgsql volatile set search_path = '' as $$
declare v_actor app.account_profiles;
begin
  perform app_private.lock_scheduling();
  v_actor := app_private.require_account(p_lock => true);
  perform app_private.require_class_reader(p_class_id);
  if v_actor.account_type not in ('admin','receptionist') and
     app_private.class_role(v_actor.id,p_class_id) is distinct from 'teacher' then
    perform app_private.raise_api_error(403,'forbidden');
  end if;
  return v_actor;
end $$;

create function app_private.session_dto(p_row app.class_sessions) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object('id',p_row.id,'classId',p_row.class_id,
    'className',(select name from app.classes where id=p_row.class_id),
    'kind',p_row.kind,'date',app_private.business_date(p_row.starts_at),
    'startTime',to_char(p_row.starts_at at time zone 'Asia/Ho_Chi_Minh','HH24:MI'),
    'endTime',to_char(p_row.ends_at at time zone 'Asia/Ho_Chi_Minh','HH24:MI'),
    'startsAt',p_row.starts_at,'endsAt',p_row.ends_at,'roomId',p_row.room_id,
    'roomName',p_row.room_name,'siteName',p_row.site_name,'siteAddress',p_row.site_address,
    'status',p_row.status,'isException',p_row.is_exception,
    'rowVersion',p_row.row_version,'attendanceVersion',p_row.attendance_version)
$$;

-- A separate immutable entity version for every changed session, including
-- bulk regeneration, holidays and class lifecycle operations.
create function app_private.version_session() returns trigger language plpgsql
set search_path = '' as $$
begin
  if tg_op = 'UPDATE' then
    if new.starts_at is distinct from old.starts_at or new.ends_at is distinct from old.ends_at
      or new.room_id is distinct from old.room_id or new.status is distinct from old.status then
      if old.starts_at <= clock_timestamp() then
        perform app_private.raise_api_error(409,'session_started');
      end if;
    end if;
    new.row_version := old.row_version + 1;
  end if;
  return new;
end $$;
create trigger sessions_version before insert or update on app.class_sessions
for each row execute function app_private.version_session();

-- AFTER is essential: BEFORE INSERT also fires for an ON CONFLICT proposal
-- that is discarded. Only actual persisted rows may have business versions.
create function app_private.record_session_version() returns trigger language plpgsql
set search_path = '' as $$
begin
  perform app_private.record_version('class_session',new.id,new.row_version,
    to_jsonb(new),coalesce(auth.uid(),(select created_by from app.classes where id=new.class_id)));
  return new;
end $$;
create trigger sessions_history after insert or update on app.class_sessions
for each row execute function app_private.record_session_version();

create function app_private.session_location() returns trigger language plpgsql
set search_path = '' as $$
begin
  if tg_op='INSERT' or new.room_id is distinct from old.room_id or
    (new.status='scheduled' and old.status<>'scheduled') then
    if new.room_id is null then
      new.room_name := null; new.site_name := null; new.site_address := null;
    else
      select r.name,s.name,s.address into new.room_name,new.site_name,new.site_address
      from app.rooms r join app.sites s on s.id=r.site_id
      where r.id=new.room_id and r.deleted_at is null and s.deleted_at is null;
      if not found then perform app_private.raise_api_error(409,'invalid_state'); end if;
    end if;
  end if;
  return new;
end $$;
create trigger sessions_a_location before insert or update on app.class_sessions
for each row execute function app_private.session_location();

-- Keep the pre-start snapshot in step with catalog edits. Past locations never change.
create function app_private.refresh_session_locations() returns trigger language plpgsql
set search_path = '' as $$
begin
  update app.class_sessions x set room_name=r.name,site_name=s.name,site_address=s.address
  from app.rooms r join app.sites s on s.id=r.site_id
  where x.room_id=r.id and x.starts_at>clock_timestamp()
    and (x.room_name,x.site_name,x.site_address) is distinct from (r.name,s.name,s.address);
  return new;
end $$;
create trigger rooms_schedule_snapshot after update on app.rooms
for each statement execute function app_private.refresh_session_locations();
create trigger sites_schedule_snapshot after update on app.sites
for each statement execute function app_private.refresh_session_locations();

create or replace function app_private.assert_room_unused(p_room_id uuid)
returns void language plpgsql stable set search_path = '' as $$
begin
  if exists(select 1 from app.class_sessions where room_id=p_room_id and ends_at>clock_timestamp()
    and status in ('scheduled','off','holiday')) or exists (
    select 1 from app.classes c cross join lateral generate_series(
      greatest(c.start_date,app_private.business_date(clock_timestamp())),c.end_date,interval '1 day') d
    cross join lateral (select slots from app.weekly_schedules w where w.class_id=c.id
      and w.applies_on<=d::date order by w.applies_on desc,w.revision desc limit 1) w
    cross join lateral jsonb_array_elements(w.slots) slot
    where (slot->>'roomId')::uuid=p_room_id and extract(isodow from d)::int=(slot->>'weekday')::int
  ) then
    perform app_private.raise_api_conflict('room_in_use',jsonb_build_array(
      jsonb_build_object('path','roomId','message',p_room_id::text)));
  end if;
end $$;

create function app_private.rebuild_sessions(p_class app.classes, p_from date)
returns void language plpgsql volatile set search_path = '' as $$
declare v_day date; v_slots jsonb; v_slot jsonb; v_start timestamptz; v_end timestamptz;
  v_status text; v_room uuid;
begin
  if p_class.deleted_at is not null or p_class.admin_state<>'open' then return; end if;
  -- Only regular future occurrences are replaced. Exceptions/off/buoys keep identity.
  update app.class_sessions set status='removed_schedule'
  where class_id=p_class.id and kind='weekly' and not is_exception
    and starts_at>clock_timestamp() and app_private.business_date(starts_at)>=p_from
    and status in ('scheduled','holiday');
  for v_day in select d::date from generate_series(greatest(p_from,p_class.start_date),p_class.end_date,interval '1 day') d loop
    select slots into v_slots from app.weekly_schedules where class_id=p_class.id and applies_on<=v_day
      order by applies_on desc,revision desc limit 1;
    for v_slot in select value from jsonb_array_elements(coalesce(v_slots,'[]')) loop
      if (v_slot->>'weekday')::int<>extract(isodow from v_day)::int then continue; end if;
      v_start := (v_day+(v_slot->>'startTime')::time) at time zone 'Asia/Ho_Chi_Minh';
      v_end := (v_day+(v_slot->>'endTime')::time) at time zone 'Asia/Ho_Chi_Minh';
      if v_start<=clock_timestamp() then continue; end if;
      v_room := (v_slot->>'roomId')::uuid;
      v_status := case when exists(select 1 from app.holidays where day=v_day and active) then 'holiday' else 'scheduled' end;
      insert into app.class_sessions(class_id,kind,original_day,original_start,starts_at,ends_at,room_id,status)
      values(p_class.id,'weekly',v_day,(v_slot->>'startTime')::time,v_start,v_end,v_room,v_status)
      on conflict (class_id,original_day,original_start) where kind='weekly' do update
        set starts_at=excluded.starts_at, ends_at=excluded.ends_at, room_id=excluded.room_id,status=excluded.status
        where not app.class_sessions.is_exception and app.class_sessions.starts_at>clock_timestamp()
          and app.class_sessions.status='removed_schedule';
    end loop;
  end loop;
end $$;

-- Returns conflicts with safe, explicit class/session/room/time labels.
create function app_private.room_conflicts(p_class_id uuid) returns jsonb
language sql stable set search_path = '' as $$
 select coalesce(jsonb_agg(jsonb_build_object('path','roomId','message',
   c.name||' · '||coalesce(b.room_name,'')||' · '||coalesce(b.site_name,'')||' · '||
   to_char(b.starts_at at time zone 'Asia/Ho_Chi_Minh','YYYY-MM-DD HH24:MI')||'–'||
   to_char(b.ends_at at time zone 'Asia/Ho_Chi_Minh','HH24:MI'))),'[]')
 from app.class_sessions a join app.class_sessions b on a.id<>b.id and a.room_id=b.room_id
   and tstzrange(a.starts_at,a.ends_at,'[)') && tstzrange(b.starts_at,b.ends_at,'[)')
 join app.classes c on c.id=b.class_id
 where (p_class_id is null or a.class_id=p_class_id) and a.status='scheduled' and b.status='scheduled'
$$;

create function app_private.staff_conflicts(p_class_id uuid) returns jsonb
language sql stable set search_path = '' as $$
 select coalesce(jsonb_agg(distinct jsonb_build_object('accountId',p.id,'fullName',p.full_name,
   'className',c.name,
   'sessionId',case when b.class_id=p_class_id then a.id else b.id end,
   'startsAt',case when b.class_id=p_class_id then a.starts_at else b.starts_at end,
   'endsAt',case when b.class_id=p_class_id then a.ends_at else b.ends_at end)),'[]')
 from app.class_sessions a join app.class_sessions b on a.id<b.id and a.class_id<>b.class_id
   and tstzrange(a.starts_at,a.ends_at,'[)') && tstzrange(b.starts_at,b.ends_at,'[)')
 join app.class_assignments aa on aa.class_id=a.class_id and aa.effective_period @> a.starts_at
 join app.class_assignments bb on bb.class_id=b.class_id and bb.account_id=aa.account_id
   and bb.effective_period @> b.starts_at
 join app.account_profiles p on p.id=aa.account_id
 join app.classes c on c.id=case when b.class_id=p_class_id then a.class_id else b.class_id end
 where (p_class_id is null or a.class_id=p_class_id or b.class_id=p_class_id)
   and a.status='scheduled' and b.status='scheduled' and a.ends_at>clock_timestamp()
$$;

-- Fingerprint includes the inputs and current relevant state, so an old preview
-- cannot silently approve a different set of affected sessions or conflicts.
create function app_private.schedule_fingerprint(p_class_id uuid,p_change jsonb) returns text
language sql stable set search_path = '' as $$
 select md5(jsonb_build_array(p_class_id,p_change,
   (select jsonb_agg(to_jsonb(x) order by id) from app.class_sessions x),
   (select jsonb_agg(to_jsonb(x) order by revision) from app.weekly_schedules x),
   (select jsonb_agg(to_jsonb(x) order by day) from app.holidays x),
   (select jsonb_agg(to_jsonb(x) order by id) from app.classes x),
   (select jsonb_agg(to_jsonb(x) order by id) from app.class_assignments x),
   (select jsonb_agg(to_jsonb(x) order by id) from app.rooms x),
   (select jsonb_agg(to_jsonb(x) order by id) from app.sites x))::text)
$$;

-- Internal command. Used by both preview (rolled back) and confirmation.
create function app_private.add_weekly_revision(p_class_id uuid,p_day date,p_slots jsonb,p_actor uuid)
returns void language plpgsql volatile set search_path = '' as $$
declare v_slot jsonb;
begin
  if p_day is null or p_day<app_private.business_date(clock_timestamp()) or jsonb_typeof(p_slots) is distinct from 'array' then
    perform app_private.raise_api_error(400,'validation_failed');
  end if;
  for v_slot in select value from jsonb_array_elements(p_slots) loop
    if coalesce(v_slot->>'weekday','') !~ '^[1-7]$' or
      coalesce(v_slot->>'startTime','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' or
      coalesce(v_slot->>'endTime','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' or
      (v_slot->>'endTime')::time<=(v_slot->>'startTime')::time then perform app_private.raise_api_error(400,'validation_failed'); end if;
    if v_slot->>'roomId' is not null and not exists(select 1 from app.rooms r join app.sites s on s.id=r.site_id
      where r.id=(v_slot->>'roomId')::uuid and r.deleted_at is null and s.deleted_at is null) then
      perform app_private.raise_api_error(409,'invalid_state');
    end if;
  end loop;
  if exists(select 1 from jsonb_array_elements(p_slots) a group by a->>'weekday',a->>'startTime' having count(*)>1) then
    perform app_private.raise_api_error(400,'validation_failed');
  end if;
  insert into app.weekly_schedules(class_id,applies_on,slots,created_by) values(p_class_id,p_day,p_slots,p_actor);
end $$;

create function app_private.change_schedule(p_class_id uuid,p_change jsonb) returns jsonb
language plpgsql volatile set search_path = '' as $$
declare v_actor app.account_profiles; v_class app.classes; v_before app.class_sessions;
  v_session app.class_sessions; v_slot jsonb; v_day date; v_start timestamptz; v_end timestamptz;
  v_op text:=p_change->>'op'; v_token text; v_conflicts jsonb; v_impacted jsonb; v_old jsonb;
  v_holiday app.holidays; v_after_class app.classes;
begin
  perform app_private.lock_scheduling();
  v_actor:=app_private.require_account(p_lock => true);
  if v_op in ('holiday','remove_holiday') then
    if v_actor.account_type<>'admin' then perform app_private.raise_api_error(403,'forbidden'); end if;
    v_day:=(p_change->>'date')::date;
    if v_day is null then perform app_private.raise_api_error(400,'validation_failed'); end if;
    select * into v_holiday from app.holidays where day=v_day;
    if (v_op='holiday' and coalesce(v_holiday.active,false)) or
       (v_op='remove_holiday' and not coalesce(v_holiday.active,false)) then
      perform app_private.raise_api_error(409,'invalid_state');
    end if;
  elsif v_op='reopen' then
    v_actor:=app_private.require_manager();
    v_class:=app_private.lock_class(p_class_id,(p_change->>'expectedVersion')::bigint);
    if v_class.deleted_at is not null or v_class.admin_state<>'closed' then
      perform app_private.raise_api_error(409,'invalid_state');
    end if;
  else
    v_actor:=app_private.require_scheduler(p_class_id);
    select * into v_class from app.classes where id=p_class_id for update;
    perform app_private.require_account();
    if v_actor.account_type='user' then
      perform app_private.lock_student_edit_assignment(v_actor.id,array[p_class_id]);
      if not exists(select 1 from app.class_assignments where account_id=v_actor.id and class_id=p_class_id
        and role='teacher' and effective_period @> clock_timestamp()) then
        perform app_private.raise_api_error(403,'forbidden');
      end if;
    end if;
    if v_class.deleted_at is not null or v_class.admin_state<>'open' then
      perform app_private.raise_api_error(409,'invalid_state');
    end if;
  end if;
  v_token:=app_private.schedule_fingerprint(p_class_id,p_change);
  select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') into v_old from app.class_sessions x;
  -- Defer only within this transaction so bulk changes can release all their old
  -- reservations before checking the final state. The actual constraint is checked below.
  set constraints app.sessions_no_room_overlap deferred;
  case v_op
  when 'reopen' then
    if v_class.end_date<app_private.business_date(clock_timestamp()) then perform app_private.raise_api_error(409,'class_ended'); end if;
    if jsonb_typeof(p_change->'weekly')='object' then
      perform app_private.add_weekly_revision(p_class_id,(p_change#>>'{weekly,appliesOn}')::date,p_change#>'{weekly,slots}',v_actor.id);
    end if;
    if jsonb_typeof(p_change->'adjustments') is distinct from 'array' then
      perform app_private.raise_api_error(400,'validation_failed');
    end if;
    for v_slot in select value from jsonb_array_elements(p_change->'adjustments') loop
      select * into v_before from app.class_sessions where class_id=p_class_id and id=(v_slot->>'sessionId')::uuid for update;
      if not found or v_before.status<>'removed_class' then perform app_private.raise_api_error(409,'invalid_state'); end if;
      v_day:=(v_slot->>'date')::date;
      v_start:=(v_day+(v_slot->>'startTime')::time) at time zone 'Asia/Ho_Chi_Minh';
      v_end:=(v_day+(v_slot->>'endTime')::time) at time zone 'Asia/Ho_Chi_Minh';
      if v_start is null or v_end is null or v_end<=v_start then perform app_private.raise_api_error(400,'validation_failed'); end if;
      if v_before.starts_at<=clock_timestamp() or v_start<=clock_timestamp() then perform app_private.raise_api_error(409,'session_started'); end if;
      if v_day<v_class.start_date or v_day>v_class.end_date then perform app_private.raise_api_error(409,'outside_class_dates'); end if;
      if (v_start,v_end,(v_slot->>'roomId')::uuid) is distinct from (v_before.starts_at,v_before.ends_at,v_before.room_id) then
        if exists(select 1 from app.holidays where day=v_day and active) then perform app_private.raise_api_error(409,'holiday_conflict'); end if;
        update app.class_sessions set starts_at=v_start,ends_at=v_end,room_id=(v_slot->>'roomId')::uuid,is_exception=true,
          resume_status=case when resume_status='off' or holiday_status='off' then 'off' else 'scheduled' end,
          holiday_status=null where id=v_before.id;
      end if;
    end loop;
    update app.classes set admin_state='open',closed_at=null,row_version=row_version+1,updated_at=now()
      where id=p_class_id returning * into v_after_class;
    perform app_private.record_class_lifecycle(v_class,v_after_class,'reopen',null,v_actor.id,jsonb_build_object('schedule',p_change));
  when 'weekly' then
    v_day:=(p_change->>'appliesOn')::date;
    perform app_private.add_weekly_revision(p_class_id,v_day,p_change->'slots',v_actor.id);
    perform app_private.rebuild_sessions(v_class,v_day);
  when 'makeup', 'move', 'off', 'resume' then
    if v_op<>'makeup' then
      select * into v_before from app.class_sessions where id=(p_change->>'sessionId')::uuid and class_id=p_class_id for update;
      if not found then perform app_private.raise_api_error(404,'not_found'); end if;
      if v_before.starts_at<=clock_timestamp() then perform app_private.raise_api_error(409,'session_started'); end if;
      if v_before.row_version is distinct from (p_change->>'expectedVersion')::bigint then
        perform app_private.raise_api_error(409,'version_conflict');
      end if;
      if v_before.status not in ('scheduled','off') then perform app_private.raise_api_error(409,'invalid_state'); end if;
    end if;
    if v_op in ('makeup','move') then
      v_day:=(p_change->>'date')::date;
      v_start:=(v_day+(p_change->>'startTime')::time) at time zone 'Asia/Ho_Chi_Minh';
      v_end:=(v_day+(p_change->>'endTime')::time) at time zone 'Asia/Ho_Chi_Minh';
      if v_day is null or v_start is null or v_end is null or v_end<=v_start then
        perform app_private.raise_api_error(400,'validation_failed');
      end if;
      if v_day<v_class.start_date or v_day>v_class.end_date then
        perform app_private.raise_api_error(409,'outside_class_dates');
      end if;
      if v_start<=clock_timestamp() then perform app_private.raise_api_error(409,'session_started'); end if;
      if exists(select 1 from app.holidays where day=v_day and active) then
        perform app_private.raise_api_error(409,'holiday_conflict');
      end if;
    end if;
    if v_op='makeup' then
      insert into app.class_sessions(class_id,kind,original_day,original_start,starts_at,ends_at,room_id,status,is_exception)
      values(p_class_id,'makeup',v_day,(p_change->>'startTime')::time,v_start,v_end,(p_change->>'roomId')::uuid,'scheduled',true);
    elsif v_op='move' then
      update app.class_sessions set starts_at=v_start,ends_at=v_end,room_id=(p_change->>'roomId')::uuid,is_exception=true
      where id=v_before.id;
    else
      if v_op='resume' and exists(select 1 from app.holidays where day=app_private.business_date(v_before.starts_at) and active) then
        perform app_private.raise_api_error(409,'holiday_conflict');
      end if;
      update app.class_sessions set status=case when v_op='off' then 'off' else 'scheduled' end,is_exception=true where id=v_before.id;
    end if;
  when 'holiday' then
    if exists(select 1 from app.class_sessions where app_private.business_date(starts_at)=v_day
      and status in ('scheduled','off') and starts_at<=clock_timestamp()) then
      perform app_private.raise_api_error(409,'session_started');
    end if;
    insert into app.holidays(day,name,active) values(v_day,app_private.clean_text(p_change->>'name',200),true)
      on conflict(day) do update set name=excluded.name,active=true,row_version=app.holidays.row_version+1;
    update app.class_sessions set holiday_status=status,status='holiday'
      where app_private.business_date(starts_at)=v_day and status in ('scheduled','off');
  when 'remove_holiday' then
    update app.holidays set active=false,row_version=row_version+1 where day=v_day;
    update app.class_sessions x set status=coalesce(holiday_status,'scheduled'),holiday_status=null
      from app.classes c where c.id=x.class_id and c.deleted_at is null and c.admin_state='open'
        and app_private.business_date(x.starts_at)=v_day and x.starts_at>clock_timestamp() and x.status='holiday';
  else perform app_private.raise_api_error(400,'validation_failed');
  end case;
  v_conflicts:=app_private.room_conflicts(p_class_id);
  if jsonb_array_length(v_conflicts)>0 then perform app_private.raise_api_conflict('room_conflict',v_conflicts); end if;
  set constraints app.sessions_no_room_overlap immediate;
  select coalesce(jsonb_agg(app_private.session_dto(x) order by x.starts_at,x.id),'[]') into v_impacted
    from app.class_sessions x where not exists(select 1 from jsonb_array_elements(v_old) b where b=to_jsonb(x));
  -- One audit for the entire business command. Each session has its own version.
  if v_op<>'reopen' then
    perform app_private.write_audit(v_actor.id,'app','schedule.'||v_op,
    jsonb_strip_nulls(jsonb_build_object('class_id',p_class_id,'holiday_date',v_day)),
      jsonb_build_object('command',p_change,'sessions',v_impacted));
  end if;
  if v_op in ('holiday','remove_holiday') then
    select * into v_holiday from app.holidays where day=v_day;
    perform app_private.record_version('holiday',md5(v_day::text)::uuid,v_holiday.row_version,to_jsonb(v_holiday),v_actor.id);
  end if;
  return jsonb_build_object('token',v_token,'sessions',v_impacted,'warnings',app_private.staff_conflicts(p_class_id));
end $$;

-- Preview executes the exact command in a rolled-back subtransaction: no audit,
-- histories or reservations escape. Identity sequences may have gaps, as normal.
create function api.preview_schedule_change(p_class_id uuid,p_change jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare v_result jsonb;
begin
  begin
    v_result:=app_private.change_schedule(p_class_id,p_change);
    raise exception using errcode='PZ001',message='preview_rollback';
  exception when sqlstate 'PZ001' then null;
  end;
  return v_result;
end $$;

create function api.apply_schedule_change(p_class_id uuid,p_change jsonb,p_token text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
begin
  perform app_private.lock_scheduling();
  perform app_private.require_account();
  if p_token is null or p_token is distinct from app_private.schedule_fingerprint(p_class_id,p_change) then
    perform app_private.raise_api_error(409,'version_conflict');
  end if;
  return app_private.change_schedule(p_class_id,p_change);
end $$;

create function api.get_class_schedule(p_class_id uuid) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
begin
  perform app_private.require_class_reader(p_class_id);
  return jsonb_build_object(
    'sessions',(select coalesce(jsonb_agg(app_private.session_dto(x) order by starts_at,id),'[]') from app.class_sessions x where class_id=p_class_id),
    'weekly',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'appliesOn',applies_on,'slots',slots,'revision',revision) order by applies_on,revision),'[]') from app.weekly_schedules where class_id=p_class_id),
    'holidays',(select coalesce(jsonb_agg(jsonb_build_object('date',day,'name',name) order by day),'[]') from app.holidays where active),
    'warnings',app_private.staff_conflicts(p_class_id));
end $$;

-- Extend GĐ3 hooks without replacing its enrollment date handling.
alter function app_private.apply_class_date_change(app.classes,app.classes) rename to apply_enrollment_date_change;
create function app_private.apply_class_date_change(p_before app.classes,p_after app.classes) returns void
language plpgsql volatile set search_path = '' as $$
begin
  perform app_private.apply_enrollment_date_change(p_before,p_after);
  if exists(select 1 from app.class_sessions where class_id=p_after.id and starts_at<=clock_timestamp()
    and (app_private.business_date(starts_at)<p_after.start_date or app_private.business_date(starts_at)>p_after.end_date)) then
    perform app_private.raise_api_error(409,'class_dates_locked');
  end if;
  update app.class_sessions set status='removed_schedule' where class_id=p_after.id and starts_at>clock_timestamp()
    and status<>'removed_class' and (app_private.business_date(starts_at)<p_after.start_date or app_private.business_date(starts_at)>p_after.end_date);
  perform app_private.rebuild_sessions(p_after,app_private.business_date(clock_timestamp()));
end $$;

create or replace function app_private.on_class_lifecycle(p_class app.classes,p_event text,p_actor_id uuid)
returns void language plpgsql volatile set search_path = '' as $$
begin
  if p_event in ('close','delete') then
    update app.class_sessions set resume_status=status,status='removed_class'
      where class_id=p_class.id and starts_at>clock_timestamp() and status in ('scheduled','off','holiday');
  elsif p_event='reopen' then
    update app.class_sessions set status='removed_schedule',resume_status=null where class_id=p_class.id
      and kind='weekly' and not is_exception and starts_at>clock_timestamp() and status='removed_class';
    update app.class_sessions x set status=case when exists(select 1 from app.holidays h
      where h.day=app_private.business_date(x.starts_at) and h.active) then 'holiday'
      when resume_status='off' or holiday_status='off' then 'off' else 'scheduled' end,resume_status=null,
      holiday_status=case when exists(select 1 from app.holidays h where h.day=app_private.business_date(x.starts_at) and h.active) then holiday_status else null end
      where class_id=p_class.id and starts_at>clock_timestamp() and status='removed_class'
        and app_private.business_date(starts_at) between p_class.start_date and p_class.end_date;
    perform app_private.rebuild_sessions(p_class,app_private.business_date(clock_timestamp()));
  end if;
end $$;

-- Defer the constraint during the exact-command preview only; default remains immediate.
alter table app.class_sessions drop constraint sessions_no_room_overlap;
alter table app.class_sessions add constraint sessions_no_room_overlap exclude using gist
  (room_id with =, tstzrange(starts_at,ends_at,'[)') with &&)
  where (status='scheduled' and room_id is not null) deferrable initially immediate;

revoke all on all functions in schema app_private from public,anon,authenticated;
revoke all on function api.preview_schedule_change(uuid,jsonb),api.apply_schedule_change(uuid,jsonb,text),api.get_class_schedule(uuid) from public,anon;
grant execute on function api.preview_schedule_change(uuid,jsonb),api.apply_schedule_change(uuid,jsonb,text),api.get_class_schedule(uuid) to authenticated;
