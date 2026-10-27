/** Public runtime configuration baked into the bundle at build time. */
export const config = {
  apiBaseUrl: import.meta.env.VITE_API_BASE_URL || 'http://127.0.0.1:8787',
  supabaseUrl: import.meta.env.VITE_SUPABASE_URL || 'http://127.0.0.1:54321',
  /** Publishable key: identifies the project only; it grants no data access. */
  supabasePublishableKey: import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY || '',
} as const
