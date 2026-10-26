import assert from 'node:assert/strict';
import { after, before, describe, test } from 'node:test';
import { createApp } from '../src/spike-app.ts';
import { account, admin, auditCount, client, config, db, login, setup, teardown } from './support.ts';

const app = createApp(config);
const request = (path: string, token?: string, body?: unknown) => app.request(path, {
  method: body === undefined ? 'GET' : 'POST',
  headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), 'content-type': 'application/json' },
  ...(body === undefined ? {} : { body: JSON.stringify(body) }),
});

test('health is public and contains no credentials', async () => {
  const app = createApp({ url: 'http://127.0.0.1:54321', anonKey: 'not-needed-for-health' });
  const response = await app.request('/health');
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { status: 'ok', mode: 'auth-spike' });
});

describe('local HTTP + PostgreSQL authorization', () => {
  let operator: Awaited<ReturnType<typeof account>>;
  let adminToken: string;
  before(async () => {
    await setup();
    operator = await account('Admin');
    adminToken = (await login(operator)).token;
  });
  after(teardown);

  test('missing, invalid and tampered JWTs cannot access the API', async () => {
    assert.equal((await request('/v1/me')).status, 401);
    assert.equal((await request('/v1/me', 'not-a-jwt')).status, 401);
    const user = await account();
    const { token } = await login(user);
    const parts = token.split('.');
    const claims = JSON.parse(Buffer.from(parts[1], 'base64url').toString());
    claims.sub = operator.id;
    parts[1] = Buffer.from(JSON.stringify(claims)).toString('base64url');
    assert.equal((await request('/v1/me', parts.join('.'))).status, 401);
  });

  test('temporary password blocks business in HTTP and direct RPC', async () => {
    const user = await account('User', true);
    const { token, auth } = await login(user);
    const me = await request('/v1/me', token);
    assert.equal(me.status, 200);
    assert.equal((await me.json()).mustChangePassword, true);
    assert.equal((await request('/v1/business', token)).status, 403);
    const { error } = await auth.rpc('spike_business');
    assert.equal(error?.code, '42501');
  });

  test('locking immediately blocks two still-unexpired tokens', async () => {
    const user = await account();
    const first = await login(user);
    const second = await login(user);
    assert.equal((await request('/v1/business', first.token)).status, 200);
    assert.equal((await request('/v1/business', second.token)).status, 200);
    assert.equal((await request(`/v1/accounts/${user.id}/disable`, adminToken, {})).status, 200);
    assert.ok((await client().auth.signInWithPassword(user)).error, 'native Auth must reject login while locked');
    assert.ok((await client().auth.refreshSession({ refresh_token: first.refreshToken })).error, 'native Auth must reject refresh while locked');
    for (const session of [first, second]) {
      const claims = JSON.parse(Buffer.from(session.token.split('.')[1], 'base64url').toString());
      assert.ok(claims.exp > Date.now() / 1000);
      assert.equal((await request('/v1/business', session.token)).status, 403);
      assert.equal((await session.auth.rpc('spike_business')).error?.code, '42501');
    }
    assert.equal(await auditCount(user.id), 1);
  });

  test('unlock requires new login and cannot revive old sessions', async () => {
    const user = await account();
    const previous = await login(user);
    await request(`/v1/accounts/${user.id}/disable`, adminToken, {});
    assert.ok((await client().auth.signInWithPassword(user)).error);
    assert.equal((await request(`/v1/accounts/${user.id}/enable`, adminToken, {})).status, 200);
    assert.equal((await request('/v1/business', previous.token)).status, 403);
    const refreshed = await previous.auth.auth.refreshSession({ refresh_token: previous.refreshToken });
    assert.ok(refreshed.error, 'old refresh token must remain unusable after unban');
    assert.equal((await request('/v1/business', (await login(user)).token)).status, 200);
  });

  test('role change keeps both sessions and applies current permissions on next request', async () => {
    const user = await account('Receptionist');
    const sessions = [await login(user), await login(user)];
    for (const s of sessions) assert.equal((await request('/v1/reception', s.token)).status, 200);
    assert.equal((await request(`/v1/accounts/${user.id}/role`, adminToken, { role: 'User' })).status, 200);
    for (const s of sessions) {
      assert.equal((await request('/v1/reception', s.token)).status, 403);
      assert.equal((await request('/v1/business', s.token)).status, 200);
      assert.equal((await s.auth.auth.getUser()).error, null);
    }
  });

  test('active sessions refresh normally through the hook', async () => {
    const user = await account();
    const session = await login(user);
    const refreshed = await session.auth.auth.refreshSession({ refresh_token: session.refreshToken });
    assert.equal(refreshed.error, null);
    assert.ok(refreshed.data.session);
    assert.equal((await request('/v1/business', refreshed.data.session.access_token)).status, 200);
  });

  test('token hook rejects disabled account even when its native ban is absent', async () => {
    const user = await account();
    const session = await login(user);
    await db.query("update spike_private.accounts set status='disabled' where user_id=$1", [user.id]);
    assert.ok((await client().auth.signInWithPassword(user)).error);
    assert.ok((await client().auth.refreshSession({ refresh_token: session.refreshToken })).error);
    assert.equal(await auditCount(user.id), 0); // Fixture mutation, not an application command.
  });

  test('User cannot mutate own or other accounts through HTTP or direct RPC', async () => {
    const user = await account();
    const { token, auth } = await login(user);
    assert.equal((await request(`/v1/accounts/${user.id}/role`, token, { role: 'Receptionist' })).status, 403);
    assert.equal((await auth.rpc('spike_set_account', { p_target: operator.id, p_operation: 'disable' })).error?.code, '42501');
    assert.equal(await auditCount(user.id), 0);
  });

  test('Admin management and Admin promotion are rejected even by Admin', async () => {
    const user = await account();
    assert.equal((await request(`/v1/accounts/${operator.id}/disable`, adminToken, {})).status, 403);
    assert.equal((await request(`/v1/accounts/${user.id}/role`, adminToken, { role: 'Admin' })).status, 400);
    assert.equal(await auditCount(operator.id), 0);
    assert.equal(await auditCount(user.id), 0);
  });

  test('audit failure rolls back status and revocation cutoff, keeping both sessions usable', async () => {
    const user = await account();
    const sessions = [await login(user), await login(user)];
    await db.query('insert into spike_private.test_audit_failures values ($1)', [user.id]);
    const result = await request(`/v1/accounts/${user.id}/disable`, adminToken, {});
    assert.equal(result.status, 500);
    const error = await result.json();
    assert.equal(error.code, 'INTERNAL_ERROR');
    assert.ok(!JSON.stringify(error).includes('INJECTED_AUDIT_FAILURE'));
    const { rows } = await db.query('select status, revoked_before::text from spike_private.accounts where user_id=$1', [user.id]);
    assert.deepEqual(rows[0], { status: 'active', revoked_before: '-infinity' });
    assert.equal(await auditCount(user.id), 0);
    for (const s of sessions) assert.equal((await request('/v1/business', s.token)).status, 200);
    assert.ok((await login(user)).token, 'audit failure must also roll back native Auth ban');
    const native = await admin.auth.admin.getUserById(user.id);
    assert.ok(!native.data.user?.banned_until, 'failed lock must leave Auth unbanned');
  });

  test('concurrent duplicate disable produces one state change and one audit', async () => {
    const user = await account();
    const results = await Promise.all([
      request(`/v1/accounts/${user.id}/disable`, adminToken, {}),
      request(`/v1/accounts/${user.id}/disable`, adminToken, {}),
    ]);
    assert.deepEqual(results.map(r => r.status), [200, 200]);
    const bodies = await Promise.all(results.map(r => r.json()));
    assert.deepEqual(bodies.map(b => b.changed).sort(), [false, true]);
    assert.equal(await auditCount(user.id), 1);
  });

  test('failed enable keeps native ban, disabled state and the existing audit', async () => {
    const user = await account();
    assert.equal((await request(`/v1/accounts/${user.id}/disable`, adminToken, {})).status, 200);
    const before = (await db.query('select status, version, revoked_before from spike_private.accounts where user_id=$1', [user.id])).rows[0];
    await db.query('insert into spike_private.test_audit_failures values ($1)', [user.id]);
    assert.equal((await request(`/v1/accounts/${user.id}/enable`, adminToken, {})).status, 500);
    assert.deepEqual((await db.query('select status, version, revoked_before from spike_private.accounts where user_id=$1', [user.id])).rows[0], before);
    assert.ok((await client().auth.signInWithPassword(user)).error);
    assert.equal(await auditCount(user.id), 1);
  });

  test('no-op role change does not create a successful audit', async () => {
    const user = await account();
    const result = await request(`/v1/accounts/${user.id}/role`, adminToken, { role: 'User' });
    assert.equal(result.status, 200);
    assert.deepEqual(await result.json(), { changed: false });
    assert.equal(await auditCount(user.id), 0);
  });

  test('User to Receptionist is unavailable until assignment checks exist', async () => {
    const user = await account();
    const result = await request(`/v1/accounts/${user.id}/role`, adminToken, { role: 'Receptionist' });
    assert.equal(result.status, 501);
    assert.equal(await auditCount(user.id), 0);
    const { rows } = await db.query('select role from spike_private.accounts where user_id=$1', [user.id]);
    assert.equal(rows[0].role, 'User');
  });

  test('logged-out JWT is rejected before it expires', async () => {
    const user = await account();
    const { auth, token } = await login(user);
    assert.equal((await auth.auth.signOut({ scope: 'local' })).error, null);
    assert.equal((await request('/v1/business', token)).status, 403);
  });

  test('private account and audit tables are inaccessible through Data API', async () => {
    const user = await account();
    const { auth } = await login(user);
    for (const dbClient of [client(), auth]) {
      for (const table of ['accounts', 'audit_log']) {
        const result = await dbClient.schema('spike_private').from(table).select('*');
        assert.ok(result.error);
        assert.equal(result.data, null);
      }
    }
    assert.ok((await client().rpc('spike_identity')).error);
  });

  test('invalid input is rejected and every error carries a request ID', async () => {
    const invalidId = await request('/v1/accounts/not-a-uuid/disable', adminToken, {});
    assert.equal(invalidId.status, 400);
    const unauthenticated = await request('/v1/business');
    const body = await unauthenticated.json();
    assert.match(body.requestId, /^[0-9a-f-]{36}$/);
    assert.equal(unauthenticated.headers.get('x-request-id'), body.requestId);
  });
});
