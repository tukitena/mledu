-- A command RPC changes data, writes history, audit and notification requests in
-- one transaction; if audit or outbox fails, nothing is kept (AUD-01, NOTIF-01).
begin;
create extension if not exists pgtap with schema extensions;
select plan(26);

insert into auth.sessions (id, user_id, created_at, updated_at)
values
  ('10000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000001', now(), now()),
  ('10000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-000000000003', now(), now());

-- Sample command shaped like the real ones that follow in GĐ 2+: permission
-- check, version check, change, history, audit and notification request.
create function app_private.sample_rename_account(
  p_account_id uuid,
  p_full_name text,
  p_expected_version bigint
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor app.account_profiles;
  v_before app.account_profiles;
  v_after app.account_profiles;
begin
  v_actor := app_private.require_account(p_lock => true);
  if v_actor.account_type <> 'admin' then
    perform app_private.raise_api_error(403, 'forbidden');
  end if;

  select * into v_before from app.account_profiles a where a.id = p_account_id for update;
  if not found then
    perform app_private.raise_api_error(404, 'not_found');
  end if;
  if v_before.row_version <> p_expected_version then
    perform app_private.raise_api_error(409, 'version_conflict');
  end if;

  update app.account_profiles a
     set full_name = p_full_name, row_version = a.row_version + 1, updated_at = now()
   where a.id = p_account_id
  returning * into v_after;

  perform app_private.record_version('account_profile', v_after.id, v_after.row_version,
    jsonb_build_object('full_name', v_after.full_name), v_actor.id);
  perform app_private.write_audit(v_actor.id, 'app', 'account.profile.rename',
    jsonb_build_object('account_id', p_account_id),
    jsonb_build_object('before', jsonb_build_object('full_name', v_before.full_name),
                       'after', jsonb_build_object('full_name', v_after.full_name)));
  perform app_private.enqueue_notification(
    format('account.profile.renamed:%s:%s', p_account_id, v_after.row_version),
    'account.profile.renamed', 'account_profile', p_account_id,
    jsonb_build_object('revision', v_after.row_version), array[p_account_id]);

  return v_after.row_version;
end
$$;

-- Failure injection: raise on insert into the named table.
create table app_private.test_fail_on (table_name text primary key);
create function app_private.test_fail() returns trigger language plpgsql set search_path = '' as $$
begin
  if exists (select 1 from app_private.test_fail_on f where f.table_name = tg_table_name) then
    raise exception 'injected failure on %', tg_table_name;
  end if;
  return new;
end
$$;
create trigger zz_test_fail before insert on app.audit_events
  for each row execute function app_private.test_fail();
create trigger zz_test_fail before insert on app.outbox_events
  for each row execute function app_private.test_fail();

create function pg_temp.snapshot() returns text language sql as $$
  select format('name=%s version=%s history=%s audit=%s events=%s deliveries=%s',
    (select full_name from app.account_profiles where id = '00000000-0000-4000-8000-000000000003'),
    (select row_version from app.account_profiles where id = '00000000-0000-4000-8000-000000000003'),
    (select count(*) from app.business_entity_versions where changed_at = now()),
    (select count(*) from app.audit_events where created_at = now()),
    (select count(*) from app.outbox_events where created_at = now()),
    (select count(*) from app.outbox_deliveries where created_at = now()))
$$;

select set_config('request.jwt.claims', json_build_object(
  'sub', '00000000-0000-4000-8000-000000000001',
  'session_id', '10000000-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);

-- 1. Success: every part is written once.
select is(
  app_private.sample_rename_account('00000000-0000-4000-8000-000000000003', 'Giáo viên Đổi tên', 1),
  2::bigint, 'command succeeds and bumps the version');
select is(pg_temp.snapshot(),
  'name=Giáo viên Đổi tên version=2 history=1 audit=1 events=1 deliveries=1',
  'change, history, audit and notification request are all stored');
select is(
  (select actor_id from app.audit_events where created_at = now()), '00000000-0000-4000-8000-000000000001'::uuid,
  'audit records the acting account');
select ok(
  (select expires_at = created_at + interval '60 days' from app.audit_events where created_at = now()),
  'audit expires exactly 60 days after creation');
select is(
  (select before_after #>> '{before,full_name}' from app.audit_events where created_at = now()), 'Giáo viên Thử nghiệm',
  'audit keeps the previous value');

-- 2. Replaying the same event key (job retry) does not duplicate the notification.
select lives_ok($$
  select app_private.enqueue_notification('account.profile.renamed:00000000-0000-4000-8000-000000000003:2',
    'account.profile.renamed', 'account_profile', '00000000-0000-4000-8000-000000000003', '{}',
    array['00000000-0000-4000-8000-000000000003'::uuid])
$$, 'replaying an event key is accepted');
select is(pg_temp.snapshot(),
  'name=Giáo viên Đổi tên version=2 history=1 audit=1 events=1 deliveries=1',
  'replay adds no event or delivery');

-- 3. Stale version: rejected, unchanged.
select throws_ok(
  $$select app_private.sample_rename_account('00000000-0000-4000-8000-000000000003', 'Tên cũ', 1)$$,
  'PT409', 'version_conflict', 'stale expected version is rejected');

-- 4. Audit failure rolls back the change, history and outbox.
insert into app_private.test_fail_on values ('audit_events');
select throws_ok(
  $$select app_private.sample_rename_account('00000000-0000-4000-8000-000000000003', 'Không lưu', 2)$$,
  'P0001', 'injected failure on audit_events', 'audit failure aborts the command');
select is(pg_temp.snapshot(),
  'name=Giáo viên Đổi tên version=2 history=1 audit=1 events=1 deliveries=1',
  'nothing from the failed command is kept when audit fails');
delete from app_private.test_fail_on;

-- 5. Outbox failure (after audit succeeded inside the command) rolls back everything.
insert into app_private.test_fail_on values ('outbox_events');
select throws_ok(
  $$select app_private.sample_rename_account('00000000-0000-4000-8000-000000000003', 'Không lưu', 2)$$,
  'P0001', 'injected failure on outbox_events', 'notification request failure aborts the command');
select is(pg_temp.snapshot(),
  'name=Giáo viên Đổi tên version=2 history=1 audit=1 events=1 deliveries=1',
  'nothing from the failed command is kept when the outbox fails');
delete from app_private.test_fail_on;

-- 6. Permission is re-checked in the database with the current account type.
select set_config('request.jwt.claims', json_build_object(
  'sub', '00000000-0000-4000-8000-000000000003',
  'session_id', '10000000-0000-4000-8000-000000000003', 'role', 'authenticated')::text, true);
select throws_ok(
  $$select app_private.sample_rename_account('00000000-0000-4000-8000-000000000003', 'Tự đổi', 2)$$,
  'PT403', 'forbidden', 'non-admin is rejected');
select is(pg_temp.snapshot(),
  'name=Giáo viên Đổi tên version=2 history=1 audit=1 events=1 deliveries=1',
  'rejected command leaves no trace');

-- 7. Secrets never enter audit, history or outbox payloads.
select throws_ok(
  $$select app_private.write_audit(null, 'ops', 'account.password.reset', '{}', '{"after": {"new_password": "x"}}')$$,
  '22023', 'secret_in_payload', 'password values are rejected in audit');
select throws_ok(
  $$select app_private.write_audit(null, 'ops', 'portal.link.reroll', '{}', '{"items": [{"link_token": "x"}]}')$$,
  '22023', 'secret_in_payload', 'nested tokens are rejected in audit');
select throws_ok(
  $$select app_private.record_version('class_portal', gen_random_uuid(), 1, '{"signed_url": "x"}', null)$$,
  '22023', 'secret_in_payload', 'signed URLs are rejected in history');
select throws_ok(
  $$select app_private.write_audit(null, 'app', 'account.profile.rename', '{}', '{}')$$,
  '23514', null, 'app/excel audit requires an actor');

-- 8. Audit is append-only and its retention cannot be shortened by the caller.
insert into app.audit_events (source, action, created_at, expires_at)
values ('job', 'test.backdate_attempt', '2000-01-01', '2000-01-01');
select ok(
  (select created_at = now() from app.audit_events where action = 'test.backdate_attempt'),
  'caller-supplied creation time is ignored');
select throws_ok(
  $$update app.audit_events set action = 'test.changed'$$,
  '42501', 'append_only', 'audit rows cannot be updated');
select throws_ok(
  $$delete from app.audit_events$$,
  '42501', 'audit_not_expired', 'unexpired audit rows cannot be deleted');
select throws_ok(
  $$truncate app.audit_events$$,
  '42501', 'append_only', 'audit cannot be truncated');

-- Simulate a row created 61 days ago (triggers off only to place the fixture).
set local session_replication_role = replica;
insert into app.audit_events (source, action, created_at, expires_at)
values ('job', 'test.expired', now() - interval '61 days', now() - interval '61 days' + interval '1440 hours');
set local session_replication_role = origin;
select lives_ok(
  $$delete from app.audit_events where action = 'test.expired'$$,
  'expired audit rows can be removed by retention');
select is(pg_temp.snapshot(),
  'name=Giáo viên Đổi tên version=2 history=1 audit=2 events=1 deliveries=1',
  'retention removed only the expired row');

-- 9. History and outbox events are immutable.
select throws_ok(
  $$update app.business_entity_versions set reason = 'x'$$,
  '42501', 'append_only', 'history versions cannot be changed');
select throws_ok(
  $$delete from app.outbox_events$$,
  '42501', 'append_only', 'outbox events cannot be deleted');

select * from finish();
rollback;
