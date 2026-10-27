import { REQUEST_ID_HEADER } from '@mledu/contracts/common'
import { env } from 'cloudflare:workers'
import { createApp } from '../../src/app'

/** Fixture password from supabase/seeds/00-account.sql (local Auth only). */
export const FIXTURE_PASSWORD = '123456ab'

export type Fixture = 'admin' | 'receptionist' | 'user' | 'pending' | 'disabled'

export interface AuthSession {
  accessToken: string
  refreshToken: string
}

const authHeaders = { apikey: env.SUPABASE_PUBLISHABLE_KEY, 'Content-Type': 'application/json' }

/** Password sign-in through Supabase Auth, as the SPA's Auth SDK does it. */
export async function passwordSignIn(email: string, password: string) {
  return fetch(`${env.SUPABASE_URL}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: authHeaders,
    body: JSON.stringify({ email, password }),
  })
}

export async function signInAs(email: string, password: string): Promise<AuthSession> {
  const response = await passwordSignIn(email, password)
  if (!response.ok) throw new Error(`sign-in failed for ${email}: ${response.status}`)
  const body = (await response.json()) as { access_token: string; refresh_token: string }
  return { accessToken: body.access_token, refreshToken: body.refresh_token }
}

/** Signs in a seeded account through Supabase Auth and returns its access token. */
export async function signIn(fixture: Fixture): Promise<string> {
  return (await signInAs(`${fixture}@example.com`, FIXTURE_PASSWORD)).accessToken
}

export async function refresh(refreshToken: string) {
  return fetch(`${env.SUPABASE_URL}/auth/v1/token?grant_type=refresh_token`, {
    method: 'POST',
    headers: authHeaders,
    body: JSON.stringify({ refresh_token: refreshToken }),
  })
}

/** Ends the session server-side, like a user signing out on that device. */
export async function signOut(accessToken: string): Promise<void> {
  const response = await fetch(`${env.SUPABASE_URL}/auth/v1/logout?scope=local`, {
    method: 'POST',
    headers: { apikey: env.SUPABASE_PUBLISHABLE_KEY, Authorization: `Bearer ${accessToken}` },
  })
  if (response.status !== 204) throw new Error(`sign-out failed: ${response.status}`)
}

const app = createApp()

/** Calls the Worker app (in workerd) with an optional bearer token and JSON body. */
export async function api(
  path: string,
  { token, method = 'GET', body }: { token?: string; method?: string; body?: unknown } = {},
) {
  const headers = new Headers({ [REQUEST_ID_HEADER]: crypto.randomUUID() })
  if (token) headers.set('Authorization', `Bearer ${token}`)
  if (body !== undefined) headers.set('Content-Type', 'application/json')
  return app.request(
    path,
    { method, headers, ...(body === undefined ? {} : { body: JSON.stringify(body) }) },
    env,
  )
}

export async function json<T = Record<string, unknown>>(response: Response): Promise<T> {
  return (await response.json()) as T
}

export const errorCode = async (response: Response) =>
  ((await response.json()) as { error: { code: string } }).error.code

let counter = 0
/** Unique fictional email on the reserved example.com domain. */
export const uniqueEmail = (label: string) =>
  `${label}.${Date.now().toString(36)}${(counter++).toString(36)}@example.com`

export interface CreatedAccount {
  id: string
  email: string
  password: string
  rowVersion: number
}

/** Admin creates an account through the API; returns its temporary password. */
export async function createAccount(adminToken: string, label: string): Promise<CreatedAccount> {
  const email = uniqueEmail(label)
  const response = await api('/v1/accounts', {
    token: adminToken,
    method: 'POST',
    body: { email, fullName: `Tài khoản ${label}` },
  })
  if (response.status !== 201) throw new Error(`create failed: ${response.status}`)
  const body = await json<{
    account: { id: string; rowVersion: number }
    temporaryPassword: string
  }>(response)
  return {
    id: body.account.id,
    email,
    password: body.temporaryPassword,
    rowVersion: body.account.rowVersion,
  }
}

/** Creates an account and completes the forced first password change. */
export async function createReadyAccount(adminToken: string, label: string) {
  const account = await createAccount(adminToken, label)
  const session = await signInAs(account.email, account.password)
  const password = `own-${crypto.randomUUID().slice(0, 8)}`
  const changed = await api('/v1/me/password', {
    token: session.accessToken,
    method: 'POST',
    body: { password },
  })
  if (changed.status !== 200) throw new Error(`password change failed: ${changed.status}`)
  const me = await json<{ rowVersion: number }>(await api('/v1/me', { token: session.accessToken }))
  return { ...account, password, session, rowVersion: me.rowVersion }
}

const MAILPIT_URL = 'http://127.0.0.1:54324'

/**
 * Reset link of the `count`-th email sent to the address by local Auth
 * (Mailpit). Each test uses its own address, so counting is enough.
 */
export async function waitForResetLink(email: string, count = 1) {
  for (let attempt = 0; attempt < 50; attempt++) {
    const listing = await json<{ messages: { ID: string; Created: string }[] }>(
      await fetch(`${MAILPIT_URL}/api/v1/search?query=${encodeURIComponent(`to:"${email}"`)}`),
    )
    if (listing.messages.length >= count) {
      const newest = [...listing.messages].sort((a, b) => b.Created.localeCompare(a.Created))[0]!
      const detail = await json<{ HTML: string; Text: string }>(
        await fetch(`${MAILPIT_URL}/api/v1/message/${newest.ID}`),
      )
      const match = /reset-password\?token_hash=([^&"\s]+)&(?:amp;)?type=(recovery|magiclink)/.exec(
        detail.HTML || detail.Text,
      )
      if (!match) throw new Error('reset email has no reset link')
      return {
        tokenHash: decodeURIComponent(match[1]!),
        type: match[2] as 'recovery' | 'magiclink',
      }
    }
    await new Promise((resolve) => setTimeout(resolve, 100))
  }
  throw new Error(`no reset email for ${email}`)
}
