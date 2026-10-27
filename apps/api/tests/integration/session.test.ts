import { ErrorResponse } from '@mledu/contracts/common'
import { env } from 'cloudflare:workers'
import { describe, expect, it } from 'vitest'
import { createApp } from '../../src/app'
import type { CurrentSession } from '../../src/env'
import { requireSession } from '../../src/middleware/session'
import { FIXTURE_PASSWORD, passwordSignIn, signIn, signOut } from './support'

// Probe routes exercise the real middleware against Supabase local; they are
// not part of the deployed API.
const app = createApp()
app.get('/probe', requireSession(), (c) => c.json(c.get('session')))
app.get('/probe/password-change', requireSession({ allowPasswordChange: true }), (c) =>
  c.json(c.get('session')),
)

const call = (path: string, token: string) =>
  app.request(path, { headers: { Authorization: `Bearer ${token}` } }, env)

const errorCode = async (response: Response) =>
  ErrorResponse.parse(await response.json()).error.code

describe('requireSession (JWT forwarded to PostgreSQL)', () => {
  it('resolves each account type from the database', async () => {
    for (const fixture of ['admin', 'receptionist', 'user'] as const) {
      const response = await call('/probe', await signIn(fixture))
      expect(response.status).toBe(200)
      const session = (await response.json()) as CurrentSession
      expect(session.accountType).toBe(fixture)
      expect(session.mustChangePassword).toBe(false)
    }
  })

  it('holds back accounts that must change their temporary password', async () => {
    const token = await signIn('pending')
    const blocked = await call('/probe', token)
    expect(blocked.status).toBe(403)
    expect(await errorCode(blocked)).toBe('password_change_required')

    const allowed = await call('/probe/password-change', token)
    expect(allowed.status).toBe(200)
    expect(((await allowed.json()) as CurrentSession).mustChangePassword).toBe(true)
  })

  it('gets no token for a disabled account (access token hook)', async () => {
    // GĐ 2: the hook refuses the token; a session that was open before the
    // account was disabled is rejected by requireSession (auth-session.test.ts).
    const response = await passwordSignIn('disabled@example.com', FIXTURE_PASSWORD)
    expect(response.status).toBe(403)
    expect(await response.json()).toMatchObject({ msg: 'account_disabled' })
  })

  it('rejects a still-unexpired access token after its session signed out', async () => {
    const token = await signIn('user')
    expect((await call('/probe', token)).status).toBe(200)

    await signOut(token)

    const response = await call('/probe', token)
    expect(response.status).toBe(401)
    expect(await errorCode(response)).toBe('session_invalid')
  })

  it('rejects malformed or forged tokens', async () => {
    const response = await call('/probe', 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ4In0.c2ln')
    expect(response.status).toBe(401)
    expect(await errorCode(response)).toBe('session_invalid')
  })
})
