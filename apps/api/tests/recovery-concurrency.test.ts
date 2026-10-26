import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import { after, before, test } from 'node:test';
import { requestRecoveryLink } from './mailbox.ts';
import { account, client, config, setup, teardown } from './support.ts';

type Trial = { path: string; verified: number; passwordUpdates: number; distinctSessions: number };
const report: { generatedAt: string; environment: string; trials: Trial[] } = {
  generatedAt: new Date().toISOString(), environment: 'local mledu, GoTrue v2.197.0, native email recovery', trials: [],
};
before(() => setup(false));
after(async () => {
  writeFileSync(new URL('../../../tmp/recovery-email-concurrency.json', import.meta.url), JSON.stringify(report, null, 2));
  await teardown();
});

for (const mode of ['GET-email-link', 'POST-email-token'] as const) {
  test(`native single-use gate: ${mode}, three simultaneous-use trials`, async (t) => {
    const trials: Trial[] = [];
    for (let attempt = 0; attempt < 3; attempt++) {
      // Baseline native behavior is measured outside the experimental Auth bridge.
      const user = await account('User', false, false);
      const link = await requestRecoveryLink(user.email);
      const tokens = await Promise.all([0, 1].map(async () => {
        if (mode === 'POST-email-token') {
          const result = await client().auth.verifyOtp({ token_hash: link.searchParams.get('token')!, type: 'recovery' });
          return result.data.session?.access_token ?? null;
        }
        const response = await fetch(link, { redirect: 'manual' });
        const location = response.headers.get('location');
        await response.arrayBuffer();
        if (!location) return null;
        return new URLSearchParams(new URL(location).hash.slice(1)).get('access_token');
      }));
      const updates = await Promise.all(tokens.map(async token => {
        if (!token) return false;
        const response = await fetch(`${config.url}/auth/v1/user`, {
          method: 'PUT', headers: { apikey: config.anonKey, authorization: `Bearer ${token}`, 'content-type': 'application/json' },
          body: JSON.stringify({ password: randomUUID() }),
        });
        const body = await response.json();
        return response.ok && body.id === user.id;
      }));
      const sessions = tokens.filter((token): token is string => Boolean(token)).map(token =>
        JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString()).session_id as string);
      const trial = { path: mode, verified: sessions.length, passwordUpdates: updates.filter(Boolean).length, distinctSessions: new Set(sessions).size };
      trials.push(trial);
      report.trials.push(trial);
      t.diagnostic(JSON.stringify({ trial: attempt + 1, ...trial }));
    }
    // Strict requirement remains unchanged even if the native version fails it.
    for (const trial of trials) {
      assert.equal(trial.verified, 1, 'a mailed recovery link must authorize only one session');
      assert.equal(trial.passwordUpdates, 1, 'a mailed recovery link must authorize only one password update');
    }
  });
}
