import assert from 'node:assert/strict';
import { setTimeout } from 'node:timers/promises';
import { client, config } from './support.ts';

export async function requestRecoveryLink(email: string) {
  const sent = await client().auth.resetPasswordForEmail(email);
  assert.equal(sent.error, null, 'local Auth recovery request failed');
  let id: string | undefined;
  for (let attempt = 0; attempt < 30; attempt++) {
    const listing = await (await fetch('http://127.0.0.1:54324/api/v1/messages')).json();
    id = listing.messages.find((m: { To: { Address: string }[] }) => m.To.some(a => a.Address === email))?.ID;
    if (id) break;
    await setTimeout(100);
  }
  assert.ok(id, 'local mailbox has no recovery email for the fixture');
  const message = await (await fetch(`http://127.0.0.1:54324/api/v1/message/${id}`)).json();
  const match = (message.HTML || message.Text).match(/https?:[^\s"<>]+\/auth\/v1\/verify\?[^\s"<>]+/);
  assert.ok(match, 'local email contains no recovery link');
  const link = new URL(match[0].replaceAll('&amp;', '&'));
  assert.equal(link.origin, config.url);
  assert.equal(link.pathname, '/auth/v1/verify');
  assert.equal(link.searchParams.get('type'), 'recovery');
  assert.ok(link.searchParams.get('token'));
  return link;
}
