/** Public runtime configuration baked into the bundle at build time. */
export const config = {
  apiBaseUrl: import.meta.env.VITE_API_BASE_URL || 'http://127.0.0.1:8787',
} as const
