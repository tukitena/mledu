import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, before, test } from 'node:test';
import { setTimeout } from 'node:timers/promises';
import pg from 'pg';
import { account, admin, auditCount, client, config, db, login, setup, teardown } from './support.ts';

before(() => setup());
after(teardown);

async function prepare(targetId: string, action: 'disable' | 'enable' | 'set_temporary_password') {
  const operator = await account('Admin');
  const session = await login(operator);
  const result = await session.auth.rpc('spike_prepare_auth_command', {
    p_target: targetId, p_action: action, p_request_id: randomUUID(),
  });
  assert.equal(result.error, null);
  assert.ok(result.data.commandId);
  return { id: result.data.commandId as string, operator, session };
}

const setPassword = (userId: string, commandId: string, password: string) => admin.auth.admin.updateUserById(userId, {
  password, app_metadata: { spike_auth_command: commandId },
});

test('temporary password, session revocation, must-change flag and labelled audit commit together', async () => {
  const user = await account();
  const previous = [await login(user), await login(user)];
  const command = await prepare(user.id, 'set_temporary_password');
  const password = randomUUID();
  assert.equal((await setPassword(user.id, command.id, password)).error, null);
  assert.ok((await client().auth.signInWithPassword(user)).error);
  const changed = await login({ ...user, password });
  const identity = await changed.auth.rpc('spike_identity');
  assert.equal(identity.data.mustChangePassword, true);
  assert.equal((await changed.auth.rpc('spike_business')).error?.code, '42501');
  for (const old of previous) {
    assert.equal((await old.auth.rpc('spike_identity')).error?.code, '42501');
    assert.ok((await old.auth.auth.refreshSession({ refresh_token: old.refreshToken })).error);
  }
  const { rows } = await db.query('select actor_id, target_id, action, command_id, before_data, after_data from spike_private.audit_log where target_id=$1', [user.id]);
  assert.equal(rows.length, 1);
  assert.equal(rows[0].actor_id, command.operator.id);
  assert.equal(rows[0].target_id, user.id);
  assert.equal(rows[0].action, 'set_temporary_password');
  assert.equal(rows[0].command_id, command.id);
  assert.equal(rows[0].before_data.must_change_password, false);
  assert.equal(rows[0].after_data.must_change_password, true);
  const serialized = JSON.stringify(rows);
  assert.ok(!serialized.includes(password));
  assert.ok(!serialized.includes('encrypted_password'));
});

test('audit failure rolls back native password, original sessions, metadata, flag and command consumption', async () => {
  const user = await account();
  const previous = [await login(user), await login(user)];
  const command = await prepare(user.id, 'set_temporary_password');
  const password = randomUUID();
  await db.query('insert into spike_private.test_audit_failures values ($1)', [user.id]);
  assert.ok((await setPassword(user.id, command.id, password)).error);
  assert.ok((await login(user)).token);
  assert.ok((await client().auth.signInWithPassword({ ...user, password })).error);
  for (const session of previous) {
    assert.equal((await session.auth.rpc('spike_business')).error, null);
    assert.equal((await session.auth.auth.refreshSession({ refresh_token: session.refreshToken })).error, null);
  }
  const { rows } = await db.query(`select a.must_change_password, a.revoked_before::text,
    c.consumed_at from spike_private.accounts a join spike_private.auth_commands c on c.target_id=a.user_id
    where c.id=$1`, [command.id]);
  assert.deepEqual(rows[0], { must_change_password: false, revoked_before: '-infinity', consumed_at: null });
  assert.notEqual((await admin.auth.admin.getUserById(user.id)).data.user?.app_metadata.spike_auth_command, command.id);
  assert.equal(await auditCount(user.id), 0);
  // Same command remains retryable after rollback; successful commit produces one audit.
  await db.query('delete from spike_private.test_audit_failures where target_id=$1', [user.id]);
  assert.equal((await setPassword(user.id, command.id, password)).error, null);
  assert.equal(await auditCount(user.id), 1);
});

test('controlled accounts reject native password changes without a command or with forged user metadata', async () => {
  const user = await account();
  const session = await login(user);
  assert.equal((await session.auth.auth.updateUser({ data: { spike_auth_command: randomUUID() } })).error, null);
  assert.ok((await session.auth.auth.updateUser({ password: randomUUID() })).error);
  assert.ok((await admin.auth.admin.updateUserById(user.id, { password: randomUUID() })).error);
  assert.ok((await login(user)).token);
  assert.equal(await auditCount(user.id), 0);
});

test('expired, wrong-target and wrong-action commands cannot alter native Auth', async () => {
  const user = await account();
  const other = await account();
  const command = await prepare(user.id, 'set_temporary_password');
  assert.ok((await setPassword(other.id, command.id, randomUUID())).error);
  assert.ok((await admin.auth.admin.updateUserById(user.id, {
    ban_duration: '876000h', app_metadata: { spike_auth_command: command.id },
  })).error);
  await db.query("update spike_private.auth_commands set expires_at=clock_timestamp()-interval '1 second' where id=$1", [command.id]);
  assert.ok((await setPassword(user.id, command.id, randomUUID())).error);
  for (const target of [user, other]) {
    assert.ok((await login(target)).token);
    assert.equal(await auditCount(target.id), 0);
  }
});

test('revoking the preparing actor session prevents commit through the service credential', async () => {
  const user = await account();
  const command = await prepare(user.id, 'disable');
  assert.equal((await command.session.auth.auth.signOut({ scope: 'global' })).error, null);
  assert.ok((await admin.auth.admin.updateUserById(user.id, {
    ban_duration: '876000h', app_metadata: { spike_auth_command: command.id },
  })).error);
  assert.ok((await login(user)).token);
  assert.equal(await auditCount(user.id), 0);
});

test('stale account version and consumed commands cannot be replayed', async () => {
  const user = await account();
  const stale = await prepare(user.id, 'set_temporary_password');
  await db.query('update spike_private.accounts set must_change_password=true where user_id=$1', [user.id]);
  assert.ok((await setPassword(user.id, stale.id, randomUUID())).error);
  const valid = await prepare(user.id, 'set_temporary_password');
  const password = randomUUID();
  assert.equal((await setPassword(user.id, valid.id, password)).error, null);
  assert.ok((await setPassword(user.id, valid.id, randomUUID())).error);
  assert.ok((await login({ ...user, password })).token);
  assert.equal(await auditCount(user.id), 1);
});

test('the legacy DB-only status RPC cannot bypass Auth integration', async () => {
  const operator = await account('Admin');
  const user = await account();
  const { auth } = await login(operator);
  assert.equal((await auth.rpc('spike_set_account', { p_target: user.id, p_operation: 'disable' })).error?.code, '42501');
  assert.equal((await auth.rpc('spike_set_account_legacy', { p_target: user.id, p_operation: 'disable' })).error?.code, '42501');
  assert.equal(await auditCount(user.id), 0);
  assert.ok((await login(user)).token);
});

test('actor logout waits for an already-authorized Auth transaction to finish committing', { timeout: 15_000 }, async () => {
  const user = await account();
  const command = await prepare(user.id, 'disable');
  const gate = new pg.Client({ connectionString: config.databaseUrl });
  await gate.connect();
  await gate.query('begin; lock table spike_private.audit_log in access exclusive mode');
  const mutation = admin.auth.admin.updateUserById(user.id, {
    ban_duration: '876000h', app_metadata: { spike_auth_command: command.id },
  });
  let logout: ReturnType<typeof command.session.auth.auth.signOut> | undefined;
  let logoutFinished = false;
  try {
    let auditBlocked = false;
    for (let attempt = 0; attempt < 150; attempt++) {
      const { rows } = await db.query("select count(*)::int n from pg_locks where relation='spike_private.audit_log'::regclass and not granted");
      if (rows[0].n > 0) { auditBlocked = true; break; }
      await setTimeout(20);
    }
    assert.ok(auditBlocked, 'Auth update must reach the deliberately blocked audit insert');
    logout = command.session.auth.auth.signOut({ scope: 'global' }).then(result => { logoutFinished = true; return result; });
    let logoutBlocked = false;
    for (let attempt = 0; attempt < 150; attempt++) {
      const { rows } = await db.query(`select count(*)::int n from pg_locks l join pg_stat_activity a on a.pid=l.pid
        where not l.granted and l.locktype='transactionid' and a.usename='supabase_auth_admin'`);
      if (rows[0].n > 0) { logoutBlocked = true; break; }
      if (logoutFinished) break;
      await setTimeout(20);
    }
    assert.equal(logoutFinished, false, 'logout must not commit between actor validation and Auth/audit commit');
    assert.ok(logoutBlocked, 'logout must be waiting on the actor session row lock');
  } finally {
    await gate.query('rollback');
    await gate.end();
    assert.equal((await mutation).error, null);
    if (logout) assert.equal((await logout).error, null);
  }
  assert.equal(await auditCount(user.id), 1);
});
