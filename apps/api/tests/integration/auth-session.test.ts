import { env } from 'cloudflare:workers'
import { beforeAll, describe, expect, it } from 'vitest'
import {
  api,
  createAccount,
  createReadyAccount,
  errorCode,
  json,
  passwordSignIn,
  refresh,
  signIn,
  signInAs,
  uniqueEmail,
  waitForResetLink,
} from './support'

// Real Worker app + Supabase local (GoTrue, PostgREST, Mailpit). Every test
// creates its own accounts through the API, so tests do not share state.

let admin: string

beforeAll(async () => {
  admin = await signIn('admin')
})

const me = (token: string) => api('/v1/me', { token })
const loginStatus = async (email: string, password: string) =>
  (await passwordSignIn(email, password)).status

describe('account creation and first sign-in (AUTH-07, AUTH-01)', () => {
  it('creates a User that must replace the temporary password before business use', async () => {
    const account = await createAccount(admin, 'first')
    const session = await signInAs(account.email, account.password)

    const profile = await me(session.accessToken)
    expect(profile.status).toBe(200)
    expect(await json(profile)).toMatchObject({ accountType: 'user', mustChangePassword: true })

    const blocked = await api('/v1/me', {
      token: session.accessToken,
      method: 'PATCH',
      body: { fullName: 'X', phone: null, birthDate: null, expectedVersion: account.rowVersion },
    })
    expect(blocked.status).toBe(403)
    expect(await errorCode(blocked)).toBe('password_change_required')

    const short = await api('/v1/me/password', {
      token: session.accessToken,
      method: 'POST',
      body: { password: '1234567' },
    })
    expect(short.status).toBe(400)
    expect(await json(await me(session.accessToken))).toMatchObject({ mustChangePassword: true })

    // A second device signed in before the change.
    const other = await signInAs(account.email, account.password)

    const changed = await api('/v1/me/password', {
      token: session.accessToken,
      method: 'POST',
      body: { password: 'chosen-password-1' },
    })
    expect(changed.status).toBe(200)
    expect(await json(changed)).toEqual({ status: 'password_changed', signInRequired: false })

    expect(await json(await me(session.accessToken))).toMatchObject({ mustChangePassword: false })
    expect((await me(other.accessToken)).status).toBe(401)
    expect((await refresh(other.refreshToken)).ok).toBe(false)
    expect(await loginStatus(account.email, account.password)).toBe(400)
    expect(await loginStatus(account.email, 'chosen-password-1')).toBe(200)
  })

  it('refuses a duplicate email, also in another letter case', async () => {
    const account = await createAccount(admin, 'dup')
    const response = await api('/v1/accounts', {
      token: admin,
      method: 'POST',
      body: { email: ` ${account.email.toUpperCase()} `, fullName: 'Trùng email' },
    })
    expect(response.status).toBe(409)
    expect(await errorCode(response)).toBe('email_taken')
  })

  it('lets only Admin create accounts', async () => {
    const response = await api('/v1/accounts', {
      token: await signIn('receptionist'),
      method: 'POST',
      body: { email: uniqueEmail('nope'), fullName: 'Không được tạo' },
    })
    expect(response.status).toBe(403)
  })
})

describe('Auth cannot be used to skip the designed flows', () => {
  it('rejects a password change made directly with the Auth SDK', async () => {
    const account = await createReadyAccount(admin, 'sdk')
    const response = await fetch(`${env.SUPABASE_URL}/auth/v1/user`, {
      method: 'PUT',
      headers: {
        apikey: env.SUPABASE_PUBLISHABLE_KEY,
        Authorization: `Bearer ${account.session.accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ password: 'bypass-password' }),
    })
    expect(response.ok).toBe(false)
    expect(await loginStatus(account.email, 'bypass-password')).toBe(400)
    expect(await loginStatus(account.email, account.password)).toBe(200)
  })

  it('never changes the login email (AUTH-08)', async () => {
    const account = await createReadyAccount(admin, 'email')
    const response = await fetch(`${env.SUPABASE_URL}/auth/v1/user`, {
      method: 'PUT',
      headers: {
        apikey: env.SUPABASE_PUBLISHABLE_KEY,
        Authorization: `Bearer ${account.session.accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ email: uniqueEmail('changed') }),
    })
    expect(response.ok).toBe(false)
    expect(await json(await me(account.session.accessToken))).toMatchObject({
      email: account.email,
    })

    const patched = await api('/v1/me', {
      token: account.session.accessToken,
      method: 'PATCH',
      body: {
        fullName: 'Tên mới',
        phone: null,
        birthDate: null,
        email: 'x@example.com',
        expectedVersion: account.rowVersion,
      },
    })
    expect(patched.status).toBe(400)
  })
})

describe('disable and enable (AUTH-03)', () => {
  it('ends every session at once and keeps them ended after re-enabling', async () => {
    const account = await createReadyAccount(admin, 'disable')
    const second = await signInAs(account.email, account.password)

    const disabled = await api(`/v1/accounts/${account.id}/disable`, {
      token: admin,
      method: 'POST',
      body: { expectedVersion: account.rowVersion },
    })
    expect(disabled.status).toBe(200)
    const { rowVersion } = await json<{ rowVersion: number }>(disabled)

    for (const session of [account.session, second]) {
      const response = await me(session.accessToken)
      expect(response.status).toBe(401)
      expect(await errorCode(response)).toBe('account_disabled')
      expect((await refresh(session.refreshToken)).ok).toBe(false)
    }
    const denied = await passwordSignIn(account.email, account.password)
    expect(denied.status).toBe(403)
    expect(await json(denied)).toMatchObject({ msg: 'account_disabled' })

    const enabled = await api(`/v1/accounts/${account.id}/enable`, {
      token: admin,
      method: 'POST',
      body: { expectedVersion: rowVersion },
    })
    expect(enabled.status).toBe(200)
    expect((await me(account.session.accessToken)).status).toBe(401)
    expect((await refresh(second.refreshToken)).ok).toBe(false)
    expect(await loginStatus(account.email, account.password)).toBe(200)
  })

  it('refuses stale versions and Admin targets (AUTH-06)', async () => {
    const account = await createAccount(admin, 'stale')
    const stale = await api(`/v1/accounts/${account.id}/disable`, {
      token: admin,
      method: 'POST',
      body: { expectedVersion: account.rowVersion + 5 },
    })
    expect(stale.status).toBe(409)
    expect(await errorCode(stale)).toBe('version_conflict')

    const self = await json<{ id: string; rowVersion: number }>(await me(admin))
    const adminTarget = await api(`/v1/accounts/${self.id}/disable`, {
      token: admin,
      method: 'POST',
      body: { expectedVersion: self.rowVersion },
    })
    expect(adminTarget.status).toBe(403)
    expect(await errorCode(adminTarget)).toBe('admin_account_forbidden')
  })
})

describe('User <-> Receptionist (AUTH-07)', () => {
  it('applies the new type to the next request of the open session', async () => {
    const account = await createReadyAccount(admin, 'type')
    expect((await api('/v1/accounts', { token: account.session.accessToken })).status).toBe(403)

    const changed = await api(`/v1/accounts/${account.id}/type`, {
      token: admin,
      method: 'PUT',
      body: { accountType: 'receptionist', expectedVersion: account.rowVersion },
    })
    expect(changed.status).toBe(200)
    expect(await json(await me(account.session.accessToken))).toMatchObject({
      accountType: 'receptionist',
    })

    const promote = await api(`/v1/accounts/${account.id}/type`, {
      token: admin,
      method: 'PUT',
      body: { accountType: 'admin', expectedVersion: account.rowVersion + 1 },
    })
    expect(promote.status).toBe(400)
  })
})

describe('soft delete and restore (AUTH-04/05)', () => {
  it('blocks the account, keeps its email, and restores it enabled without old sessions', async () => {
    const account = await createReadyAccount(admin, 'delete')

    const missingReason = await api(`/v1/accounts/${account.id}/delete`, {
      token: admin,
      method: 'POST',
      body: { reason: '  ', expectedVersion: account.rowVersion },
    })
    expect(missingReason.status).toBe(400)

    const deleted = await api(`/v1/accounts/${account.id}/delete`, {
      token: admin,
      method: 'POST',
      body: { reason: 'Nghỉ việc', expectedVersion: account.rowVersion },
    })
    expect(deleted.status).toBe(200)
    const deletedBody = await json<{ status: string; rowVersion: number }>(deleted)
    expect(deletedBody.status).toBe('deleted')

    expect((await me(account.session.accessToken)).status).toBe(401)
    expect(await loginStatus(account.email, account.password)).toBe(403)
    const reuse = await api('/v1/accounts', {
      token: admin,
      method: 'POST',
      body: { email: account.email, fullName: 'Dùng lại email' },
    })
    expect(await errorCode(reuse)).toBe('email_taken')

    const restored = await api(`/v1/accounts/${account.id}/restore`, {
      token: admin,
      method: 'POST',
      body: { expectedVersion: deletedBody.rowVersion },
    })
    expect(await json(restored)).toMatchObject({ status: 'active', email: account.email })
    expect((await me(account.session.accessToken)).status).toBe(401)
    expect(await loginStatus(account.email, account.password)).toBe(200)
  })
})

describe('temporary password by Admin (AUTH-02)', () => {
  it('ends every session, retires the old password and forces a change', async () => {
    const account = await createReadyAccount(admin, 'temp')
    const issued = await api(`/v1/accounts/${account.id}/temporary-password`, {
      token: admin,
      method: 'POST',
      body: { expectedVersion: account.rowVersion },
    })
    expect(issued.status).toBe(200)
    const body = await json<{
      temporaryPassword: string
      account: { mustChangePassword: boolean }
    }>(issued)
    expect(body.account.mustChangePassword).toBe(true)
    expect(body.temporaryPassword).toMatch(/^[A-Za-z2-9]{12}$/)

    expect((await me(account.session.accessToken)).status).toBe(401)
    expect((await refresh(account.session.refreshToken)).ok).toBe(false)
    expect(await loginStatus(account.email, account.password)).toBe(400)

    const session = await signInAs(account.email, body.temporaryPassword)
    expect(await json(await me(session.accessToken))).toMatchObject({ mustChangePassword: true })
  })
})

describe('reset by email (AUTH-02)', () => {
  const requestReset = (email: string) =>
    api('/v1/auth/password-reset', { method: 'POST', body: { email } })
  const complete = (link: { tokenHash: string; type: string }, password: string) =>
    api('/v1/auth/password-reset/complete', { method: 'POST', body: { ...link, password } })

  it('answers the same for unknown addresses', async () => {
    const response = await requestReset(uniqueEmail('unknown'))
    expect(response.status).toBe(202)
    expect(await json(response)).toEqual({ status: 'accepted' })
  })

  it('resets once, ends every session, and refuses the link afterwards', async () => {
    const account = await createReadyAccount(admin, 'reset')
    expect((await requestReset(account.email)).status).toBe(202)
    const link = await waitForResetLink(account.email)

    const done = await complete(link, 'reset-password-1')
    expect(done.status).toBe(200)
    expect(await json(done)).toEqual({ status: 'password_changed', signInRequired: true })

    expect((await me(account.session.accessToken)).status).toBe(401)
    expect((await refresh(account.session.refreshToken)).ok).toBe(false)
    expect(await loginStatus(account.email, account.password)).toBe(400)
    expect(await loginStatus(account.email, 'reset-password-1')).toBe(200)

    const again = await complete(link, 'reset-password-2')
    expect(again.status).toBe(400)
    expect(await errorCode(again)).toBe('reset_link_invalid')
    expect(await loginStatus(account.email, 'reset-password-1')).toBe(200)
  })

  it('resets at most once when the same link is used concurrently (G1-01)', async () => {
    const account = await createReadyAccount(admin, 'race')
    await requestReset(account.email)
    const link = await waitForResetLink(account.email)

    const passwords = ['race-password-1', 'race-password-2', 'race-password-3']
    const responses = await Promise.all(passwords.map((password) => complete(link, password)))
    const succeeded = passwords.filter((_, index) => responses[index]!.status === 200)
    expect(succeeded).toHaveLength(1)

    for (const password of passwords) {
      expect(await loginStatus(account.email, password)).toBe(password === succeeded[0] ? 200 : 400)
    }
  })

  it('a new link replaces the old one, and a temporary password replaces both', async () => {
    const account = await createReadyAccount(admin, 'reissue')
    await requestReset(account.email)
    const first = await waitForResetLink(account.email, 1)
    // Local Auth allows one reset email per address per second.
    await new Promise((resolve) => setTimeout(resolve, 1_100))
    await requestReset(account.email)
    const second = await waitForResetLink(account.email, 2)
    expect(second.tokenHash).not.toBe(first.tokenHash)

    expect((await complete(first, 'old-link-password')).status).toBe(400)

    const issued = await api(`/v1/accounts/${account.id}/temporary-password`, {
      token: admin,
      method: 'POST',
      body: { expectedVersion: account.rowVersion },
    })
    expect(issued.status).toBe(200)
    const reset = await complete(second, 'after-temp-password')
    expect(reset.status).toBe(400)
    expect(await errorCode(reset)).toBe('reset_link_invalid')
    expect(await loginStatus(account.email, 'after-temp-password')).toBe(400)
  })

  it('does not reset or re-enable a disabled account', async () => {
    const account = await createReadyAccount(admin, 'resetoff')
    await api(`/v1/accounts/${account.id}/disable`, {
      token: admin,
      method: 'POST',
      body: { expectedVersion: account.rowVersion },
    })
    await requestReset(account.email)
    const link = await waitForResetLink(account.email)

    const response = await complete(link, 'disabled-reset-1')
    expect(response.status).toBe(400)
    expect(await errorCode(response)).toBe('reset_link_invalid')
    expect(await loginStatus(account.email, 'disabled-reset-1')).toBe(400)
    expect(await loginStatus(account.email, account.password)).toBe(403)
  })
})
