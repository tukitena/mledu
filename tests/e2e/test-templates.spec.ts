import { expect, test } from '@playwright/test'
import { FIXTURE_PASSWORD, signInThroughUi } from './support'

// GĐ 5 shared test template library (TEST-02) on desktop and mobile.
const unique = () => `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`

test('Admin creates a letter template, edits it into version 2, archives and restores it', async ({
  page,
}) => {
  await signInThroughUi(page, 'admin@example.com', FIXTURE_PASSWORD)
  await expect(page.getByTestId('welcome')).toBeVisible()
  await page.goto('/admin/test-templates')

  const name = `Mẫu chữ E2E ${unique()}`
  await page.getByTestId('tt-create').click()
  const dialog = page.getByRole('dialog')
  await dialog.getByLabel('Tên template').fill(name)
  await page.getByTestId('tt-scale').selectOption('letter')
  // The default letter set of TEST-02 is offered.
  await expect(page.getByTestId('tt-level')).toHaveCount(4)
  await expect(dialog.getByLabel('Tên mức 1')).toHaveValue('Chưa đạt')
  await expect(dialog.getByLabel('Tên mức 4')).toHaveValue('Xuất sắc')

  // Duplicate labels (ignoring accents) are refused before saving.
  await page.getByTestId('tt-add-level').click()
  await dialog.getByLabel('Tên mức 5').fill('dat')
  await page.getByTestId('tt-submit').click()
  await expect(dialog.getByText('không trùng khi bỏ dấu')).toBeVisible()
  await dialog.getByLabel('Tên mức 5').fill('Khá')
  await page.getByTestId('tt-submit').click()

  const row = page.locator(`tr[data-name="${name}"]`)
  await expect(row).toContainText('Chưa đạt · Đạt · Tốt · Xuất sắc · Khá')
  await expect(row).toContainText('v1')

  // Editing creates version 2; version 1 stays in the history.
  await row.getByRole('button', { name: `Thao tác: ${name}` }).click()
  await row.locator('[data-action="edit"]').click()
  await page.getByTestId('tt-scale').selectOption('numeric')
  await dialog.getByLabel('Điểm tối đa').fill('8,255')
  await page.getByTestId('tt-submit').click()
  await expect(dialog.getByText('tối đa hai chữ số thập phân')).toBeVisible()
  await dialog.getByLabel('Điểm tối đa').fill('8,25')
  await page.getByTestId('tt-submit').click()
  await expect(row).toContainText('Tối đa 8,25')
  await expect(row).toContainText('v2')

  await row.getByRole('button', { name: `Thao tác: ${name}` }).click()
  await row.locator('[data-action="history"]').click()
  const history = page.getByTestId('tt-history')
  await expect(history.locator('tbody tr')).toHaveCount(2)
  await expect(history.locator('tbody tr').nth(1)).toContainText('Chưa đạt')
  await page.getByRole('dialog').getByRole('button', { name: 'Đóng', exact: true }).last().click()

  await row.getByRole('button', { name: `Thao tác: ${name}` }).click()
  await row.locator('[data-action="archive"]').click()
  await page.getByLabel('Lý do').fill('Không dùng nữa')
  await page.getByTestId('tt-confirm-archive').click()
  await expect(row).toHaveCount(0)

  await page.getByText('Hiện template đã lưu trữ').click()
  await expect(row).toContainText('Đã lưu trữ')
  await row.getByRole('button', { name: `Thao tác: ${name}` }).click()
  await row.locator('[data-action="restore"]').click()
  await page.getByTestId('tt-confirm-restore').click()
  await expect(row).toContainText('Đang dùng')
  await expect(row).toContainText('v2')
})

test('Admin stores an IELTS template with selected skills only', async ({ page }) => {
  await signInThroughUi(page, 'admin@example.com', FIXTURE_PASSWORD)
  await expect(page.getByTestId('welcome')).toBeVisible()
  await page.goto('/admin/test-templates')

  const name = `IELTS E2E ${unique()}`
  await page.getByTestId('tt-create').click()
  const dialog = page.getByRole('dialog')
  await dialog.getByLabel('Tên template').fill(name)
  await page.getByTestId('tt-scale').selectOption('ielts')
  await dialog.getByLabel('Writing (W)').uncheck()
  await dialog.getByLabel('Speaking (S)').uncheck()
  await dialog.getByLabel('Chế độ nhập L').selectOption('detailed')
  await expect(dialog.getByLabel('Số câu tối đa L')).toHaveValue('40')
  await page.getByTestId('tt-submit').click()

  const row = page.locator(`tr[data-name="${name}"]`)
  await expect(row).toContainText('IELTS')
  await expect(row.getByTestId('tt-summary')).toHaveText('L (40 câu), R')
})

test('Receptionists and Users have no template library', async ({ page }) => {
  for (const email of ['receptionist@example.com', 'user@example.com']) {
    await page.context().clearCookies()
    await page.goto('/login')
    await page.evaluate(() => localStorage.clear())
    await signInThroughUi(page, email, FIXTURE_PASSWORD)
    await expect(page.getByTestId('welcome')).toBeVisible()
    await expect(page.getByTestId('nav-test-templates')).toHaveCount(0)
    await page.goto('/admin/test-templates')
    await expect(page).toHaveURL(/\/$/)
  }
})
