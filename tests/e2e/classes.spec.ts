import { expect, test } from '@playwright/test'
import { FIXTURE_PASSWORD, readyAccount, signInThroughUi } from './support'

// GĐ 3 classes and assignments in the browser (CLASS-01/02/03, AUTH-04).
const unique = () => `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`
const day = (offset: number) =>
  new Date(Date.now() + 7 * 3600_000 + offset * 86_400_000).toISOString().slice(0, 10)

test('Receptionist creates a class and assigns a teacher who then sees it', async ({
  browser,
  page,
}, testInfo) => {
  const teacher = await readyAccount('teacher')
  await signInThroughUi(page, 'receptionist@example.com', FIXTURE_PASSWORD)
  await expect(page.getByTestId('welcome')).toBeVisible()
  await page.goto('/classes')

  const name = `Toán E2E ${unique()}`
  await page.getByTestId('class-create').click()
  await page.getByLabel('Tên lớp').fill(name)
  await page.getByLabel('Môn', { exact: true }).selectOption({ label: 'Toán' })
  await page.getByLabel('Khối', { exact: true }).selectOption({ label: 'Lớp 6' })
  await page.getByLabel('Ngày mở').fill(day(-3))
  await page.getByLabel('Ngày kết thúc').fill(day(60))
  await page.getByTestId('class-submit').click()
  await expect(page.getByTestId('class-title')).toHaveText(name)

  await page.getByTestId('assignment-create').click()
  await page.getByRole('dialog').getByLabel('Nhân sự').selectOption({ value: teacher.id })
  await page.getByLabel('Ngày bắt đầu').fill(day(-1))
  await page.getByTestId('assignment-submit').click()
  const row = page.locator(`tr[data-email="${teacher.email}"]`)
  await expect(row.getByTestId('assignment-status')).toHaveText('Đang hiệu lực')
  await page.screenshot({ path: testInfo.outputPath('class-detail.png') })

  // The teacher sees the class under "My classes" in its own session.
  const teacherContext = await browser.newContext()
  const teacherPage = await teacherContext.newPage()
  await signInThroughUi(teacherPage, teacher.email, teacher.password)
  await expect(teacherPage.getByTestId('welcome')).toBeVisible()
  await teacherPage.goto('/classes')
  await expect(teacherPage.getByRole('heading', { name: 'Lớp của tôi' })).toBeVisible()
  await expect(teacherPage.getByTestId('classes-table')).toContainText(name)
  await expect(teacherPage.getByTestId('class-create')).toHaveCount(0)

  // AUTH-04: the Admin cannot delete an account that teaches now.
  const adminContext = await browser.newContext()
  const adminPage = await adminContext.newPage()
  await signInThroughUi(adminPage, 'admin@example.com', FIXTURE_PASSWORD)
  await expect(adminPage.getByTestId('welcome')).toBeVisible()
  await adminPage.goto('/admin/accounts')
  await adminPage.getByPlaceholder('Tìm theo tên hoặc email').fill(teacher.email)
  await adminPage.getByRole('button', { name: 'Tìm kiếm', exact: true }).click()
  const accountRow = adminPage.locator(`tr[data-email="${teacher.email}"]`)
  await accountRow.getByRole('button', { name: /^Thao tác/ }).click()
  await accountRow.locator('[data-action="delete"]').click()
  await adminPage.getByLabel('Lý do').fill('Nghỉ việc')
  await adminPage.getByTestId('confirm-delete').click()
  await expect(adminPage.getByText(`Liên quan: ${name}`)).toBeVisible()

  // Ending the assignment closes the class for the teacher on the next request.
  await row.getByRole('button', { name: /^Thao tác/ }).click()
  await row.locator('[data-action="end"]').click()
  await page.getByLabel('Lý do').fill('Đổi giáo viên')
  await page.getByTestId('assignment-confirm-end').click()
  await expect(row.getByTestId('assignment-status')).toHaveText('Kết thúc sớm')

  await teacherPage.reload()
  await expect(teacherPage.getByTestId('classes-table')).not.toContainText(name)
  await teacherContext.close()
  await adminContext.close()
})
