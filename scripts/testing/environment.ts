import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

export const ROOT = fileURLToPath(new URL('../../', import.meta.url))
export const TEST_WORKDIR = fileURLToPath(new URL('../../tmp/supabase-test/', import.meta.url))
export const TEST_ENV_FILE = new URL('../../tmp/supabase-test/environment.json', import.meta.url)
export const TEST_WORKER_CONFIG = fileURLToPath(
  new URL('../../tmp/supabase-test/wrangler.json', import.meta.url),
)
export const TEST_PROJECT = 'mledu-test'

export interface TestEnvironment {
  projectId: string
  SUPABASE_URL: string
  SUPABASE_PUBLISHABLE_KEY: string
  SUPABASE_SECRET_KEY: string
  SUPABASE_ANON_KEY: string
  SUPABASE_SERVICE_ROLE_KEY: string
  TEST_DATABASE_URL: string
  TEST_MAILPIT_URL: string
}

export function assertTestEnvironment(value: unknown): asserts value is TestEnvironment {
  if (!value || typeof value !== 'object') throw new Error('Missing isolated test environment')
  const env = value as Record<string, unknown>
  if (
    env.projectId !== TEST_PROJECT ||
    env.SUPABASE_URL !== 'http://127.0.0.1:55321' ||
    env.TEST_MAILPIT_URL !== 'http://127.0.0.1:55324'
  ) {
    throw new Error(
      'Tests require mledu-test on its dedicated ports; refusing the development stack',
    )
  }
  for (const key of [
    'SUPABASE_PUBLISHABLE_KEY',
    'SUPABASE_SECRET_KEY',
    'SUPABASE_ANON_KEY',
    'SUPABASE_SERVICE_ROLE_KEY',
    'TEST_DATABASE_URL',
  ]) {
    if (typeof env[key] !== 'string' || !env[key]) throw new Error(`Missing test setting: ${key}`)
  }
  const db = new URL(env.TEST_DATABASE_URL as string)
  if (
    !['postgres:', 'postgresql:'].includes(db.protocol) ||
    db.hostname !== '127.0.0.1' ||
    db.port !== '55322' ||
    db.pathname !== '/postgres'
  ) {
    throw new Error('Tests may only connect to the isolated database on 127.0.0.1:55322')
  }
}

/** Never fall back to the app's .dev.vars/.env.local or an ambient database URL. */
export function readTestEnvironment(): TestEnvironment {
  let value: unknown
  try {
    value = JSON.parse(readFileSync(TEST_ENV_FILE, 'utf8'))
  } catch {
    throw new Error('Test stack is not configured. Run npm run test:stack:start first.')
  }
  assertTestEnvironment(value)
  return value
}
