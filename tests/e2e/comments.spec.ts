import { expect, test } from '@playwright/test'
import { FIXTURE_PASSWORD, accessToken, apiCall, signInThroughUi } from './support'

// GĐ 5 comments (COMMENT-01-03, ACAD-01) on desktop and mobile: a batch is
// created, filled, published, deleted with its impact shown and restored
// unpublished; a test comment is published apart from the score.
const unique = () => `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`
const day = (n: number) =>
  new Date(Date.now() + 7 * 3600_000 + n * 86_400_000).toISOString().slice(0, 10)

test('Admin writes, publishes, deletes and restores a comment batch', async ({ page }) => {
  const admin = await accessToken('admin@example.com', FIXTURE_PASSWORD)
  const klass = await apiCall<{ id: string }>(admin, '/v1/classes', 'POST', {
    name: `Nhận xét E2E ${unique()}`,
    subjectId: '10000000-0000-4000-8000-000000000001',
    gradeId: '10000000-0000-4000-8000-000000000011',
    startDate: day(-10),
    endDate: day(30),
    note: null,
  })
  expect(klass.status).toBe(201)
  const name = `Minh ${unique()}`
  const student = await apiCall<{ id: string }>(admin, '/v1/students', 'POST', {
    fullName: name,
    parentName: null,
    parentPhones: [],
    studentPhones: [],
    birthDate: null,
    school: null,
    generalNote: null,
  })
  expect(
    (
      await apiCall(admin, `/v1/classes/${klass.body.id}/students`, 'POST', {
        studentId: student.body.id,
        joinDate: day(-5),
        leaveDate: null,
        note: null,
      })
    ).status,
  ).toBe(201)
  expect(
    (
      await apiCall(admin, `/v1/classes/${klass.body.id}/tests`, 'POST', {
        name: 'Kiểm tra 15 phút',
        testOn: day(0),
        description: null,
        config: { scaleKind: 'numeric', inputMode: 'direct', maxScore: 10 },
        sourceTemplateVersionId: null,
      })
    ).status,
  ).toBe(201)

  await signInThroughUi(page, 'admin@example.com', FIXTURE_PASSWORD)
  await expect(page.getByTestId('welcome')).toBeVisible()

  // Test comment from the test row menu.
  await page.goto(`/classes/${klass.body.id}?tab=tests`)
  const testRow = page.locator('tr[data-name="Kiểm tra 15 phút"]')
  await testRow.getByRole('button', { name: 'Thao tác: Kiểm tra 15 phút' }).click()
  await testRow.locator('[data-action="comments"]').click()
  const dialog = page.getByRole('dialog')
  const row = dialog.locator(`tr[data-student="${name}"]`)
  await row.getByTestId('comment-body').fill('x'.repeat(1001))
  await expect(row.getByTestId('comment-length')).toHaveText('1001/1000')
  await expect(dialog.getByText('vượt 1000 ký tự')).toBeVisible()
  await row.getByTestId('comment-body').fill('<b>Làm bài cẩn thận</b>')
  await page.getByTestId('comments-save').click()
  await expect(row.getByTestId('comment-status')).toHaveText('Đã lưu')
  await row.getByTestId('comment-publish').click()
  await expect(row.getByTestId('comment-status')).toHaveText('Đã công bố')
  await expect(row.getByTestId('comment-body')).toBeDisabled()
  await dialog.getByRole('button', { name: 'Đóng' }).last().click()
  await expect(testRow.getByTestId('test-comment-count')).toHaveText('1 nhận xét')
  await expect(testRow.getByTestId('test-published-count')).toHaveCount(0)

  // TEST-06: deleting the test shows its impact and unpublishes the comment;
  // restoring brings it back unpublished.
  await testRow.getByRole('button', { name: 'Thao tác: Kiểm tra 15 phút' }).click()
  await testRow.locator('[data-action="archive"]').click()
  await expect(page.getByTestId('test-archive-impact')).toContainText(
    '0 kết quả (0 đang công bố) và 1 nhận xét (1 đang công bố)',
  )
  await page.getByTestId('test-archive-reason').fill('Nhập nhầm')
  await page.getByTestId('test-confirm-archive').click()
  await expect(testRow).toHaveCount(0)
  await page.getByLabel('Hiện bài đã xóa').check()
  await expect(testRow.getByTestId('test-archived')).toBeVisible()
  await testRow.getByRole('button', { name: 'Thao tác: Kiểm tra 15 phút' }).click()
  await testRow.locator('[data-action="restore"]').click()
  await page.getByTestId('test-confirm-restore').click()
  await expect(testRow.getByTestId('test-archived')).toHaveCount(0)
  await expect(testRow.getByTestId('test-comment-count')).toHaveText('1 nhận xét')

  // Batch tab.
  await page.goto(`/classes/${klass.body.id}?tab=comments`)
  await page.getByTestId('batch-create').click()
  await page.getByTestId('batch-name').fill('Tháng 10')
  await page.getByTestId('batch-save').click()
  const batchRow = page.locator('tr[data-name="Tháng 10"]')
  await batchRow.getByRole('button', { name: 'Thao tác: Tháng 10' }).click()
  await batchRow.locator('[data-action="open"]').click()
  await dialog.locator(`tr[data-student="${name}"]`).getByTestId('comment-body').fill('Tiến bộ')
  await page.getByTestId('comments-save').click()
  await page.getByTestId('comments-publish-all').click()
  await expect(dialog.getByTestId('comments-notice')).toContainText('Đã công bố 1 nhận xét')
  await dialog.getByRole('button', { name: 'Đóng' }).last().click()
  await expect(batchRow.getByTestId('batch-counts')).toContainText('1 đã công bố')

  await batchRow.getByRole('button', { name: 'Thao tác: Tháng 10' }).click()
  await batchRow.locator('[data-action="archive"]').click()
  await expect(page.getByTestId('batch-archive-impact')).toContainText('1 nhận xét, 1 đang công bố')
  await page.getByTestId('batch-reason').fill('Tạo nhầm')
  await page.getByTestId('batch-confirm-archive').click()
  await expect(batchRow).toHaveCount(0)

  await page.getByLabel('Hiện đợt đã xóa').check()
  await expect(batchRow.getByTestId('batch-archived')).toBeVisible()
  await batchRow.getByRole('button', { name: 'Thao tác: Tháng 10' }).click()
  await batchRow.locator('[data-action="restore"]').click()
  await page.getByTestId('batch-confirm-restore').click()
  await expect(batchRow.getByTestId('batch-archived')).toHaveCount(0)
  await expect(batchRow.getByTestId('batch-counts')).toHaveText('1 nhận xét')
})
