/**
 * Browser-local preferences (UX-01). Storage may be unavailable (private mode,
 * blocked site data); the app then falls back to defaults.
 */
export function readPreference<T extends string>(
  key: string,
  allowed: readonly T[],
  fallback: T,
): T {
  try {
    const value = localStorage.getItem(key)
    return allowed.includes(value as T) ? (value as T) : fallback
  } catch {
    return fallback
  }
}

export function writePreference(key: string, value: string) {
  try {
    localStorage.setItem(key, value)
  } catch {
    // Not persisted; the choice still applies until the page is closed.
  }
}
