import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { setTimeout } from 'node:timers/promises';
import { account, admin, auditCount, client, login, setup, teardown } from '../support.ts';

before(() => setup(false));
after(teardown);

test('recovery link works before 5 minutes and is rejected after 301 real seconds', { timeout: 330_000 }, async (t) => {
  const user = await account();
  const initial = await admin.auth.admin.generateLink({ type: 'recovery', email: user.email });
  assert.equal(initial.error, null);
  assert.equal((await client().auth.verifyOtp({ token_hash: initial.data.properties!.hashed_token, type: 'recovery' })).error, null);
  const expired = await admin.auth.admin.generateLink({ type: 'recovery', email: user.email });
  assert.equal(expired.error, null);
  const issuedAt = performance.now();
  t.diagnostic('Waiting 301 seconds against the real Auth server; no clock or auth-table manipulation.');
  await setTimeout(301_000);
  assert.ok(performance.now() - issuedAt >= 301_000);
  const result = await client().auth.verifyOtp({ token_hash: expired.data.properties!.hashed_token, type: 'recovery' });
  assert.equal(result.error?.code, 'otp_expired');
  assert.equal(result.data.session, null);
  assert.ok((await login(user)).token);
  assert.equal(await auditCount(user.id), 0);
});
