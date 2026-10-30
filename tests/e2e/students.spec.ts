import { expect, test } from '@playwright/test'
import { accessToken, apiCall, FIXTURE_PASSWORD, signInThroughUi } from './support'

// GĐ 3 student records in the browser (STU-04/01/02) on desktop and mobile.
const unique = () => `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`
const phone = () => `09${String(Math.floor(Math.random() * 1e8)).padStart(8, '0')}`

test('Receptionist creates, finds, soft-deletes and restores a student', async ({
  page,
}, testInfo) => {
  await signInThroughUi(page, 'receptionist@example.com', FIXTURE_PASSWORD)
  await expect(page.getByTestId('welcome')).toBeVisible()
  await page.goto('/students')

  const name = `Lê Thị Hoa ${unique()}`
  const parentPhone = phone()
  await page.getByTestId('student-create').click()
  await page.getByLabel('Họ tên học sinh').fill(name)
  // Invalid numbers are flagged before saving.
  await page.getByLabel('Số điện thoại phụ huynh 1').fill('09l2345678')
  await expect(page.getByText('Số không hợp lệ')).toBeVisible()
  await expect(page.getByTestId('student-submit')).toBeDisabled()
  await page
    .getByLabel('Số điện thoại phụ huynh 1')
    .fill(`+84 ${parentPhone.slice(1, 4)} ${parentPhone.slice(4)}`)
  const createdResponse = page.waitForResponse(
    (response) =>
      response.url().endsWith('/v1/students') &&
      response.request().method() === 'POST' &&
      response.status() === 201,
  )
  await page.getByTestId('student-submit').click()
  const created = (await (await createdResponse).json()) as { id: string; code: string }
  await expect(page.getByText(`Đã thêm ${name}.`, { exact: true })).toBeVisible()
  await expect(page.getByTestId('students-table')).not.toContainText(created.code)
  const token = await accessToken('receptionist@example.com', FIXTURE_PASSWORD)
  const byCode = await apiCall<{ items: unknown[]; total: number }>(
    token,
    `/v1/students?search=${created.code}`,
  )
  expect(byCode.body).toMatchObject({ items: [], total: 0 })
  await page.screenshot({ path: testInfo.outputPath('students-list.png') })

  // Search without accents finds the student; the phone is stored normalized.
  await page.getByTestId('student-search').fill(name.replace('Lê Thị', 'le thi'))
  await page.getByRole('button', { name: 'Tìm kiếm', exact: true }).click()
  const row = page.locator('tr', { hasText: name })
  await expect(row).toContainText(parentPhone)
  await expect(page.getByTestId('students-table').getByRole('columnheader')).toHaveCount(5)

  // Same name and parent phone again: refused without exposing internal codes.
  await page.getByTestId('student-create').click()
  await page.getByLabel('Họ tên học sinh').fill(name.toUpperCase())
  await page.getByLabel('Số điện thoại phụ huynh 1').fill(parentPhone)
  await page.getByTestId('student-submit').click()
  await expect(page.getByTestId('error-alert')).toContainText('Trùng học sinh đã có')
  await expect(page.getByTestId('error-alert')).not.toContainText(created.code)
  await page.screenshot({ path: testInfo.outputPath('students-duplicate.png') })
  await page.getByRole('button', { name: 'Hủy' }).click()

  await row.getByRole('button', { name: `Thao tác: ${name}` }).click()
  await row.locator('[data-action="delete"]').click()
  await page.getByLabel('Lý do').fill('Chuyển nơi ở')
  await page.getByTestId('student-confirm-delete').click()
  await expect(row).toHaveCount(0)

  await page.getByTestId('student-status-deleted').click()
  await page.getByTestId('student-search').fill(name)
  await page.getByRole('button', { name: 'Tìm kiếm', exact: true }).click()
  await row.getByRole('button', { name: `Thao tác: ${name}` }).click()
  await row.locator('[data-action="restore"]').click()
  await page.getByTestId('student-submit').click()
  await expect(page.getByText(`Đã khôi phục ${name}.`)).toBeVisible()
})

test('an unassigned User searches students but cannot change them', async ({ page }) => {
  await signInThroughUi(page, 'user@example.com', FIXTURE_PASSWORD)
  await expect(page.getByTestId('welcome')).toBeVisible()
  await page.goto('/students')
  await page.getByTestId('student-search').fill('nguyen van an')
  await page.getByRole('button', { name: 'Tìm kiếm', exact: true }).click()
  await expect(page.getByTestId('students-table')).toContainText('0900000001')
  await expect(page.getByTestId('students-table')).not.toContainText('HS000001')
  await expect(page.getByTestId('student-create')).toHaveCount(0)
  await expect(page.getByTestId('student-status-deleted')).toHaveCount(0)

  const row = page
    .getByTestId('students-table')
    .locator('tbody tr')
    .filter({ hasText: '0900000001' })
  await row.getByRole('button', { name: /^Thao tác/ }).click()
  await expect(row.locator('[data-action]')).toHaveCount(1)
  await row.locator('[data-action="view"]').click()
  await expect(page.getByTestId('student-detail')).toContainText('0900000001')
  await expect(page.getByTestId('student-detail')).not.toContainText('HS000001')
})
