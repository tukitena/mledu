import { expect, test } from '@playwright/test'

test('the SPA loads and reaches the Worker API', async ({ page }) => {
  await page.goto('/')
  await expect(page.getByRole('heading', { name: 'MLedu' })).toBeVisible()
  await expect(page.getByTestId('api-status')).toHaveAttribute('data-state', 'ok')
})

test('unknown deep links render the SPA not-found page', async ({ page }) => {
  await page.goto('/khong-ton-tai/trang-con')
  await expect(page.getByRole('heading', { name: '404' })).toBeVisible()
})
