import { cloudflareTest } from '@cloudflare/vitest-plugin'
import { defineConfig } from 'vitest/config'
import { readTestEnvironment, TEST_WORKER_CONFIG } from '../../scripts/testing/environment.ts'

/** Tests never read development secrets or fall back to the development database. */
function supabaseBindings() {
  const { SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, SUPABASE_SECRET_KEY } = readTestEnvironment()
  return { SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, SUPABASE_SECRET_KEY }
}

export default defineConfig({
  test: {
    projects: [
      {
        plugins: [
          cloudflareTest({
            miniflare: {
              compatibilityDate: '2026-10-01',
              // Unit tests never reach a database.
              bindings: {
                APP_ENV: 'test',
                APP_VERSION: 'test',
                ALLOWED_ORIGINS: 'http://127.0.0.1:5173',
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
            wrangler: { configPath: TEST_WORKER_CONFIG },
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
