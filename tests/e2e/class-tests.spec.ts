import { expect, test } from '@playwright/test'
import { FIXTURE_PASSWORD, accessToken, apiCall, readyAccount, signInThroughUi } from './support'

// GĐ 5 tests of a class (TEST-05) on desktop and mobile: a test copied from a
// template and adjusted, a new configuration revision, and the assistant's view.
const unique = () => `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`
const day = (n: number) =>
  new Date(Date.now() + 7 * 3600_000 + n * 86_400_000).toISOString().slice(0, 10)

async function createClass(admin: string) {
  const klass = await apiCall<{ id: string }>(admin, '/v1/classes', 'POST', {
    name: `Học vụ E2E ${unique()}`,
    subjectId: '10000000-0000-4000-8000-000000000001',
    gradeId: '10000000-0000-4000-8000-000000000011',
    startDate: day(-10),
    endDate: day(30),
    note: null,
  })
  expect(klass.status).toBe(201)
  return klass.body.id
}

test('Admin copies a template into a test, adjusts it and edits only its information', async ({
  page,
}) => {
  const admin = await accessToken('admin@example.com', FIXTURE_PASSWORD)
  const classId = await createClass(admin)
  const templateName = `Mẫu E2E ${unique()}`
  const template = await apiCall(admin, '/v1/test-templates', 'POST', {
    name: templateName,
    description: null,
    config: {
      scaleKind: 'letter',
      inputMode: 'direct',
      levels: [{ label: 'Chưa đạt' }, { label: 'Đạt' }],
    },
  })
  expect(template.status).toBe(201)

  await signInThroughUi(page, 'admin@example.com', FIXTURE_PASSWORD)
  await expect(page.getByTestId('welcome')).toBeVisible()
  await page.goto(`/classes/${classId}?tab=tests`)
  await expect(page.getByText('Lớp chưa có bài kiểm tra.')).toBeVisible()

  await page.getByTestId('test-create').click()
  const dialog = page.getByRole('dialog')
  // Required fields are reported before anything is sent.
  await page.getByTestId('test-submit').click()
  await expect(dialog.getByText('Nhập tên bài')).toBeVisible()

  await page.getByTestId('test-name').fill('Đánh giá tháng')
  await page.getByTestId('test-template').selectOption({ label: `${templateName} · v1 · Chữ` })
  await expect(page.getByTestId('tt-level')).toHaveCount(2)
  await page.getByTestId('tt-add-level').click()
  await dialog.getByLabel('Tên mức 3').fill('Giỏi')
  await page.getByTestId('test-submit').click()

  const row = page.locator('tr[data-name="Đánh giá tháng"]')
  await expect(row.getByTestId('test-summary')).toContainText('Chưa đạt · Đạt · Giỏi')
  await expect(row.getByTestId('test-source')).toContainText(`Template ${templateName} · v1`)

  // The configuration is fixed once created: only the information can be edited.
  await row.getByRole('button', { name: 'Thao tác: Đánh giá tháng' }).click()
  await expect(row.locator('[data-action="config"]')).toHaveCount(0)
  await expect(row.locator('[data-action="history"]')).toHaveCount(0)
  await row.locator('[data-action="info"]').click()
  await expect(page.getByTestId('test-template')).toHaveCount(0)
  await page.getByTestId('test-name').fill('Đánh giá tháng 10')
  await page.getByTestId('test-submit').click()
  const renamed = page.locator('tr[data-name="Đánh giá tháng 10"]')
  await expect(renamed.getByTestId('test-summary')).toContainText('Chưa đạt · Đạt · Giỏi')
})

test('an assistant creates a test but cannot change the display option', async ({ page }) => {
  const account = await readyAccount('tests-assistant')
  const classId = await createClass(account.admin)
  const assigned = await apiCall(account.admin, `/v1/classes/${classId}/assignments`, 'POST', {
    accountId: account.id,
    role: 'assistant',
    startDate: day(-1),
    endDate: day(20),
    subjectNote: null,
  })
  expect(assigned.status).toBe(201)

  await signInThroughUi(page, account.email, account.password)
  await expect(page.getByTestId('welcome')).toBeVisible()
  await page.goto(`/classes/${classId}?tab=tests`)
  await page.getByTestId('test-create').click()
  const dialog = page.getByRole('dialog')
  await page.getByTestId('test-name').fill('Bài theo phần')
  await page.getByTestId('tt-mode').selectOption('components')
  await dialog.getByLabel('Tên phần 1').fill('Nghe')
  await dialog.getByLabel('Điểm tối đa 1').fill('10')
  await page.getByTestId('test-submit').click()

  const row = page.locator('tr[data-name="Bài theo phần"]')
  await expect(row.getByTestId('test-display')).toContainText('Ẩn chi tiết')
  await row.getByRole('button', { name: 'Thao tác: Bài theo phần' }).click()
  // No display action for an assistant (TEST-04).
  await expect(row.locator('[data-action="display"]')).toHaveCount(0)
})
