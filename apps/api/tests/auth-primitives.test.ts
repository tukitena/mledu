import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import { after, before, test } from 'node:test';
import { createApp } from '../src/spike-app.ts';
import { account as managedAccount, admin, auditCount, client, config, db, login, setup, teardown } from './support.ts';

// Baseline fixtures intentionally bypass the candidate Auth integration.
const account = (role = 'User', temporary = false) => managedAccount(role, temporary, false);

const app = createApp(config);
const observations: Record<string, unknown> = {
  scope: 'Unmanaged native baseline; controlled integration has separate tests.',
  generatedAt: new Date().toISOString(),
};
const business = (token: string) => app.request('/v1/business', { headers: { authorization: `Bearer ${token}` } });
before(() => setup());
after(async () => {
  writeFileSync(new URL('../../../tmp/auth-spike-observations.json', import.meta.url), JSON.stringify(observations, null, 2));
  await teardown();
});

test('Auth enforces minimum length without requiring mixed character classes', async () => {
  const user = await account();
  const weak = await admin.auth.admin.updateUserById(user.id, { password: '1234567' });
  assert.ok(weak.error);
  assert.ok((await login(user)).token);
  const valid = await admin.auth.admin.updateUserById(user.id, { password: 'abcdefgh' });
  assert.equal(valid.error, null);
  assert.ok((await login({ ...user, password: 'abcdefgh' })).token);
});

test('self password change plus signOut others preserves current session and rejects the other', async () => {
  const user = await account();
  const current = await login(user);
  const other = await login(user);
  const password = randomUUID();
  assert.equal((await current.auth.auth.updateUser({ password })).error, null);
  assert.equal((await current.auth.auth.signOut({ scope: 'others' })).error, null);
  assert.equal((await business(current.token)).status, 200);
  assert.equal((await business(other.token)).status, 403);
  assert.ok((await client().auth.signInWithPassword(user)).error);
  assert.ok((await login({ ...user, password })).token);
  observations.selfPasswordSessionPrimitive = 'PASS: current retained, other rejected; application audit not implemented';
});

test('recovery token can be verified only once, including two simultaneous requests', async (t) => {
  const user = await account();
  const link = await admin.auth.admin.generateLink({ type: 'recovery', email: user.email });
  assert.equal(link.error, null);
  const input = { token_hash: link.data.properties!.hashed_token, type: 'recovery' as const };
  const consumers = [client(), client()];
  const results = await Promise.all(consumers.map(c => c.auth.verifyOtp(input)));
  const verified = results.filter(r => !r.error && r.data.session).length;
  const updates = await Promise.all(consumers.map((c, i) => results[i].data.session
    ? c.auth.updateUser({ password: randomUUID() }) : Promise.resolve({ error: new Error('No recovery session') })));
  const updated = updates.filter(r => !r.error).length;
  observations.recoverySingleUse = { verified, passwordUpdates: updated, requiredMaximum: 1 };
  t.diagnostic(`Concurrent recovery: ${verified} verifications and ${updated} password updates succeeded; required maximum is 1.`);
  assert.equal(verified, 1);
  assert.equal(updated, 1);
  assert.ok((await client().auth.verifyOtp(input)).error);
  assert.equal(await auditCount(user.id), 0);
});

test('password recovery email reaches the local mailbox and the mailed link verifies', async () => {
  const user = await account();
  assert.equal((await client().auth.resetPasswordForEmail(user.email)).error, null);
  let messageId: string | undefined;
  for (let attempt = 0; attempt < 20; attempt++) {
    const listing = await (await fetch('http://127.0.0.1:54324/api/v1/messages')).json();
    messageId = listing.messages.find((m: { To: { Address: string }[] }) => m.To.some(a => a.Address === user.email))?.ID;
    if (messageId) break;
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  assert.ok(messageId, 'recovery email was not captured locally');
  const message = await (await fetch(`http://127.0.0.1:54324/api/v1/message/${messageId}`)).json();
  const text = message.HTML || message.Text;
  const match = text.match(/https?:[^\s"<>]+\/auth\/v1\/verify\?[^\s"<>]+/);
  assert.ok(match, 'email must contain a recovery verification link');
  const url = new URL(match[0].replaceAll('&amp;', '&'));
  const token = url.searchParams.get('token');
  assert.ok(token);
  assert.equal(url.searchParams.get('type'), 'recovery');
  assert.equal((await client().auth.verifyOtp({ token_hash: token, type: 'recovery' })).error, null);
  assert.equal(await auditCount(user.id), 0);
  observations.localRecoveryEmail = 'PASS: local SMTP delivery and mailed recovery link verified';
});

test('issuing a new recovery link invalidates the previous link', async () => {
  const user = await account();
  const previous = await admin.auth.admin.generateLink({ type: 'recovery', email: user.email });
  const current = await admin.auth.admin.generateLink({ type: 'recovery', email: user.email });
  assert.equal(previous.error, null);
  assert.equal(current.error, null);
  assert.ok((await client().auth.verifyOtp({ token_hash: previous.data.properties!.hashed_token, type: 'recovery' })).error);
  assert.equal((await client().auth.verifyOtp({ token_hash: current.data.properties!.hashed_token, type: 'recovery' })).error, null);
  observations.recoveryReissue = 'PASS: previous token rejected, latest token accepted';
});

test('recovery password update plus global signOut rejects all existing sessions and recovery session', async () => {
  const user = await account();
  const previous = [await login(user), await login(user)];
  const link = await admin.auth.admin.generateLink({ type: 'recovery', email: user.email });
  assert.equal(link.error, null);
  const recovery = client();
  const verified = await recovery.auth.verifyOtp({ token_hash: link.data.properties!.hashed_token, type: 'recovery' });
  assert.equal(verified.error, null);
  assert.ok(verified.data.session);
  const recoveryToken = verified.data.session.access_token;
  const password = randomUUID();
  assert.equal((await recovery.auth.updateUser({ password })).error, null);
  assert.equal((await recovery.auth.signOut({ scope: 'global' })).error, null);
  for (const token of [...previous.map(s => s.token), recoveryToken]) assert.equal((await business(token)).status, 403);
  assert.ok((await login({ ...user, password })).token);
  observations.recoverySessionPrimitive = 'PASS: global signout rejects previous and recovery sessions; audit gate remains';
});

test('temporary password primitives revoke old sessions and links and require a password change', async () => {
  const user = await account();
  const previous = [await login(user), await login(user)];
  const link = await admin.auth.admin.generateLink({ type: 'recovery', email: user.email });
  assert.equal(link.error, null);
  const password = randomUUID();
  assert.equal((await admin.auth.admin.updateUserById(user.id, { password })).error, null);
  const { rows } = await db.query('select count(*)::int as count from auth.sessions where user_id=$1', [user.id]);
  assert.equal(rows[0].count, 0);
  // Fixture setup for the gate, not a claim that the three writes are atomic.
  await db.query('update spike_private.accounts set must_change_password=true where user_id=$1', [user.id]);
  for (const session of previous) assert.equal((await business(session.token)).status, 403);
  assert.ok((await client().auth.signInWithPassword(user)).error);
  assert.ok((await client().auth.verifyOtp({ token_hash: link.data.properties!.hashed_token, type: 'recovery' })).error);
  const temporary = await login({ ...user, password });
  assert.equal((await business(temporary.token)).status, 403);
  const identity = await app.request('/v1/me', { headers: { authorization: `Bearer ${temporary.token}` } });
  assert.equal((await identity.json()).mustChangePassword, true);
  observations.temporaryPasswordPrimitives = 'PASS: Admin password update removed sessions/old link; fixture must-change flag blocks business; atomic application command not implemented';
});

test('OBSERVATION: Auth password update is not rolled back when the subsequent audit insert fails', async (t) => {
  const user = await account();
  const password = randomUUID();
  await db.query('insert into spike_private.test_audit_failures values ($1)', [user.id]);
  assert.equal((await admin.auth.admin.updateUserById(user.id, { password })).error, null);
  await assert.rejects(db.query(`insert into spike_private.audit_log(actor_id, target_id, action)
    values ($1, $1, 'password_changed')`, [user.id]), /INJECTED_AUDIT_FAILURE/);
  assert.equal(await auditCount(user.id), 0);
  assert.ok((await client().auth.signInWithPassword(user)).error);
  assert.ok((await login({ ...user, password })).token);
  observations.authPasswordAuditAtomicity = 'BLOCKED: password changed, audit failed, old password rejected, new password accepted';
  t.diagnostic('BASELINE GAP: this two-step native/audit observation is not acceptance of the controlled Auth integration.');
});

test('OBSERVATION: a status field alone is not an Auth ban (unmanaged baseline)', async (t) => {
  const user = await account();
  await db.query("update spike_private.accounts set status='disabled', revoked_before=clock_timestamp() where user_id=$1", [user.id]);
  const direct = await login(user);
  assert.equal((await business(direct.token)).status, 403);
  observations.nativeLoginWhileApplicationLocked = 'BLOCKED: direct Auth can issue tokens; guarded RPC/API denies business';
  t.diagnostic('BASELINE GAP: changing only a status field is not an Auth ban; controlled ban/hook integration is tested separately.');
});

test('native Auth ban prevents password login but still has a separate audit boundary', async () => {
  const user = await account();
  await login(user);
  assert.equal((await admin.auth.admin.updateUserById(user.id, { ban_duration: '876000h' })).error, null);
  assert.ok((await client().auth.signInWithPassword(user)).error);
  assert.equal((await admin.auth.admin.updateUserById(user.id, { ban_duration: 'none' })).error, null);
  assert.ok((await login(user)).token);
  observations.nativeBanPrimitive = 'PASS: ban blocks password login; ban/unban API plus application audit is not one transaction';
});
