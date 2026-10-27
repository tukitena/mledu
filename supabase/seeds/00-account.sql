-- Temporary accounts for manually using the LOCAL application only.
-- CI/test accounts are independently maintained in tests/fixtures/database/00-account.sql.
-- Before replacing this file with real accounts, untrack it and remove its .gitignore exception.
-- Never deploy these fictional accounts or this shared password to staging/production.
-- All people are fictional; emails follow <role>@example.com (reserved domain).
-- Password for every account: 123456ab (meets the 8-character minimum, AUTH-01).
-- Inserted straight into auth.users, so Auth's password policy is not applied here.

with fixtures (id, email, full_name, account_type, is_enabled, must_change_password) as (
  values
    ('00000000-0000-4000-8000-000000000001'::uuid, 'admin@example.com', 'Quản trị Thử nghiệm', 'admin'::app.account_type, true, false),
    ('00000000-0000-4000-8000-000000000002'::uuid, 'receptionist@example.com', 'Lễ tân Thử nghiệm', 'receptionist'::app.account_type, true, false),
    ('00000000-0000-4000-8000-000000000003'::uuid, 'user@example.com', 'Giáo viên Thử nghiệm', 'user'::app.account_type, true, false),
    -- Request-time check fixtures: temporary password not changed / disabled account.
    ('00000000-0000-4000-8000-000000000004'::uuid, 'pending@example.com', 'Tài khoản Chờ đổi mật khẩu', 'user'::app.account_type, true, true),
    ('00000000-0000-4000-8000-000000000005'::uuid, 'disabled@example.com', 'Tài khoản Bị khóa', 'user'::app.account_type, false, false)
),
users as (
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change, email_change_token_new
  )
  select
    '00000000-0000-0000-0000-000000000000', f.id, 'authenticated', 'authenticated', f.email,
    extensions.crypt('123456ab', extensions.gen_salt('bf')), now(),
    '{"provider": "email", "providers": ["email"]}', '{}', now(), now(),
    '', '', '', ''
  from fixtures f
  returning id, email
),
identities as (
  insert into auth.identities (
    id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at
  )
  select
    gen_random_uuid(), u.id, u.id::text, 'email',
    jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
    now(), now(), now()
  from users u
  returning user_id
)
insert into app.account_profiles (
  id, login_email_key, full_name, account_type, is_enabled, must_change_password
)
select f.id, f.email, f.full_name, f.account_type, f.is_enabled, f.must_change_password
from fixtures f
join identities i on i.user_id = f.id;
