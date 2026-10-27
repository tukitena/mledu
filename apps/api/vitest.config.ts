import { cloudflareTest } from '@cloudflare/vitest-plugin'
import { existsSync, readFileSync } from 'node:fs'
import { defineConfig } from 'vitest/config'

const wrangler = { configPath: './wrangler.jsonc' }

/** Local Supabase connection for integration tests: env vars first, then .dev.vars. */
function supabaseBindings() {
  const fromFile: Record<string, string> = {}
  const file = new URL('./.dev.vars', import.meta.url)
  if (existsSync(file)) {
    for (const line of readFileSync(file, 'utf8').split(/\r?\n/)) {
      const match = /^([A-Z0-9_]+)=(.*)$/.exec(line.trim())
      if (match) fromFile[match[1]!] = match[2]!
    }
  }
  const SUPABASE_URL = process.env.SUPABASE_URL ?? fromFile.SUPABASE_URL
  const SUPABASE_PUBLISHABLE_KEY =
    process.env.SUPABASE_PUBLISHABLE_KEY ?? fromFile.SUPABASE_PUBLISHABLE_KEY
  const SUPABASE_SECRET_KEY = process.env.SUPABASE_SECRET_KEY ?? fromFile.SUPABASE_SECRET_KEY
  if (!SUPABASE_URL || !SUPABASE_PUBLISHABLE_KEY || !SUPABASE_SECRET_KEY) {
    throw new Error(
      'Integration tests need Supabase local: run `supabase start` and `npm run local:env`.',
    )
  }
  if (!/^http:\/\/(127\.0\.0\.1|localhost):\d+$/.test(SUPABASE_URL)) {
    throw new Error('Integration tests only run against a local Supabase stack.')
  }
  return { SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, SUPABASE_SECRET_KEY }
}

export default defineConfig({
  test: {
    projects: [
      {
        plugins: [
          cloudflareTest({
            wrangler,
            miniflare: {
              // Unit tests never reach a database.
              bindings: {
                APP_ENV: 'test',
                SUPABASE_URL: 'http://127.0.0.1:9',
                SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_unit_test',
              },
            },
          }),
        ],
        test: { name: 'unit', include: ['src/**/*.test.ts'] },
      },
      {
        plugins: [
          cloudflareTest(() => ({
            wrangler,
            miniflare: { bindings: { APP_ENV: 'test', ...supabaseBindings() } },
          })),
        ],
        test: {
          name: 'integration',
          include: ['tests/integration/**/*.test.ts'],
          testTimeout: 30_000,
          // Files share the seeded accounts and Auth rate limits.
          fileParallelism: false,
        },
      },
    ],
  },
})
