-- GĐ 3: shared catalogs — subjects, grades (CAT-01), sites (SCHED-03) and rooms
-- (SCHED-02/05). Also the helpers every GĐ 3 command uses: lookup keys
-- (STU-04 name normalization), text limits (C.1.1), manager checks and the
-- version + audit pair written by each change.
--
-- Catalogs are shared by the whole centre: no tenants and no site-based
-- permissions (A.1). Archiving is a soft delete that keeps the identifier, the
-- name used by older records and the history; restoring reuses the identifier.

-------------------------------------------------------------------------------
-- Shared helpers.
-------------------------------------------------------------------------------

-- Lookup key of a name (STU-04): NFD, drop combining marks, đ/Đ -> d, lower
-- case, trim and collapse whitespace. Punctuation is kept. Display names keep
-- their original diacritics; keys are only used to compare and search.
create function app_private.name_key(p_value text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select regexp_replace(
    regexp_replace(
      lower(translate(
        regexp_replace(normalize(coalesce(p_value, ''), nfd), '[̀-ͯ]', '', 'g'),
        'đĐ', 'dd')),
      '^\s+|\s+$', '', 'g'),
    '\s+', ' ', 'g')
$$;

comment on function app_private.name_key(text) is
  'STU-04/D08 lookup key: accents removed, đ -> d, lower case, single spaces.';

-- Required text: trimmed, NFC, 1..p_max Unicode characters (C.1.1). 400 otherwise.
create function app_private.clean_text(p_value text, p_max integer)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  v_value text := normalize(regexp_replace(coalesce(p_value, ''), '^\s+|\s+$', '', 'g'), nfc);
begin
  if char_length(v_value) not between 1 and p_max then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  return v_value;
end
$$;

-- Optional text: empty or whitespace-only becomes NULL; otherwise as clean_text.
create function app_private.clean_optional_text(p_value text, p_max integer)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  v_value text := normalize(regexp_replace(coalesce(p_value, ''), '^\s+|\s+$', '', 'g'), nfc);
begin
  if v_value = '' then
    return null;
  end if;
  if char_length(v_value) > p_max then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  return v_value;
end
$$;

-- Admin or Receptionist (management of students, classes, sites and rooms).
create function app_private.require_manager()
returns app.account_profiles
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_actor app.account_profiles;
begin
  v_actor := app_private.require_account(p_lock => true);
  if v_actor.account_type not in ('admin', 'receptionist') then
    perform app_private.raise_api_error(403, 'forbidden');
  end if;
  return v_actor;
end
$$;

-- Records the new version and the audit row of one business change inside the
-- caller's transaction. p_before is NULL for a new record.
create function app_private.record_change(
  p_entity_kind text,
  p_entity_id uuid,
  p_revision bigint,
  p_before jsonb,
  p_after jsonb,
  p_actor_id uuid,
  p_action text,
  p_entity_refs jsonb,
  p_reason text default null
)
returns void
language plpgsql
set search_path = ''
as $$
begin
  perform app_private.record_version(p_entity_kind, p_entity_id, p_revision, p_after,
    p_actor_id, p_reason);
  perform app_private.write_audit(
    p_actor_id,
    'app',
    p_action,
    p_entity_refs,
    jsonb_strip_nulls(jsonb_build_object('before', p_before, 'after', p_after, 'reason', p_reason))
  );
end
$$;

-------------------------------------------------------------------------------
-- Subjects and grades (CAT-01). Admin writes; every internal account reads.
-------------------------------------------------------------------------------

create table app.catalog_entries (
  id uuid primary key default gen_random_uuid(),
  kind text not null,
  name text not null,
  name_key text not null,
  row_version bigint not null default 1,
  created_at timestamptz not null default now(),
  created_by uuid not null references app.account_profiles (id),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  deleted_by uuid references app.account_profiles (id),
  deleted_reason text,
  -- Unique per kind including archived entries (CAT-01).
  constraint catalog_entries_name_key_key unique (kind, name_key),
  constraint catalog_entries_kind_check check (kind in ('subject', 'grade')),
  constraint catalog_entries_name_check check (
    name = btrim(name) and name is nfc normalized and char_length(name) between 1 and 100
  ),
  constraint catalog_entries_name_key_check check (name_key = app_private.name_key(name)),
  constraint catalog_entries_row_version_check check (row_version >= 1),
  constraint catalog_entries_deleted_check check (
    (deleted_at is null and deleted_by is null and deleted_reason is null)
    or (deleted_at is not null and deleted_by is not null
        and char_length(deleted_reason) between 1 and 1000)
  )
);

comment on table app.catalog_entries is
  'Subjects and grades (CAT-01). Archived entries keep their id for older classes.';

-------------------------------------------------------------------------------
-- Sites (SCHED-03) and rooms (SCHED-02/05). Admin and Receptionist write.
-------------------------------------------------------------------------------

create table app.sites (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  name_key text not null,
  address text not null,
  row_version bigint not null default 1,
  created_at timestamptz not null default now(),
  created_by uuid not null references app.account_profiles (id),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  deleted_by uuid references app.account_profiles (id),
  deleted_reason text,
  constraint sites_name_key_key unique (name_key),
  constraint sites_name_check check (
    name = btrim(name) and name is nfc normalized and char_length(name) between 1 and 200
  ),
  constraint sites_name_key_check check (name_key = app_private.name_key(name)),
  constraint sites_address_check check (
    address = btrim(address) and address is nfc normalized and char_length(address) between 1 and 500
  ),
  constraint sites_row_version_check check (row_version >= 1),
  constraint sites_deleted_check check (
    (deleted_at is null and deleted_by is null and deleted_reason is null)
    or (deleted_at is not null and deleted_by is not null
        and char_length(deleted_reason) between 1 and 1000)
  )
);

comment on table app.sites is
  'Centre sites (SCHED-03). Initial sites are data, never fixed in code.';

create table app.rooms (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references app.sites (id),
  -- Only name and site are managed (SCHED-02): no capacity or notes.
  name text not null,
  name_key text not null,
  row_version bigint not null default 1,
  created_at timestamptz not null default now(),
  created_by uuid not null references app.account_profiles (id),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  deleted_by uuid references app.account_profiles (id),
  deleted_reason text,
  -- Same name allowed at different sites; unique within a site including archived rooms.
  constraint rooms_name_key_key unique (site_id, name_key),
  constraint rooms_name_check check (
    name = btrim(name) and name is nfc normalized and char_length(name) between 1 and 200
  ),
  constraint rooms_name_key_check check (name_key = app_private.name_key(name)),
  constraint rooms_row_version_check check (row_version >= 1),
  constraint rooms_deleted_check check (
    (deleted_at is null and deleted_by is null and deleted_reason is null)
    or (deleted_at is not null and deleted_by is not null
        and char_length(deleted_reason) between 1 and 1000)
  )
);

create index rooms_site_idx on app.rooms (site_id);

comment on table app.rooms is
  'Rooms of a site (SCHED-02). Sessions keep their own room snapshot (GĐ 4).';

alter table app.catalog_entries enable row level security;
alter table app.sites enable row level security;
alter table app.rooms enable row level security;
revoke all on table app.catalog_entries, app.sites, app.rooms from public, anon, authenticated;

-------------------------------------------------------------------------------
-- Snapshots (history/audit) and DTOs (packages/contracts/src/catalogs.ts).
-------------------------------------------------------------------------------

create function app_private.catalog_entry_snapshot(p_entry app.catalog_entries)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'kind', p_entry.kind,
    'name', p_entry.name,
    'deleted_at', p_entry.deleted_at,
    'deleted_by', p_entry.deleted_by,
    'deleted_reason', p_entry.deleted_reason
  )
$$;

create function app_private.catalog_entry_dto(p_entry app.catalog_entries)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_entry.id,
    'kind', p_entry.kind,
    'name', p_entry.name,
    'archived', p_entry.deleted_at is not null,
    'deletedAt', p_entry.deleted_at,
    'deletedReason', p_entry.deleted_reason,
    'rowVersion', p_entry.row_version
  )
$$;

create function app_private.site_snapshot(p_site app.sites)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'name', p_site.name,
    'address', p_site.address,
    'deleted_at', p_site.deleted_at,
    'deleted_by', p_site.deleted_by,
    'deleted_reason', p_site.deleted_reason
  )
$$;

create function app_private.site_dto(p_site app.sites)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_site.id,
    'name', p_site.name,
    'address', p_site.address,
    'archived', p_site.deleted_at is not null,
    'deletedAt', p_site.deleted_at,
    'deletedReason', p_site.deleted_reason,
    'activeRoomCount', (
      select count(*) from app.rooms r where r.site_id = p_site.id and r.deleted_at is null
    ),
    'rowVersion', p_site.row_version
  )
$$;

create function app_private.room_snapshot(p_room app.rooms)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'site_id', p_room.site_id,
    'name', p_room.name,
    'deleted_at', p_room.deleted_at,
    'deleted_by', p_room.deleted_by,
    'deleted_reason', p_room.deleted_reason
  )
$$;

create function app_private.room_dto(p_room app.rooms)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_room.id,
    'siteId', p_room.site_id,
    'siteName', s.name,
    'siteArchived', s.deleted_at is not null,
    'name', p_room.name,
    'archived', p_room.deleted_at is not null,
    'deletedAt', p_room.deleted_at,
    'deletedReason', p_room.deleted_reason,
    'rowVersion', p_room.row_version
  )
    from app.sites s
   where s.id = p_room.site_id
$$;

-------------------------------------------------------------------------------
-- Subject/grade commands (CAT-01).
-------------------------------------------------------------------------------

create function app_private.check_catalog_kind(p_kind text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_kind is null or p_kind not in ('subject', 'grade') then
    perform app_private.raise_api_error(400, 'validation_failed');
  end if;
  return p_kind;
end
$$;

-- Archived entries are listed only for Admin (management page). Classes keep
-- showing archived names through their own reads.
create function api.list_catalog_entries(p_kind text, p_include_archived boolean default false)
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
    select jsonb_agg(app_private.catalog_entry_dto(e) order by e.deleted_at nulls first, e.name_key, e.id)
      from app.catalog_entries e
     where e.kind = v_kind
       and (coalesce(p_include_archived, false) or e.deleted_at is null)
  ), '[]');
end
$$;

-- A name whose key matches an archived entry is restored instead of created
-- (CAT-01): the caller gets archived_duplicate and restores that entry.
create function app_private.assert_catalog_name_free(p_kind text, p_name_key text, p_except uuid)
returns void
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_other app.catalog_entries;
begin
  select * into v_other
    from app.catalog_entries e
   where e.kind = p_kind and e.name_key = p_name_key and e.id is distinct from p_except;
  if found then
    perform app_private.raise_api_error(409,
      case when v_other.deleted_at is null then 'duplicate_name' else 'archived_duplicate' end);
  end if;
end
$$;

create function api.create_catalog_entry(p_kind text, p_name text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_admin();
  v_kind text := app_private.check_catalog_kind(p_kind);
  v_name text := app_private.clean_text(p_name, 100);
  v_entry app.catalog_entries;
begin
  -- Serializes creations of the same key; the unique constraint is the backstop.
  perform pg_advisory_xact_lock(hashtextextended('catalog:' || v_kind || ':' || app_private.name_key(v_name), 0));
  perform app_private.assert_catalog_name_free(v_kind, app_private.name_key(v_name), null);

  insert into app.catalog_entries (kind, name, name_key, created_by)
  values (v_kind, v_name, app_private.name_key(v_name), v_actor.id)
  returning * into v_entry;

  perform app_private.record_change('catalog_entry', v_entry.id, v_entry.row_version, null,
    app_private.catalog_entry_snapshot(v_entry), v_actor.id, 'catalog.' || v_kind || '.create',
    jsonb_build_object('catalog_entry_id', v_entry.id));
  return app_private.catalog_entry_dto(v_entry);
end
$$;

create function app_private.lock_catalog_entry(p_id uuid, p_expected_version bigint)
returns app.catalog_entries
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_entry app.catalog_entries;
begin
  select * into v_entry from app.catalog_entries e where e.id = p_id for update;
  if not found then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  if p_expected_version is null or v_entry.row_version <> p_expected_version then
    perform app_private.raise_api_error(409, 'version_conflict');
  end if;
  return v_entry;
end
$$;

create function api.rename_catalog_entry(p_id uuid, p_name text, p_expected_version bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_admin();
  v_name text := app_private.clean_text(p_name, 100);
  v_before app.catalog_entries := app_private.lock_catalog_entry(p_id, p_expected_version);
  v_after app.catalog_entries;
begin
  if v_before.deleted_at is not null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
  if v_before.name = v_name then
    return app_private.catalog_entry_dto(v_before);
  end if;
  perform pg_advisory_xact_lock(hashtextextended('catalog:' || v_before.kind || ':' || app_private.name_key(v_name), 0));
  perform app_private.assert_catalog_name_free(v_before.kind, app_private.name_key(v_name), v_before.id);

  update app.catalog_entries e
     set name = v_name,
         name_key = app_private.name_key(v_name),
         row_version = e.row_version + 1,
         updated_at = now()
   where e.id = v_before.id
  returning * into v_after;

  perform app_private.record_change('catalog_entry', v_after.id, v_after.row_version,
    app_private.catalog_entry_snapshot(v_before), app_private.catalog_entry_snapshot(v_after),
    v_actor.id, 'catalog.' || v_after.kind || '.rename',
    jsonb_build_object('catalog_entry_id', v_after.id));
  return app_private.catalog_entry_dto(v_after);
end
$$;

-- Archiving is allowed while classes use the entry; they keep the reference.
create function api.archive_catalog_entry(p_id uuid, p_reason text, p_expected_version bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_admin();
  v_reason text := app_private.normalize_reason(p_reason);
  v_before app.catalog_entries := app_private.lock_catalog_entry(p_id, p_expected_version);
  v_after app.catalog_entries;
begin
  if v_before.deleted_at is not null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;

  update app.catalog_entries e
     set deleted_at = now(),
         deleted_by = v_actor.id,
         deleted_reason = v_reason,
         row_version = e.row_version + 1,
         updated_at = now()
   where e.id = v_before.id
  returning * into v_after;

  perform app_private.record_change('catalog_entry', v_after.id, v_after.row_version,
    app_private.catalog_entry_snapshot(v_before), app_private.catalog_entry_snapshot(v_after),
    v_actor.id, 'catalog.' || v_after.kind || '.archive',
    jsonb_build_object('catalog_entry_id', v_after.id), v_reason);
  return app_private.catalog_entry_dto(v_after);
end
$$;

create function api.restore_catalog_entry(p_id uuid, p_expected_version bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_admin();
  v_before app.catalog_entries := app_private.lock_catalog_entry(p_id, p_expected_version);
  v_after app.catalog_entries;
begin
  if v_before.deleted_at is null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;

  update app.catalog_entries e
     set deleted_at = null,
         deleted_by = null,
         deleted_reason = null,
         row_version = e.row_version + 1,
         updated_at = now()
   where e.id = v_before.id
  returning * into v_after;

  perform app_private.record_change('catalog_entry', v_after.id, v_after.row_version,
    app_private.catalog_entry_snapshot(v_before), app_private.catalog_entry_snapshot(v_after),
    v_actor.id, 'catalog.' || v_after.kind || '.restore',
    jsonb_build_object('catalog_entry_id', v_after.id));
  return app_private.catalog_entry_dto(v_after);
end
$$;

-------------------------------------------------------------------------------
-- Site commands (SCHED-03/05).
-------------------------------------------------------------------------------

create function api.list_sites(p_include_archived boolean default false)
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
    select jsonb_agg(app_private.site_dto(s) order by s.deleted_at nulls first, s.name_key, s.id)
      from app.sites s
     where coalesce(p_include_archived, false) or s.deleted_at is null
  ), '[]');
end
$$;

create function app_private.assert_site_name_free(p_name_key text, p_except uuid)
returns void
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_other app.sites;
begin
  select * into v_other from app.sites s where s.name_key = p_name_key and s.id is distinct from p_except;
  if found then
    perform app_private.raise_api_error(409,
      case when v_other.deleted_at is null then 'duplicate_name' else 'archived_duplicate' end);
  end if;
end
$$;

create function app_private.lock_site(p_id uuid, p_expected_version bigint)
returns app.sites
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_site app.sites;
begin
  select * into v_site from app.sites s where s.id = p_id for update;
  if not found then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  if p_expected_version is null or v_site.row_version <> p_expected_version then
    perform app_private.raise_api_error(409, 'version_conflict');
  end if;
  return v_site;
end
$$;

create function api.create_site(p_name text, p_address text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_manager();
  v_name text := app_private.clean_text(p_name, 200);
  v_address text := app_private.clean_text(p_address, 500);
  v_site app.sites;
begin
  perform pg_advisory_xact_lock(hashtextextended('site:' || app_private.name_key(v_name), 0));
  perform app_private.assert_site_name_free(app_private.name_key(v_name), null);

  insert into app.sites (name, name_key, address, created_by)
  values (v_name, app_private.name_key(v_name), v_address, v_actor.id)
  returning * into v_site;

  perform app_private.record_change('site', v_site.id, v_site.row_version, null,
    app_private.site_snapshot(v_site), v_actor.id, 'site.create',
    jsonb_build_object('site_id', v_site.id));
  return app_private.site_dto(v_site);
end
$$;

create function api.update_site(p_id uuid, p_name text, p_address text, p_expected_version bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_manager();
  v_name text := app_private.clean_text(p_name, 200);
  v_address text := app_private.clean_text(p_address, 500);
  v_before app.sites := app_private.lock_site(p_id, p_expected_version);
  v_after app.sites;
begin
  if v_before.deleted_at is not null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
  if v_before.name = v_name and v_before.address = v_address then
    return app_private.site_dto(v_before);
  end if;
  perform pg_advisory_xact_lock(hashtextextended('site:' || app_private.name_key(v_name), 0));
  perform app_private.assert_site_name_free(app_private.name_key(v_name), v_before.id);

  update app.sites s
     set name = v_name,
         name_key = app_private.name_key(v_name),
         address = v_address,
         row_version = s.row_version + 1,
         updated_at = now()
   where s.id = v_before.id
  returning * into v_after;

  perform app_private.record_change('site', v_after.id, v_after.row_version,
    app_private.site_snapshot(v_before), app_private.site_snapshot(v_after), v_actor.id,
    'site.update', jsonb_build_object('site_id', v_after.id));
  return app_private.site_dto(v_after);
end
$$;

-- SCHED-05: a site (and every room in it, archived in the same command) may be
-- archived only when no room has a session in progress or still to come.
-- Sessions and weekly schedules arrive in GĐ 4, which adds that check to
-- app_private.assert_room_unused; until then no room can be in use.
create function app_private.assert_room_unused(p_room_id uuid)
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  -- GĐ 4 (SCHED-01/05): raise 409 room_in_use listing the sessions/schedules
  -- that still use p_room_id now or in the future.
  return;
end
$$;

create function api.archive_site(p_id uuid, p_reason text, p_expected_version bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_manager();
  v_reason text := app_private.normalize_reason(p_reason);
  v_before app.sites := app_private.lock_site(p_id, p_expected_version);
  v_after app.sites;
  v_room_before app.rooms;
  v_room_after app.rooms;
  v_room_ids jsonb := '[]';
begin
  if v_before.deleted_at is not null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;

  for v_room_before in
    select * from app.rooms r where r.site_id = v_before.id and r.deleted_at is null
     order by r.id for update
  loop
    perform app_private.assert_room_unused(v_room_before.id);
    update app.rooms r
       set deleted_at = now(),
           deleted_by = v_actor.id,
           deleted_reason = v_reason,
           row_version = r.row_version + 1,
           updated_at = now()
     where r.id = v_room_before.id
    returning * into v_room_after;
    perform app_private.record_version('room', v_room_after.id, v_room_after.row_version,
      app_private.room_snapshot(v_room_after), v_actor.id, v_reason);
    v_room_ids := v_room_ids || to_jsonb(v_room_after.id);
  end loop;

  update app.sites s
     set deleted_at = now(),
         deleted_by = v_actor.id,
         deleted_reason = v_reason,
         row_version = s.row_version + 1,
         updated_at = now()
   where s.id = v_before.id
  returning * into v_after;

  -- One audit row for the whole command, listing the rooms archived with it.
  perform app_private.record_version('site', v_after.id, v_after.row_version,
    app_private.site_snapshot(v_after), v_actor.id, v_reason);
  perform app_private.write_audit(v_actor.id, 'app', 'site.archive',
    jsonb_build_object('site_id', v_after.id),
    jsonb_build_object(
      'before', app_private.site_snapshot(v_before),
      'after', app_private.site_snapshot(v_after),
      'archived_room_ids', v_room_ids,
      'reason', v_reason));
  return app_private.site_dto(v_after);
end
$$;

-- Restoring a site does not restore its rooms; each room is restored on its own.
create function api.restore_site(p_id uuid, p_expected_version bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_manager();
  v_before app.sites := app_private.lock_site(p_id, p_expected_version);
  v_after app.sites;
begin
  if v_before.deleted_at is null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;

  update app.sites s
     set deleted_at = null,
         deleted_by = null,
         deleted_reason = null,
         row_version = s.row_version + 1,
         updated_at = now()
   where s.id = v_before.id
  returning * into v_after;

  perform app_private.record_change('site', v_after.id, v_after.row_version,
    app_private.site_snapshot(v_before), app_private.site_snapshot(v_after), v_actor.id,
    'site.restore', jsonb_build_object('site_id', v_after.id));
  return app_private.site_dto(v_after);
end
$$;

-------------------------------------------------------------------------------
-- Room commands (SCHED-02/05).
-------------------------------------------------------------------------------

create function api.list_rooms(p_site_id uuid default null, p_include_archived boolean default false)
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
             order by r.deleted_at nulls first, s.name_key, r.name_key, r.id)
      from app.rooms r
      join app.sites s on s.id = r.site_id
     where (p_site_id is null or r.site_id = p_site_id)
       and (coalesce(p_include_archived, false) or (r.deleted_at is null and s.deleted_at is null))
  ), '[]');
end
$$;

-- New and moved rooms must belong to an active site (SCHED-05).
create function app_private.lock_active_site(p_site_id uuid)
returns app.sites
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_site app.sites;
begin
  select * into v_site from app.sites s where s.id = p_site_id for share;
  if not found then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  if v_site.deleted_at is not null then
    perform app_private.raise_api_error(409, 'site_archived');
  end if;
  return v_site;
end
$$;

create function app_private.assert_room_name_free(p_site_id uuid, p_name_key text, p_except uuid)
returns void
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_other app.rooms;
begin
  select * into v_other
    from app.rooms r
   where r.site_id = p_site_id and r.name_key = p_name_key and r.id is distinct from p_except;
  if found then
    perform app_private.raise_api_error(409,
      case when v_other.deleted_at is null then 'duplicate_name' else 'archived_duplicate' end);
  end if;
end
$$;

create function app_private.lock_room(p_id uuid, p_expected_version bigint)
returns app.rooms
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_room app.rooms;
begin
  select * into v_room from app.rooms r where r.id = p_id for update;
  if not found then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  if p_expected_version is null or v_room.row_version <> p_expected_version then
    perform app_private.raise_api_error(409, 'version_conflict');
  end if;
  return v_room;
end
$$;

create function api.create_room(p_site_id uuid, p_name text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_manager();
  v_name text := app_private.clean_text(p_name, 200);
  v_site app.sites := app_private.lock_active_site(p_site_id);
  v_room app.rooms;
begin
  perform pg_advisory_xact_lock(hashtextextended('room:' || v_site.id || ':' || app_private.name_key(v_name), 0));
  perform app_private.assert_room_name_free(v_site.id, app_private.name_key(v_name), null);

  insert into app.rooms (site_id, name, name_key, created_by)
  values (v_site.id, v_name, app_private.name_key(v_name), v_actor.id)
  returning * into v_room;

  perform app_private.record_change('room', v_room.id, v_room.row_version, null,
    app_private.room_snapshot(v_room), v_actor.id, 'room.create',
    jsonb_build_object('room_id', v_room.id, 'site_id', v_site.id));
  return app_private.room_dto(v_room);
end
$$;

-- Renaming or moving a room changes only the catalog; sessions that already
-- started keep the room name/site they had (GĐ 4 snapshot).
create function api.update_room(p_id uuid, p_site_id uuid, p_name text, p_expected_version bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_manager();
  v_name text := app_private.clean_text(p_name, 200);
  v_before app.rooms := app_private.lock_room(p_id, p_expected_version);
  v_site app.sites;
  v_after app.rooms;
begin
  if v_before.deleted_at is not null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
  v_site := app_private.lock_active_site(p_site_id);
  if v_before.site_id = v_site.id and v_before.name = v_name then
    return app_private.room_dto(v_before);
  end if;
  perform pg_advisory_xact_lock(hashtextextended('room:' || v_site.id || ':' || app_private.name_key(v_name), 0));
  perform app_private.assert_room_name_free(v_site.id, app_private.name_key(v_name), v_before.id);

  update app.rooms r
     set site_id = v_site.id,
         name = v_name,
         name_key = app_private.name_key(v_name),
         row_version = r.row_version + 1,
         updated_at = now()
   where r.id = v_before.id
  returning * into v_after;

  perform app_private.record_change('room', v_after.id, v_after.row_version,
    app_private.room_snapshot(v_before), app_private.room_snapshot(v_after), v_actor.id,
    'room.update', jsonb_build_object('room_id', v_after.id, 'site_id', v_after.site_id));
  return app_private.room_dto(v_after);
end
$$;

create function api.archive_room(p_id uuid, p_reason text, p_expected_version bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_manager();
  v_reason text := app_private.normalize_reason(p_reason);
  v_before app.rooms := app_private.lock_room(p_id, p_expected_version);
  v_after app.rooms;
begin
  if v_before.deleted_at is not null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
  perform app_private.assert_room_unused(v_before.id);

  update app.rooms r
     set deleted_at = now(),
         deleted_by = v_actor.id,
         deleted_reason = v_reason,
         row_version = r.row_version + 1,
         updated_at = now()
   where r.id = v_before.id
  returning * into v_after;

  perform app_private.record_change('room', v_after.id, v_after.row_version,
    app_private.room_snapshot(v_before), app_private.room_snapshot(v_after), v_actor.id,
    'room.archive', jsonb_build_object('room_id', v_after.id, 'site_id', v_after.site_id), v_reason);
  return app_private.room_dto(v_after);
end
$$;

-- A room comes back only into an active site; restoring rebuilds no schedule.
create function api.restore_room(p_id uuid, p_expected_version bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles := app_private.require_manager();
  v_before app.rooms := app_private.lock_room(p_id, p_expected_version);
  v_after app.rooms;
begin
  if v_before.deleted_at is null then
    perform app_private.raise_api_error(409, 'invalid_state');
  end if;
  perform app_private.lock_active_site(v_before.site_id);

  update app.rooms r
     set deleted_at = null,
         deleted_by = null,
         deleted_reason = null,
         row_version = r.row_version + 1,
         updated_at = now()
   where r.id = v_before.id
  returning * into v_after;

  perform app_private.record_change('room', v_after.id, v_after.row_version,
    app_private.room_snapshot(v_before), app_private.room_snapshot(v_after), v_actor.id,
    'room.restore', jsonb_build_object('room_id', v_after.id, 'site_id', v_after.site_id));
  return app_private.room_dto(v_after);
end
$$;

grant execute on function api.list_catalog_entries(text, boolean) to authenticated;
grant execute on function api.create_catalog_entry(text, text) to authenticated;
grant execute on function api.rename_catalog_entry(uuid, text, bigint) to authenticated;
grant execute on function api.archive_catalog_entry(uuid, text, bigint) to authenticated;
grant execute on function api.restore_catalog_entry(uuid, bigint) to authenticated;
grant execute on function api.list_sites(boolean) to authenticated;
grant execute on function api.create_site(text, text) to authenticated;
grant execute on function api.update_site(uuid, text, text, bigint) to authenticated;
grant execute on function api.archive_site(uuid, text, bigint) to authenticated;
grant execute on function api.restore_site(uuid, bigint) to authenticated;
grant execute on function api.list_rooms(uuid, boolean) to authenticated;
grant execute on function api.create_room(uuid, text) to authenticated;
grant execute on function api.update_room(uuid, uuid, text, bigint) to authenticated;
grant execute on function api.archive_room(uuid, text, bigint) to authenticated;
grant execute on function api.restore_room(uuid, bigint) to authenticated;
