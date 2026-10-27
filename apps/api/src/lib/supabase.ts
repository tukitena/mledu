import { createClient } from '@supabase/supabase-js'
import { REQUEST_ID_HEADER } from '@mledu/contracts/common'
import type { Database } from '../generated/database.types'
import type { Bindings } from '../env'
import { AppError } from './errors'

/** Only the `api` schema is exposed through the Data API (see supabase/config.toml). */
export type UserDb = ReturnType<typeof createUserClient>
export type ServiceClient = ReturnType<typeof createServiceClient>

const serverAuth = {
  persistSession: false,
  autoRefreshToken: false,
  detectSessionInUrl: false,
} as const

/**
 * Client that forwards the caller's JWT, so PostgreSQL sees `authenticated`
 * with the caller's `sub`/`session_id` and every RPC re-checks permissions.
 */
export function createUserClient(env: Bindings, accessToken: string, requestId: string) {
  return createClient<Database, 'api'>(env.SUPABASE_URL, env.SUPABASE_PUBLISHABLE_KEY, {
    db: { schema: 'api' },
    auth: serverAuth,
    global: {
      headers: { Authorization: `Bearer ${accessToken}`, [REQUEST_ID_HEADER]: requestId },
    },
  })
}

/** Client without a user; only reaches functions granted to `anon` (health check). */
export function createPublicClient(env: Bindings, requestId: string) {
  return createClient<Database, 'api'>(env.SUPABASE_URL, env.SUPABASE_PUBLISHABLE_KEY, {
    db: { schema: 'api' },
    auth: serverAuth,
    global: { headers: { [REQUEST_ID_HEADER]: requestId } },
  })
}

/**
 * Service-role client: bypasses RLS and reaches Storage and service-only RPCs.
 * Use it only after a user-scoped RPC has checked the caller, and only for the
 * step that needs it (Auth Admin API, avatar files, command status).
 */
export function createServiceClient(env: Bindings, requestId: string) {
  if (!env.SUPABASE_SECRET_KEY) {
    throw new AppError(503, 'dependency_unavailable', 'dependency_unavailable')
  }
  return createClient<Database, 'api'>(env.SUPABASE_URL, env.SUPABASE_SECRET_KEY, {
    db: { schema: 'api' },
    auth: serverAuth,
    global: { headers: { [REQUEST_ID_HEADER]: requestId } },
  })
}

/** Generated RPC argument types omit NULL; these SQL parameters accept it. */
export const nullable = <T>(value: T | null | undefined) => (value ?? null) as T
