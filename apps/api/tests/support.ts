import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';
import pg from 'pg';
import { localConfig } from '../../../scripts/auth-spike/config.ts';

export const config = localConfig();
export const db = new pg.Client({ connectionString: config.databaseUrl });
export const client = () => createClient(config.url, config.anonKey, {
  auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
});
export const admin = createClient(config.url, config.serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});
const fixtures: string[] = [];
let injectionInstalled = false;

export async function account(role = 'User', temporary = false, controlled = true) {
  const email = `spike-${randomUUID()}@example.test`;
  const password = `Tmp-${randomUUID()}`;
  const { data, error } = await admin.auth.admin.createUser({ email, password, email_confirm: true });
  assert.equal(error, null, 'local fixture creation failed');
  assert.ok(data.user);
  fixtures.push(data.user.id);
  await db.query(`insert into spike_private.accounts(user_id, email, role, must_change_password, auth_controlled)
    values ($1, $2, $3, $4, $5)`, [data.user.id, email, role, temporary, controlled]);
  return { id: data.user.id, email, password };
}

export async function login(user: { email: string; password: string }) {
  const auth = client();
  const { data, error } = await auth.auth.signInWithPassword(user);
  assert.equal(error, null, 'fixture login failed');
  assert.ok(data.session);
  return { auth, token: data.session.access_token, refreshToken: data.session.refresh_token };
}

export async function setup(injectAuditFailures = true) {
  await db.connect();
  if (!injectAuditFailures) return;
  // Fault injection is installed only by tests; no API or JWT controls it.
  await db.query(`
    create table spike_private.test_audit_failures (target_id uuid primary key);
    create function spike_private.test_reject_audit() returns trigger
    language plpgsql set search_path = '' as $$
    begin
      if exists (select 1 from spike_private.test_audit_failures where target_id = new.target_id) then
        raise exception 'INJECTED_AUDIT_FAILURE';
      end if;
      return new;
    end $$;
    create trigger test_reject_audit before insert on spike_private.audit_log
      for each row execute function spike_private.test_reject_audit();
  `);
  injectionInstalled = true;
}

export async function teardown() {
  for (const id of fixtures) {
    const { error } = await admin.auth.admin.deleteUser(id);
    assert.equal(error, null, 'fixture cleanup failed');
  }
  if (injectionInstalled) await db.query(`
    drop trigger if exists test_reject_audit on spike_private.audit_log;
    drop function if exists spike_private.test_reject_audit();
    drop table if exists spike_private.test_audit_failures;
  `);
  await db.query('delete from spike_private.audit_log where target_id = any($1::uuid[])', [fixtures]);
  await db.end();
}

export async function auditCount(id: string) {
  const { rows } = await db.query('select count(*)::int as count from spike_private.audit_log where target_id=$1', [id]);
  return rows[0].count as number;
}
