import { REQUEST_ID_HEADER } from '@mledu/contracts/common'
import type { Bindings } from '../env'
import { AppError } from './errors'

/**
 * Minimal Supabase Auth (GoTrue) REST calls. Request bodies carry passwords,
 * so they are never logged; only status and GoTrue's error code are returned.
 */
export interface GoTrueResult<T = unknown> {
  ok: boolean
  status: number
  /** GoTrue `error_code`, e.g. `same_password`, `weak_password`, `email_exists`. */
  errorCode?: string
  body?: T
}

interface CallOptions {
  method: 'GET' | 'POST' | 'PUT'
  /** Bearer token: a user's access token, or the secret key for Admin API calls. */
  bearer?: string
  /** API key header; the secret key for Admin API calls. */
  apiKey?: string
  body?: unknown
}

async function call<T>(
  env: Bindings,
  requestId: string,
  path: string,
  { method, bearer, apiKey, body }: CallOptions,
): Promise<GoTrueResult<T>> {
  const headers = new Headers({
    apikey: apiKey ?? env.SUPABASE_PUBLISHABLE_KEY,
    'Content-Type': 'application/json',
    [REQUEST_ID_HEADER]: requestId,
  })
  if (bearer) headers.set('Authorization', `Bearer ${bearer}`)

  let response: Response
  try {
    response = await fetch(`${env.SUPABASE_URL}/auth/v1${path}`, {
      method,
      headers,
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    })
  } catch {
    // A lost response is resolved by the caller (command status), never retried blindly.
    return { ok: false, status: 0 }
  }
  const payload = (await response.json().catch(() => null)) as Record<string, unknown> | null
  return {
    ok: response.ok,
    status: response.status,
    ...(typeof payload?.error_code === 'string' ? { errorCode: payload.error_code } : {}),
    ...(response.ok && payload ? { body: payload as T } : {}),
  }
}

const secretKey = (env: Bindings) => {
  if (!env.SUPABASE_SECRET_KEY) {
    throw new AppError(503, 'dependency_unavailable', 'dependency_unavailable')
  }
  return env.SUPABASE_SECRET_KEY
}

/** Own password change with the caller's session (keeps it, ends the others). */
export const updateOwnPassword = (
  env: Bindings,
  requestId: string,
  accessToken: string,
  password: string,
) => call(env, requestId, '/user', { method: 'PUT', bearer: accessToken, body: { password } })

/** Sends the reset email; GoTrue answers the same for unknown addresses. */
export const requestRecovery = (env: Bindings, requestId: string, email: string) =>
  call(env, requestId, '/recover', { method: 'POST', body: { email } })

/** Verifies an email-link token hash and returns the link session. */
export const verifyEmailLink = (
  env: Bindings,
  requestId: string,
  tokenHash: string,
  type: 'recovery' | 'magiclink',
) =>
  call<{ access_token: string }>(env, requestId, '/verify', {
    method: 'POST',
    body: { type, token_hash: tokenHash },
  })

/** Ends one session (best effort cleanup of a link session). */
export const signOutSession = (env: Bindings, requestId: string, accessToken: string) =>
  call(env, requestId, '/logout?scope=local', { method: 'POST', bearer: accessToken })

/** Admin API: creates a confirmed user bound to a prepared account.create command. */
export function adminCreateUser(
  env: Bindings,
  requestId: string,
  user: { id: string; email: string; password: string; commandId: string },
) {
  const key = secretKey(env)
  return call(env, requestId, '/admin/users', {
    method: 'POST',
    bearer: key,
    apiKey: key,
    body: {
      id: user.id,
      email: user.email,
      password: user.password,
      email_confirm: true,
      app_metadata: { mledu_command: user.commandId },
    },
  })
}

/** Admin API: sets a temporary password bound to a prepared command. */
export function adminSetPassword(
  env: Bindings,
  requestId: string,
  userId: string,
  password: string,
  commandId: string,
) {
  const key = secretKey(env)
  return call(env, requestId, `/admin/users/${encodeURIComponent(userId)}`, {
    method: 'PUT',
    bearer: key,
    apiKey: key,
    body: { password, app_metadata: { mledu_command: commandId } },
  })
}
