-- Accounts, access token hook, Auth command completion, profile and avatar
-- (AUTH-01–08, AUD-01). GoTrue itself is exercised by the API integration
-- tests; here its effect on auth.users is simulated and the completion
-- function is called the way the deferred trigger calls it.
begin;
create extension if not exists pgtap with schema extensions;
select plan(84);

-- Seed fixtures: 1 admin, 2 receptionist, 3 user, 4 pending password change, 5 disabled.
insert into auth.sessions (id, user_id, created_at, updated_at)
values
  ('20000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000001', now() - interval '1 minute', now()),
  ('20000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000002', now() - interval '1 minute', now()),
  ('20000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-000000000003', now() - interval '1 minute', now()),
  ('20000000-0000-4000-8000-000000000033', '00000000-0000-4000-8000-000000000003', now() - interval '1 minute', now()),
  ('20000000-0000-4000-8000-000000000004', '00000000-0000-4000-8000-000000000004', now() - interval '1 minute', now());
insert into auth.mfa_amr_claims (id, session_id, created_at, updated_at, authentication_method)
values
  (gen_random_uuid(), '20000000-0000-4000-8000-000000000001', now(), now(), 'password'),
  (gen_random_uuid(), '20000000-0000-4000-8000-000000000002', now(), now(), 'password'),
  (gen_random_uuid(), '20000000-0000-4000-8000-000000000003', now(), now(), 'password'),
  -- Session 33 was opened from an email link (recovery/magic link).
  (gen_random_uuid(), '20000000-0000-4000-8000-000000000033', now(), now(), 'otp'),
  (gen_random_uuid(), '20000000-0000-4000-8000-000000000004', now(), now(), 'password');

create function pg_temp.as_user(p_user int, p_session text default null)
returns void
language sql
as $$
  select set_config('request.jwt.claims', json_build_object(
    'sub', format('00000000-0000-4000-8000-%s', lpad(p_user::text, 12, '0')),
    'session_id', format('20000000-0000-4000-8000-%s', lpad(coalesce(p_session, p_user::text), 12, '0')),
    'role', 'authenticated')::text, true);
$$;
grant execute on function pg_temp.as_user(int, text) to authenticated;

create function pg_temp.hook(p_user int, p_session text, p_method text default 'password')
returns jsonb
language sql
as $$
  select app_private.access_token_hook(jsonb_build_object(
    'user_id', format('00000000-0000-4000-8000-%s', lpad(p_user::text, 12, '0')),
    'authentication_method', p_method,
    'claims', jsonb_build_object('session_id', p_session, 'role', 'authenticated')));
$$;

-- Audit rows written by this test: the audit trigger stamps them with the
-- transaction time, so rows left by other suites on a local stack are ignored.
create function pg_temp.audits(p_action text)
returns bigint
language sql
as $$ select count(*) from app.audit_events where action = p_action and created_at = now() $$;

-------------------------------------------------------------------------------
-- Privileges of the new entry points.
-------------------------------------------------------------------------------
select ok(not has_function_privilege('authenticated', 'api.auth_command_status(uuid)', 'execute'),
  'clients cannot read Auth command state');
select ok(not has_function_privilege('authenticated', 'api.ops_set_account(text, uuid, text, boolean)', 'execute'),
  'clients cannot call the operations tool RPCs');
select ok(not has_function_privilege('anon', 'api.prepare_account_create(text, text, text, date)', 'execute'),
  'anon cannot prepare account creation');
select ok(not has_function_privilege('authenticated', 'api.discard_avatar_upload(text)', 'execute')
       and not has_function_privilege('authenticated', 'api.mark_avatar_verified(text)', 'execute'),
  'clients cannot mark or discard avatar uploads');
select ok(has_function_privilege('supabase_auth_admin', 'app_private.access_token_hook(jsonb)', 'execute'),
  'Supabase Auth may run the access token hook');
select is(
  (select count(*)::int from pg_trigger where tgname = 'mledu_complete_auth_command' and tgdeferrable and tginitdeferred),
  1, 'auth.users changes are completed by a deferred trigger');
select is(
  (select count(*)::int from storage.buckets where id = 'avatars' and not public and file_size_limit = 5000000),
  1, 'avatars bucket is private and limited to 5,000,000 bytes');
select is(
  (select count(*)::int from pg_policies where schemaname = 'storage' and tablename = 'objects'
     and (qual like '%avatars%' or with_check like '%avatars%')),
  0, 'no Storage policy lets clients touch avatars directly');

-------------------------------------------------------------------------------
-- Access token hook.
-------------------------------------------------------------------------------
select ok(pg_temp.hook(3, '20000000-0000-4000-8000-000000000003') ? 'claims',
  'an active account gets its token');
select is(pg_temp.hook(5, '20000000-0000-4000-8000-000000000099') #>> '{error,message}', 'account_disabled',
  'a disabled account gets no token');
select is(pg_temp.hook(3, '20000000-0000-4000-8000-0000000000ff', 'token_refresh') #>> '{error,message}',
  'session_invalid', 'refresh of a session Auth no longer has is refused');

-------------------------------------------------------------------------------
-- Email-link sessions may only reset the password.
-------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user(3, '33');
select throws_ok('select * from api.current_session()', 'PT403', 'password_reset_required',
  'a session from an email link cannot use business functions');
select throws_ok('select api.prepare_password_reset()', 'PT400', 'reset_link_invalid',
  'reset needs a link newer than the last password change');
reset role;
update auth.users set recovery_sent_at = now() - interval '2 minutes'
 where id = '00000000-0000-4000-8000-000000000003';
set local role authenticated;
select pg_temp.as_user(3, '33');
select lives_ok('select api.prepare_password_reset()', 'an issued link may prepare one reset');
select pg_temp.as_user(3);
select throws_ok('select api.prepare_password_reset()', 'PT400', 'reset_link_invalid',
  'a password session cannot use the reset command');
reset role;

-------------------------------------------------------------------------------
-- Account listing (Admin only).
-------------------------------------------------------------------------------
create temp table expected_disabled as
  select count(*)::int as n from app.account_profiles where not is_enabled and deleted_at is null;
grant select on expected_disabled to authenticated;
set local role authenticated;
select pg_temp.as_user(1);
select is((api.list_accounts(p_status => 'disabled') ->> 'total')::int,
  (select n from expected_disabled),
  'Admin lists accounts by status');
select is(api.list_accounts(p_search => 'LỄ TÂN') #>> '{items,0,email}', 'receptionist@example.com',
  'search matches names regardless of case');
select is(api.get_account('00000000-0000-4000-8000-000000000003') ->> 'status', 'active',
  'Admin reads one account');
select pg_temp.as_user(2);
select throws_ok('select api.list_accounts()', 'PT403', 'forbidden', 'a Receptionist cannot list accounts');
reset role;

-------------------------------------------------------------------------------
-- Disable / enable (AUTH-03).
-------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user(2);
select throws_ok($$select api.set_account_enabled('00000000-0000-4000-8000-000000000003', false, 1)$$,
  'PT403', 'forbidden', 'a Receptionist cannot disable accounts');
select pg_temp.as_user(1);
select throws_ok($$select api.set_account_enabled('00000000-0000-4000-8000-000000000001', false, 1)$$,
  'PT403', 'admin_account_forbidden', 'an Admin cannot disable an Admin, not even itself (AUTH-06)');
select throws_ok($$select api.set_account_enabled('00000000-0000-4000-8000-000000000003', false, 99)$$,
  'PT409', 'version_conflict', 'a stale version is rejected');
select is(api.set_account_enabled('00000000-0000-4000-8000-000000000003', false, 1) ->> 'status', 'disabled',
  'Admin disables a User');
reset role;
select is(pg_temp.audits('account.disable'), 1::bigint, 'disabling writes one audit row');
select is((select count(*)::int from app.business_entity_versions
            where entity_id = '00000000-0000-4000-8000-000000000003' and revision = 2),
  1, 'disabling keeps a history version');
select is(pg_temp.hook(3, '20000000-0000-4000-8000-000000000003', 'token_refresh') #>> '{error,message}',
  'account_disabled', 'refresh is refused while disabled');
set local role authenticated;
select pg_temp.as_user(3);
select throws_ok('select * from api.current_session()', 'PT401', 'account_disabled',
  'the open session stops working immediately');
select pg_temp.as_user(1);
select is((api.set_account_enabled('00000000-0000-4000-8000-000000000003', false, 2) ->> 'rowVersion')::int, 2,
  'disabling a disabled account changes nothing');
select is(api.set_account_enabled('00000000-0000-4000-8000-000000000003', true, 2) ->> 'status', 'active',
  'Admin re-enables the account');
select pg_temp.as_user(3);
select throws_ok('select * from api.current_session()', 'PT401', 'session_invalid',
  'sessions ended by disabling stay ended after re-enabling');
reset role;
select is(pg_temp.audits('account.disable'), 1::bigint, 'a no-op writes no audit');
select is(pg_temp.hook(3, '20000000-0000-4000-8000-000000000003', 'token_refresh') #>> '{error,message}',
  'session_invalid', 'old sessions cannot refresh after re-enabling');

-- Fresh session for the user after re-enabling.
insert into auth.sessions (id, user_id, created_at, updated_at)
values ('20000000-0000-4000-8000-000000000333', '00000000-0000-4000-8000-000000000003', clock_timestamp(), now());
insert into auth.mfa_amr_claims (id, session_id, created_at, updated_at, authentication_method)
values (gen_random_uuid(), '20000000-0000-4000-8000-000000000333', now(), now(), 'password');

-------------------------------------------------------------------------------
-- User <-> Receptionist (AUTH-07).
-------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user(1);
select throws_ok($$select api.set_account_type('00000000-0000-4000-8000-000000000003', 'admin', 3)$$,
  'PT403', 'admin_account_forbidden', 'no Admin can be created through the type change');
select is(api.set_account_type('00000000-0000-4000-8000-000000000003', 'receptionist', 3) ->> 'accountType',
  'receptionist', 'Admin changes User to Receptionist');
select pg_temp.as_user(3, '333');
select is((select account_type from api.current_session()), 'receptionist',
  'the open session uses the new type on its next request');
select throws_ok($$select api.set_account_type('00000000-0000-4000-8000-000000000003', 'user', 4)$$,
  'PT403', 'forbidden', 'an account cannot change its own type');
select pg_temp.as_user(1);
select is(api.set_account_type('00000000-0000-4000-8000-000000000003', 'user', 4) ->> 'accountType',
  'user', 'Admin changes Receptionist back to User');
reset role;
select is(pg_temp.audits('account.type.change'), 2::bigint, 'each type change is audited');

-------------------------------------------------------------------------------
-- Soft delete / restore (AUTH-04/05) and audit failure.
-------------------------------------------------------------------------------
create table app_private.test_fail_audit (on_ boolean);
create function app_private.test_fail_audit() returns trigger language plpgsql set search_path = '' as $$
begin
  if exists (select 1 from app_private.test_fail_audit) then
    raise exception 'injected audit failure';
  end if;
  return new;
end
$$;
create trigger zz_test_fail before insert on app.audit_events
  for each row execute function app_private.test_fail_audit();

set local role authenticated;
select pg_temp.as_user(1);
select throws_ok($$select api.soft_delete_account('00000000-0000-4000-8000-000000000003', '   ', 5)$$,
  'PT400', 'validation_failed', 'soft delete requires a reason');
reset role;
insert into app_private.test_fail_audit values (true);
set local role authenticated;
select pg_temp.as_user(1);
select throws_ok($$select api.soft_delete_account('00000000-0000-4000-8000-000000000003', 'Nghỉ việc', 5)$$,
  'P0001', 'injected audit failure', 'audit failure aborts the soft delete');
reset role;
delete from app_private.test_fail_audit;
select is((select deleted_at is null and row_version = 5 from app.account_profiles
            where id = '00000000-0000-4000-8000-000000000003'), true,
  'nothing changes when the audit cannot be written');
set local role authenticated;
select pg_temp.as_user(1);
select is(api.soft_delete_account('00000000-0000-4000-8000-000000000003', 'Nghỉ việc', 5) ->> 'status',
  'deleted', 'Admin soft-deletes the account');
select throws_ok($$select api.soft_delete_account('00000000-0000-4000-8000-000000000003', 'Lần nữa', 6)$$,
  'PT409', 'invalid_state', 'a deleted account is not deleted again');
select throws_ok($$select * from api.prepare_account_create('USER@example.com ', 'Người khác')$$,
  'PT409', 'email_taken', 'the email of a soft-deleted account cannot be reused');
select pg_temp.as_user(3, '333');
select throws_ok('select * from api.current_session()', 'PT401', 'account_disabled',
  'a soft-deleted account cannot use its session');
select pg_temp.as_user(1);
select throws_ok($$select api.restore_account('00000000-0000-4000-8000-000000000002', 1)$$,
  'PT409', 'invalid_state', 'only a deleted account can be restored');
select is(api.restore_account('00000000-0000-4000-8000-000000000003', 6) ->> 'status', 'active',
  'restore enables the account again');
select pg_temp.as_user(3, '333');
select throws_ok('select * from api.current_session()', 'PT401', 'session_invalid',
  'sessions ended by the deletion stay ended after restore');
reset role;
select is((select deleted_at is null and deleted_reason is null and login_email_key = 'user@example.com'
             from app.account_profiles where id = '00000000-0000-4000-8000-000000000003'), true,
  'restore keeps the same account and email');
select is((select sanitized_snapshot ->> 'deleted_reason' from app.business_entity_versions
            where entity_id = '00000000-0000-4000-8000-000000000003' and revision = 6),
  'Nghỉ việc', 'history keeps the deletion and its reason after restore');

-------------------------------------------------------------------------------
-- Account creation and password commands, completed as GoTrue's trigger does.
-------------------------------------------------------------------------------
create temp table created (command_id uuid, account_id uuid);
create temp table temp_cmd (id uuid);
create temp table upload (path text);
grant all on created, temp_cmd, upload to authenticated;

set local role authenticated;
select pg_temp.as_user(2);
select throws_ok($$select * from api.prepare_account_create('a@example.com', 'Ai đó')$$,
  'PT403', 'forbidden', 'only Admin creates accounts');
select pg_temp.as_user(1);
select throws_ok($$select * from api.prepare_account_create('không phải email', 'Ai đó')$$,
  'PT400', 'validation_failed', 'invalid email is rejected');
insert into created select * from api.prepare_account_create(' New@Example.com', ' Người  Mới ', '090.123.4567', null);
reset role;

-- Without the command id GoTrue's insert cannot complete.
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, raw_app_meta_data,
  created_at, updated_at, confirmation_token, recovery_token, email_change, email_change_token_new)
select '00000000-0000-0000-0000-000000000000', account_id, 'authenticated', 'authenticated',
  'new@example.com', 'x', '{}', now(), now(), '', '', '', ''
from created;
select throws_ok($$select app_private.complete_auth_command((select account_id from created), 'insert')$$,
  '42501', 'auth_command_required', 'an Auth user without a command gets no account');
update auth.users set raw_app_meta_data = jsonb_build_object('mledu_command', (select command_id from created))
 where id = (select account_id from created);
select lives_ok($$select app_private.complete_auth_command((select account_id from created), 'insert')$$,
  'the prepared command completes the creation');
select results_eq(
  $$select login_email_key, full_name, account_type::text, must_change_password, phone
      from app.account_profiles where id = (select account_id from created)$$,
  $$values ('new@example.com', 'Người  Mới', 'user', true, '0901234567')$$,
  'the new account is a User that must change its temporary password');
select is(pg_temp.audits('account.create'), 1::bigint, 'creation is audited once');
select throws_ok($$select app_private.complete_auth_command((select account_id from created), 'insert')$$,
  '42501', 'auth_command_invalid', 'a command cannot be replayed');

-- Admin temporary password for the pending account (4).
set local role authenticated;
select pg_temp.as_user(1);
insert into temp_cmd select api.prepare_temporary_password('00000000-0000-4000-8000-000000000004', 1);
reset role;
update auth.users set raw_app_meta_data = jsonb_build_object('mledu_command', (select id from temp_cmd)),
  recovery_sent_at = now() - interval '1 minute'
 where id = '00000000-0000-4000-8000-000000000004';
insert into app_private.test_fail_audit values (true);
select throws_ok($$select app_private.complete_auth_command('00000000-0000-4000-8000-000000000004', 'password')$$,
  'P0001', 'injected audit failure', 'audit failure aborts the temporary password (and GoTrue''s transaction)');
delete from app_private.test_fail_audit;
select lives_ok($$select app_private.complete_auth_command('00000000-0000-4000-8000-000000000004', 'password')$$,
  'the Admin command completes the temporary password');
select is((select must_change_password and sessions_valid_after is not null and credentials_changed_at is not null
             from app.account_profiles where id = '00000000-0000-4000-8000-000000000004'), true,
  'a temporary password forces a change and ends every session');
select is((select before_after::text ~ '(?i)password' from app.audit_events
            where action = 'account.password.temporary' and created_at = now()), false,
  'the audit holds no password data');

-- A reset link issued before the temporary password no longer works.
insert into auth.sessions (id, user_id, created_at, updated_at)
values ('20000000-0000-4000-8000-000000000044', '00000000-0000-4000-8000-000000000004', clock_timestamp(), now());
insert into auth.mfa_amr_claims (id, session_id, created_at, updated_at, authentication_method)
values (gen_random_uuid(), '20000000-0000-4000-8000-000000000044', now(), now(), 'otp');
set local role authenticated;
select pg_temp.as_user(4, '44');
select throws_ok('select api.prepare_password_reset()', 'PT400', 'reset_link_invalid',
  'the temporary password invalidates earlier reset links');
reset role;

-- Own password change without a prepared command is refused (direct SDK call).
select throws_ok($$select app_private.complete_auth_command('00000000-0000-4000-8000-000000000002', 'password')$$,
  '42501', 'auth_command_required', 'a password change needs a command prepared through the API');

-- Own change by the Receptionist keeps the current session (GoTrue removes the others).
set local role authenticated;
select pg_temp.as_user(2);
select lives_ok('select api.prepare_password_change()', 'an account prepares its own password change');
reset role;
select lives_ok($$select app_private.complete_auth_command('00000000-0000-4000-8000-000000000002', 'password')$$,
  'the own change completes');
set local role authenticated;
select pg_temp.as_user(2);
select is((select must_change_password from api.current_session()), false,
  'the session that changed the password keeps working');
reset role;

-- Email reset by the User: one reset per link; every session ends.
update auth.users set recovery_sent_at = now() where id = '00000000-0000-4000-8000-000000000003';
insert into auth.sessions (id, user_id, created_at, updated_at)
values ('20000000-0000-4000-8000-000000000034', '00000000-0000-4000-8000-000000000003', clock_timestamp(), now());
insert into auth.mfa_amr_claims (id, session_id, created_at, updated_at, authentication_method)
values (gen_random_uuid(), '20000000-0000-4000-8000-000000000034', now(), now(), 'otp');
set local role authenticated;
select pg_temp.as_user(3, '34');
select lives_ok('select api.prepare_password_reset()', 'the link session prepares a reset');
select lives_ok('select api.prepare_password_reset()', 'a concurrent use of the same link prepares too');
reset role;
-- GoTrue removed the other sessions and cleared recovery_sent_at; session 34
-- performed the reset.
delete from auth.sessions where user_id = '00000000-0000-4000-8000-000000000003'
  and id <> '20000000-0000-4000-8000-000000000034';
update auth.users set recovery_sent_at = null where id = '00000000-0000-4000-8000-000000000003';
select lives_ok($$select app_private.complete_auth_command('00000000-0000-4000-8000-000000000003', 'password')$$,
  'the first reset completes');
select throws_ok($$select app_private.complete_auth_command('00000000-0000-4000-8000-000000000003', 'password')$$,
  '42501', null, 'the same link cannot reset a second time (its session already ended)');
set local role authenticated;
select pg_temp.as_user(3, '34');
select throws_ok('select api.prepare_password_reset()', 'PT401', 'session_invalid',
  'the reset ends every session, including the one that reset');
reset role;
select is(pg_temp.audits('account.password.reset'), 1::bigint, 'one audit for one reset');

-------------------------------------------------------------------------------
-- Own profile and avatar (AUTH-08).
-------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user(2);
select throws_ok($$select api.update_my_profile('Lễ tân', '123', null, 2)$$,
  'PT400', 'validation_failed', 'an invalid phone is rejected');
select throws_ok($$select api.update_my_profile('Lễ tân', null, '2999-01-01', 2)$$,
  'PT400', 'validation_failed', 'a birth date in the future is rejected');
select is(api.update_my_profile(' Lễ tân Mới ', '0912 345 678', '1990-05-01', 2) ->> 'fullName', 'Lễ tân Mới',
  'the account updates its own profile');
select throws_ok($$select api.update_my_profile('Khác', null, null, 2)$$,
  'PT409', 'version_conflict', 'a stale profile version is rejected');

insert into upload select api.reserve_avatar_upload('webp');
select ok((select path ~ '^00000000-0000-4000-8000-000000000002/[0-9a-f]{32}\.webp$' from upload),
  'avatar paths are generated under the caller''s folder');
select throws_ok($$select api.set_my_avatar((select path from upload), 3)$$,
  'PT400', 'avatar_invalid', 'a file the Worker has not checked cannot be committed');
reset role;
select lives_ok($$select api.mark_avatar_verified((select path from upload))$$,
  'the Worker marks the checked file');
set local role authenticated;
select pg_temp.as_user(1);
select throws_ok($$select api.set_my_avatar((select path from upload), 1)$$,
  'PT400', 'avatar_invalid', 'nobody else can commit that path');
select pg_temp.as_user(2);
select is(api.set_my_avatar((select path from upload), 3) #>> '{profile,avatarPath}', (select path from upload),
  'the owner commits the verified upload');
select throws_ok($$select api.set_my_avatar((select path from upload), 4)$$,
  'PT400', 'avatar_invalid', 'a path is committed only once');
reset role;
select is(pg_temp.audits('account.avatar.update'), 1::bigint, 'the avatar change is audited');
select is(api.discard_avatar_upload((select path from upload)), false,
  'the file in use is never reported as safe to delete');

select * from finish();
rollback;
