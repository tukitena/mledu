import { env } from 'cloudflare:workers'

/** Fixture password from supabase/seeds/00-account.sql (local Auth only). */
const FIXTURE_PASSWORD = '123456ab'

export type Fixture = 'admin' | 'receptionist' | 'user' | 'pending' | 'disabled'

/** Signs in a seeded account through Supabase Auth and returns its access token. */
export async function signIn(fixture: Fixture): Promise<string> {
  const response = await fetch(`${env.SUPABASE_URL}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: env.SUPABASE_PUBLISHABLE_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: `${fixture}@example.com`, password: FIXTURE_PASSWORD }),
  })
  if (!response.ok) throw new Error(`sign-in failed for ${fixture}: ${response.status}`)
  const body = (await response.json()) as { access_token: string }
  return body.access_token
}

/** Ends the session server-side, like a user signing out on that device. */
export async function signOut(accessToken: string): Promise<void> {
  const response = await fetch(`${env.SUPABASE_URL}/auth/v1/logout?scope=local`, {
    method: 'POST',
    headers: { apikey: env.SUPABASE_PUBLISHABLE_KEY, Authorization: `Bearer ${accessToken}` },
  })
  if (response.status !== 204) throw new Error(`sign-out failed: ${response.status}`)
}
