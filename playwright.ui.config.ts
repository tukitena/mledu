import { defineConfig, devices } from '@playwright/test'

// Presentation checks use fictional API responses; no database or account changes.
export default defineConfig({
  testDir: 'tests/ui',
  use: { baseURL: 'http://127.0.0.1:5184', screenshot: 'only-on-failure' },
  projects: [
    { name: 'desktop', use: { ...devices['Desktop Chrome'] } },
    { name: 'mobile', use: { ...devices['Pixel 7'] } },
  ],
  webServer: {
    command: 'node ../../node_modules/vite/bin/vite.js --host 127.0.0.1 --port 5184 --strictPort',
    cwd: 'apps/web',
    url: 'http://127.0.0.1:5184',
    reuseExistingServer: !process.env.CI,
  },
})
