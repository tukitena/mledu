import { defineConfig, devices } from '@playwright/test'
import { readTestEnvironment, TEST_WORKER_CONFIG } from './scripts/testing/environment.ts'

// Separate Supabase, Worker and SPA for tests. Run npm run test:stack:start first.
const testEnv = readTestEnvironment()
const API_PORT = 8797
const WEB_PORT = 5183
const WEB_ORIGIN = `http://127.0.0.1:${WEB_PORT}`

export default defineConfig({
  testDir: 'tests/e2e',
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [['list'], ['html', { open: 'never' }]] : 'list',
  use: {
    baseURL: WEB_ORIGIN,
    trace: 'retain-on-failure',
  },
  projects: [
    { name: 'desktop', use: { ...devices['Desktop Chrome'] } },
    { name: 'mobile', use: { ...devices['Pixel 7'] } },
  ],
  // Dedicated ports, never reusing a running server, so e2e cannot hit another
  // local API (for example the GĐ 0 spike on 8787) by accident.
  webServer: [
    {
      command: `npx wrangler dev --config "${TEST_WORKER_CONFIG}" --port ${API_PORT}`,
      cwd: 'apps/api',
      url: `http://127.0.0.1:${API_PORT}/v1/health`,
      reuseExistingServer: false,
      timeout: 120_000,
    },
    {
      command: `npx vite --host 127.0.0.1 --port ${WEB_PORT} --strictPort`,
      cwd: 'apps/web',
      env: {
        VITE_API_BASE_URL: `http://127.0.0.1:${API_PORT}`,
        VITE_SUPABASE_URL: testEnv.SUPABASE_URL,
        VITE_SUPABASE_PUBLISHABLE_KEY: testEnv.SUPABASE_PUBLISHABLE_KEY,
      },
      url: WEB_ORIGIN,
      reuseExistingServer: false,
      timeout: 120_000,
    },
  ],
})
