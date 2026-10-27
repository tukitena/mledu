import { expect, test } from '@playwright/test'
import { FIXTURE_PASSWORD, signInThroughUi } from './support'

// GĐ 3 catalogs in the browser (CAT-01, SCHED-02/03/05) on desktop and mobile.
const unique = () => `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`

test('Admin creates, archives and restores a subject; archived names point to restoring', async ({
  page,
}) => {
  await signInThroughUi(page, 'admin@example.com', FIXTURE_PASSWORD)
  await expect(page.getByTestId('welcome')).toBeVisible()
  await page.goto('/catalogs?tab=subject')

  const name = `Môn E2E ${unique()}`
  await page.getByTestId('catalog-create').click()
  await page.getByLabel('Tên', { exact: true }).fill(name)
  await page.getByTestId('catalog-submit').click()
  const row = page.locator(`tr[data-name="${name}"]`)
  await expect(row).toContainText('Đang dùng')

  await row.getByRole('button', { name: `Thao tác: ${name}` }).click()
  await row.locator('[data-action="archive"]').click()
  await page.getByLabel('Lý do').fill('Ngừng dạy môn này')
  await page.getByTestId('catalog-confirm-archive').click()
  await expect(row).toHaveCount(0)

  // Same key, different accents/case: the API asks to restore the archived entry.
  await page.getByTestId('catalog-create').click()
  await page.getByLabel('Tên', { exact: true }).fill(name.toUpperCase())
  await page.getByTestId('catalog-submit').click()
  await expect(page.getByText('Tên này thuộc một mục đã lưu trữ')).toBeVisible()
  await page.getByRole('button', { name: 'Hủy' }).click()

  await page.getByText('Hiện mục đã lưu trữ').click()
  await expect(row).toContainText('Đã lưu trữ')
  await row.getByRole('button', { name: `Thao tác: ${name}` }).click()
  await row.locator('[data-action="restore"]').click()
  await page.getByTestId('catalog-confirm-restore').click()
  await expect(row).toContainText('Đang dùng')
})

test('Receptionist reads subjects only and manages rooms of a site', async ({ page }) => {
  await signInThroughUi(page, 'receptionist@example.com', FIXTURE_PASSWORD)
  await expect(page.getByTestId('welcome')).toBeVisible()
  await page.goto('/catalogs?tab=subject')
  await expect(page.getByTestId('catalog-table')).toContainText('Toán')
  await expect(page.getByTestId('catalog-create')).toHaveCount(0)

  await page.getByTestId('catalog-tab-room').click()
  const name = `P-${unique()}`
  await page.getByTestId('catalog-create').click()
  await page.getByRole('dialog').getByLabel('Địa điểm').selectOption({ label: 'Tòa B' })
  await page.getByLabel('Tên', { exact: true }).fill(name)
  await page.getByTestId('catalog-submit').click()
  await expect(page.locator(`tr[data-name="${name}"]`)).toContainText('Tòa B')

  // The same name again at the same site is refused by the backend.
  await page.getByTestId('catalog-create').click()
  await page.getByRole('dialog').getByLabel('Địa điểm').selectOption({ label: 'Tòa B' })
  await page.getByLabel('Tên', { exact: true }).fill(name.toLowerCase())
  await page.getByTestId('catalog-submit').click()
  await expect(page.getByText('Tên này đã được dùng')).toBeVisible()
})

test('a User has no catalog management page', async ({ page }) => {
  await signInThroughUi(page, 'user@example.com', FIXTURE_PASSWORD)
  await expect(page.getByTestId('welcome')).toBeVisible()
  await expect(page.getByTestId('nav-catalogs')).toHaveCount(0)
  await page.goto('/catalogs')
  await expect(page).toHaveURL(/\/$/)
})
