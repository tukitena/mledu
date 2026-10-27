import { workspacesFor, type ErrorCode, type Workspace } from '@mledu/contracts/common'
import { MyProfile } from '@mledu/contracts/profile'
import { computed, ref } from 'vue'
import { ApiError, createApiClient, type RequestOptions } from '../lib/api-client'
import { config } from '../lib/config'
import { readPreference, writePreference } from '../lib/storage'
import { auth } from '../lib/supabase-auth'
import type { z } from 'zod'

/**
 * Signed-in state of the SPA. The profile (and so the account type) always
 * comes from GET /v1/me, never from JWT claims, and is re-read periodically so
 * a type change by an Admin shows up without signing in again (AUTH-07).
 */
const client = createApiClient({
  baseUrl: config.apiBaseUrl,
  getAccessToken: async () => (await auth.getSession()).data.session?.access_token ?? null,
})

export const profile = ref<MyProfile | null>(null)
/** Why the session ended, shown on the sign-in page. */
export const endedReason = ref<ErrorCode | null>(null)

const SESSION_ENDING: ReadonlySet<ErrorCode> = new Set([
  'unauthenticated',
  'session_invalid',
  'account_disabled',
  'password_reset_required',
])

/** API call that ends the local session when the backend no longer accepts it. */
export async function apiRequest<T extends z.ZodType>(
  path: string,
  options: RequestOptions<T>,
): Promise<z.infer<T>> {
  try {
    return await client.request(path, options)
  } catch (error) {
    if (error instanceof ApiError && error.status === 401 && SESSION_ENDING.has(error.code)) {
      await endSession(error.code)
    }
    if (error instanceof ApiError && error.code === 'password_change_required' && profile.value) {
      profile.value = { ...profile.value, mustChangePassword: true }
    }
    throw error
  }
}

/** Raw API call for binary responses (avatar), with the caller's token. */
export async function apiFetch(path: string): Promise<Response> {
  const token = (await auth.getSession()).data.session?.access_token
  return fetch(`${config.apiBaseUrl.replace(/\/+$/, '')}${path}`, {
    headers: token ? { Authorization: `Bearer ${token}` } : {},
  })
}

export async function loadProfile(): Promise<MyProfile | null> {
  const { data } = await auth.getSession()
  if (!data.session) {
    profile.value = null
    return null
  }
  try {
    profile.value = await apiRequest('/v1/me', { schema: MyProfile })
  } catch (error) {
    if (!(error instanceof ApiError) || error.status !== 401) throw error
  }
  return profile.value
}

/** Sign-in uses the Auth SDK directly (techstack §1.1); everything else goes to the API. */
export async function signIn(email: string, password: string) {
  const { error } = await auth.signInWithPassword({ email: email.trim(), password })
  if (error) throw error
  endedReason.value = null
  return loadProfile()
}

export async function signOut() {
  await auth.signOut({ scope: 'local' }).catch(() => undefined)
  profile.value = null
}

async function endSession(reason: ErrorCode) {
  endedReason.value = reason
  await signOut()
}

// --- Workspace (A.2): presentation only; the API decides every permission. ---

const WORKSPACE_KEY = 'mledu.workspace'
const WORKSPACES = ['admin', 'receptionist', 'user'] as const
const workspaceChoice = ref<Workspace>(readPreference(WORKSPACE_KEY, WORKSPACES, 'admin'))

export const workspaces = computed<Workspace[]>(() =>
  profile.value ? workspacesFor(profile.value.accountType) : [],
)

export const workspace = computed<Workspace | null>({
  get: () =>
    workspaces.value.includes(workspaceChoice.value)
      ? workspaceChoice.value
      : (workspaces.value[0] ?? null),
  set: (value) => {
    if (value) {
      workspaceChoice.value = value
      writePreference(WORKSPACE_KEY, value)
    }
  },
})

// --- Keeping the profile current while the app is open. ---

const SYNC_INTERVAL_MS = 5 * 60_000
let syncTimer: ReturnType<typeof setInterval> | undefined

export function startProfileSync() {
  const sync = () => {
    if (profile.value && document.visibilityState === 'visible')
      void loadProfile().catch(() => undefined)
  }
  syncTimer ??= setInterval(sync, SYNC_INTERVAL_MS)
  auth.onAuthStateChange((event) => {
    if (event === 'SIGNED_OUT') profile.value = null
  })
}
