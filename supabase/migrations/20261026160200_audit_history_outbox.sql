-- Audit, long-term business history and notification outbox (AUD-01, NOTIF-01).
--
-- Every business command runs in one RPC transaction that changes data, writes
-- its audit row, its history versions and its required notification requests.
-- Any failure (including the audit insert) rolls back the whole command.
-- Delivery/retention jobs come in GĐ 9; their tables are added then.

-- Rejects JSON that carries secrets by key name (passwords, hashes of them,
-- reset links, tokens, signed URLs). Applied to audit/history/outbox payloads.
create function app_private.assert_no_secrets(p_value jsonb)
returns void
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_key text;
  v_child jsonb;
begin
  case jsonb_typeof(p_value)
    when 'object' then
      for v_key, v_child in select e.key, e.value from jsonb_each(p_value) e loop
        if lower(v_key) ~ '(password|passwd|secret|token|jwt|otp|api_?key|signed_?url|encrypted)' then
          raise exception using errcode = '22023', message = 'secret_in_payload',
            detail = format('JSON key "%s" is not allowed in audit/history/outbox data', v_key);
        end if;
        perform app_private.assert_no_secrets(v_child);
      end loop;
    when 'array' then
      for v_child in select e.value from jsonb_array_elements(p_value) e loop
        perform app_private.assert_no_secrets(v_child);
      end loop;
    else
      null;
  end case;
end
$$;

-- Request ID forwarded by the Worker (X-Request-Id), if the call came through PostgREST.
create function app_private.current_request_id()
returns text
language sql
stable
set search_path = ''
as $$
  select left(nullif(current_setting('request.headers', true), '')::json ->> 'x-request-id', 64)
$$;

create function app_private.reject_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using errcode = '42501', message = 'append_only',
    detail = format('%I.%I rows cannot be %s', tg_table_schema, tg_table_name, lower(tg_op));
end
$$;

-------------------------------------------------------------------------------
-- Audit: kept exactly 60 days from creation, then removed by the retention job.
-------------------------------------------------------------------------------

create table app.audit_events (
  id uuid primary key default gen_random_uuid(),
  -- NULL only for jobs and operations tools; app/Excel commands always have an actor.
  actor_id uuid references app.account_profiles (id),
  -- app: UI/API command; excel: confirmed import; job: background task;
  -- ops: controlled operations tool (AUTH-06).
  source text not null,
  -- Dotted lower-case name, e.g. account.profile.update.
  action text not null,
  -- Identifiers used by AUD-01 filters, e.g. {"student_id": ..., "class_id": ...}.
  entity_refs jsonb not null default '{}',
  -- Before/after values of the change; never secrets (see assert_no_secrets).
  before_after jsonb not null default '{}',
  request_id text,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  constraint audit_events_source_check check (source in ('app', 'excel', 'job', 'ops')),
  constraint audit_events_actor_check check (source in ('job', 'ops') or actor_id is not null),
  constraint audit_events_action_check
    check (action ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$' and char_length(action) <= 100),
  constraint audit_events_entity_refs_check check (jsonb_typeof(entity_refs) = 'object'),
  constraint audit_events_before_after_check check (jsonb_typeof(before_after) = 'object'),
  constraint audit_events_expiry_check check (expires_at = created_at + interval '1440 hours')
);

create index audit_events_created_at_idx on app.audit_events (created_at desc);
create index audit_events_actor_idx on app.audit_events (actor_id, created_at desc);
create index audit_events_action_idx on app.audit_events (action, created_at desc);
create index audit_events_entity_refs_idx on app.audit_events using gin (entity_refs jsonb_path_ops);
create index audit_events_expires_at_idx on app.audit_events (expires_at);

comment on table app.audit_events is
  'AUD-01 audit. Append-only; rows expire exactly 60 days (1440 h) after creation.';

create function app_private.audit_events_before_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- The database clock decides retention; callers cannot back- or post-date rows.
  new.created_at := now();
  new.expires_at := new.created_at + interval '1440 hours';
  new.request_id := coalesce(new.request_id, app_private.current_request_id());
  perform app_private.assert_no_secrets(new.entity_refs);
  perform app_private.assert_no_secrets(new.before_after);
  return new;
end
$$;

create trigger audit_events_before_insert
  before insert on app.audit_events
  for each row execute function app_private.audit_events_before_insert();

create trigger audit_events_no_update
  before update on app.audit_events
  for each row execute function app_private.reject_change();

create trigger audit_events_no_truncate
  before truncate on app.audit_events
  for each statement execute function app_private.reject_change();

-- Only expired rows may be deleted (retention job, AUD-01). Deleting them does
-- not create another audit row.
create function app_private.audit_events_before_delete()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.expires_at > now() then
    raise exception using errcode = '42501', message = 'audit_not_expired';
  end if;
  return old;
end
$$;

create trigger audit_events_before_delete
  before delete on app.audit_events
  for each row execute function app_private.audit_events_before_delete();

-------------------------------------------------------------------------------
-- Business history: versions kept without time limit, independent of audit.
-------------------------------------------------------------------------------

create table app.business_entity_versions (
  id uuid primary key default gen_random_uuid(),
  entity_kind text not null,
  -- Logical reference; entity tables differ, so there is no physical FK.
  entity_id uuid not null,
  revision bigint not null,
  sanitized_snapshot jsonb not null,
  changed_by uuid references app.account_profiles (id),
  changed_at timestamptz not null default now(),
  reason text,
  constraint business_entity_versions_revision_key unique (entity_kind, entity_id, revision),
  constraint business_entity_versions_kind_check check (entity_kind ~ '^[a-z][a-z0-9_]*$'),
  constraint business_entity_versions_revision_check check (revision >= 1),
  constraint business_entity_versions_snapshot_check
    check (jsonb_typeof(sanitized_snapshot) = 'object'),
  constraint business_entity_versions_reason_check
    check (reason is null or char_length(reason) between 1 and 1000)
);

comment on table app.business_entity_versions is
  'Version snapshots of business records (secrets excluded). Never expires.';

create function app_private.business_entity_versions_before_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.changed_at := now();
  perform app_private.assert_no_secrets(new.sanitized_snapshot);
  return new;
end
$$;

create trigger business_entity_versions_before_insert
  before insert on app.business_entity_versions
  for each row execute function app_private.business_entity_versions_before_insert();

create trigger business_entity_versions_no_update
  before update or delete on app.business_entity_versions
  for each row execute function app_private.reject_change();

create trigger business_entity_versions_no_truncate
  before truncate on app.business_entity_versions
  for each statement execute function app_private.reject_change();

-------------------------------------------------------------------------------
-- Outbox: notification requests stored with the business change, delivered later.
-------------------------------------------------------------------------------

create table app.outbox_events (
  id uuid primary key default gen_random_uuid(),
  -- Idempotency key of the business event; a retried job reuses it.
  event_key text not null,
  event_kind text not null,
  subject_kind text not null,
  subject_id uuid not null,
  -- Minimal signal only; clients re-read details through permission-checked APIs.
  minimal_payload jsonb not null default '{}',
  created_at timestamptz not null default now(),
  constraint outbox_events_event_key_key unique (event_key),
  constraint outbox_events_event_key_check check (char_length(event_key) between 1 and 200),
  constraint outbox_events_kind_check
    check (event_kind ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$' and char_length(event_kind) <= 100),
  constraint outbox_events_subject_kind_check check (subject_kind ~ '^[a-z][a-z0-9_]*$'),
  constraint outbox_events_payload_check check (jsonb_typeof(minimal_payload) = 'object')
);

create table app.outbox_deliveries (
  event_id uuid not null references app.outbox_events (id),
  recipient_id uuid not null references app.account_profiles (id),
  state text not null default 'pending',
  attempt_count integer not null default 0,
  next_attempt_at timestamptz,
  delivered_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (event_id, recipient_id),
  constraint outbox_deliveries_state_check check (state in ('pending', 'retry', 'delivered')),
  constraint outbox_deliveries_delivered_check check ((state = 'delivered') = (delivered_at is not null)),
  constraint outbox_deliveries_attempt_check check (attempt_count >= 0)
);

create index outbox_deliveries_due_idx on app.outbox_deliveries (next_attempt_at)
  where state <> 'delivered';
create index outbox_deliveries_recipient_idx on app.outbox_deliveries (recipient_id);

create function app_private.outbox_events_before_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.created_at := now();
  perform app_private.assert_no_secrets(new.minimal_payload);
  return new;
end
$$;

create trigger outbox_events_before_insert
  before insert on app.outbox_events
  for each row execute function app_private.outbox_events_before_insert();

-- Events are immutable; delivery rows keep the dedupe key after notifications expire.
create trigger outbox_events_no_update
  before update or delete on app.outbox_events
  for each row execute function app_private.reject_change();

create trigger outbox_deliveries_no_delete
  before delete on app.outbox_deliveries
  for each row execute function app_private.reject_change();

alter table app.audit_events enable row level security;
alter table app.business_entity_versions enable row level security;
alter table app.outbox_events enable row level security;
alter table app.outbox_deliveries enable row level security;
revoke all on table
  app.audit_events,
  app.business_entity_versions,
  app.outbox_events,
  app.outbox_deliveries
  from public, anon, authenticated;

-------------------------------------------------------------------------------
-- Helpers called by command RPCs inside their transaction.
-------------------------------------------------------------------------------

create function app_private.write_audit(
  p_actor_id uuid,
  p_source text,
  p_action text,
  p_entity_refs jsonb,
  p_before_after jsonb
)
returns uuid
language sql
set search_path = ''
as $$
  insert into app.audit_events (actor_id, source, action, entity_refs, before_after)
  values (p_actor_id, p_source, p_action, coalesce(p_entity_refs, '{}'), coalesce(p_before_after, '{}'))
  returning id
$$;

create function app_private.record_version(
  p_entity_kind text,
  p_entity_id uuid,
  p_revision bigint,
  p_snapshot jsonb,
  p_changed_by uuid,
  p_reason text default null
)
returns uuid
language sql
set search_path = ''
as $$
  insert into app.business_entity_versions
    (entity_kind, entity_id, revision, sanitized_snapshot, changed_by, reason)
  values (p_entity_kind, p_entity_id, p_revision, p_snapshot, p_changed_by, p_reason)
  returning id
$$;

-- Stores a notification request with its recipients. Re-running with the same
-- event key (job retry) adds no duplicate event or delivery.
create function app_private.enqueue_notification(
  p_event_key text,
  p_event_kind text,
  p_subject_kind text,
  p_subject_id uuid,
  p_payload jsonb,
  p_recipient_ids uuid[]
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_event_id uuid;
begin
  insert into app.outbox_events (event_key, event_kind, subject_kind, subject_id, minimal_payload)
  values (p_event_key, p_event_kind, p_subject_kind, p_subject_id, coalesce(p_payload, '{}'))
  on conflict (event_key) do nothing
  returning id into v_event_id;

  if v_event_id is null then
    select e.id into strict v_event_id from app.outbox_events e where e.event_key = p_event_key;
  end if;

  insert into app.outbox_deliveries (event_id, recipient_id, next_attempt_at)
  select v_event_id, r.recipient_id, now()
    from unnest(coalesce(p_recipient_ids, '{}')) as r (recipient_id)
  on conflict (event_id, recipient_id) do nothing;

  return v_event_id;
end
$$;
