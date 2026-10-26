import { createApiClient } from '../lib/api-client'
import { config } from '../lib/config'

/** Shared API client. GĐ 2 adds the Supabase Auth session as `getAccessToken`. */
export const api = createApiClient({ baseUrl: config.apiBaseUrl })
