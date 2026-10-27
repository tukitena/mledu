import type { AccountType } from '@mledu/contracts/common'
import type { RequestIdVariables } from 'hono/request-id'
import type * as Entrypoint from './index'
import type { UserDb } from './lib/supabase'

export type AppEnvironment = 'local' | 'test' | 'staging' | 'production'

/** Worker bindings. Values without a default are configured per environment. */
export interface Bindings {
  APP_ENV: AppEnvironment
  APP_VERSION: string
  /** Comma-separated list of browser origins allowed by CORS. */
  ALLOWED_ORIGINS: string
  SUPABASE_URL: string
  /** Public key; it only identifies the project and never grants broad writes. */
  SUPABASE_PUBLISHABLE_KEY: string
  /** Backend-only secret; bypasses RLS. Optional until a module needs it. */
  SUPABASE_SECRET_KEY?: string
}

/** Session checked against the database on this request (not trusted from JWT claims). */
export interface CurrentSession {
  accountId: string
  accountType: AccountType
  mustChangePassword: boolean
}

export interface Variables extends RequestIdVariables {
  session: CurrentSession
  /** Database client acting as the signed-in user (RLS and RPC checks apply). */
  db: UserDb
  /** The caller's access token; only for Auth calls made on the caller's behalf. */
  accessToken: string
}

export interface AppEnv {
  Bindings: Bindings
  Variables: Variables
}

declare global {
  namespace Cloudflare {
    // eslint-disable-next-line @typescript-eslint/no-empty-object-type
    interface Env extends Bindings {}
    interface GlobalProps {
      mainModule: typeof Entrypoint
    }
  }
}
