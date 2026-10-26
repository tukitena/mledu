import { createClient } from '@supabase/supabase-js'
import { REQUEST_ID_HEADER } from '@mledu/contracts/common'
import type { Database } from '../generated/database.types'
import type { Bindings } from '../env'

/** Only the `api` schema is exposed through the Data API (see supabase/config.toml). */
export type UserDb = ReturnType<typeof createUserClient>

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
