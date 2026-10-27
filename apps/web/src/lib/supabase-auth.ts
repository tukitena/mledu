import { createClient } from '@supabase/supabase-js'
import { config } from './config'

/**
 * Supabase Auth in the browser is used for sign-in, token refresh and sign-out
 * only (techstack §1.1). Business data, password changes and resets go through
 * the Worker API. Sessions from URLs are ignored: reset links are completed by
 * the Worker and never sign the browser in.
 */
export const auth = createClient(config.supabaseUrl, config.supabasePublishableKey, {
  auth: {
    storageKey: 'mledu.auth',
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: false,
  },
}).auth
