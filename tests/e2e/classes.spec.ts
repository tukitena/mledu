import { expect, test } from '@playwright/test'
import { accessToken, apiCall, FIXTURE_PASSWORD, readyAccount, signInThroughUi } from './support'

// GĐ 3 classes and assignments in the browser (CLASS-01/02/03, AUTH-04).
const unique = () => `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`
const day = (offset: number) =>
  new Date(Date.now() + 7 * 3600_000 + offset * 86_400_000).toISOString().slice(0, 10)

test('optional school year can be created, filtered, edited and cleared', async ({
  page,
  isMobile,
}, testInfo) => {
  const prefix = `Năm học E2E ${unique()}`
  const name = `${prefix} biên chế`
  const otherName = `${prefix} tự do`
  const token = await accessToken('receptionist@example.com', FIXTURE_PASSWORD)
  expect(
    (
      await apiCall(token, '/v1/classes', 'POST', {
        name: otherName,
        subjectId: '10000000-0000-4000-8000-000000000001',
        gradeId: '10000000-0000-4000-8000-000000000011',
        startDate: day(-3),
        endDate: day(60),
        note: null,
      })
    ).status,
  ).toBe(201)
  await signInThroughUi(page, 'receptionist@example.com', FIXTURE_PASSWORD)
  await expect(page.getByTestId('welcome')).toBeVisible()
  await page.goto('/classes')
  await page.getByTestId('class-create').click()
  await page.getByLabel('Tên lớp').fill(name)
  await page.getByLabel('Môn', { exact: true }).selectOption({ label: 'Toán' })
  await page.getByLabel('Khối', { exact: true }).selectOption({ label: 'Lớp 6' })
  await page.getByLabel('Ngày mở').fill(day(-3))
  await page.getByLabel('Ngày kết thúc').fill(day(60))
  await expect(page.getByRole('dialog').getByLabel('Năm học', { exact: false })).toBeVisible({
    timeout: 5000,
  })
  await page.getByRole('dialog').getByLabel('Năm học', { exact: false }).fill('9999')
  await expect(page.getByTestId('class-submit')).toBeDisabled()
  await page.getByRole('dialog').getByLabel('Năm học', { exact: false }).fill('2026')
  await expect(page.getByTestId('school-year-preview')).toHaveText('2026–2027')
  await page.screenshot({ path: testInfo.outputPath('school-year-form-vi-light.png') })
  await page.getByTestId('class-submit').click()
  await expect(page.getByTestId('class-school-year')).toHaveText('2026–2027')
  await page.getByRole('link', { name: 'Danh sách lớp' }).click()
  await page.getByPlaceholder('Tìm theo tên lớp').fill(prefix)
  await page.getByRole('button', { name: 'Tìm kiếm', exact: true }).click()
  await expect(page.getByTestId('classes-table').locator('tbody tr[data-name]')).toHaveCount(2)
  await page.getByLabel('Lọc theo năm học').selectOption('2026')
  await expect(page.getByTestId('classes-table')).toContainText(name)
  await expect(page.getByTestId('classes-table')).not.toContainText(otherName)
  await page.screenshot({ path: testInfo.outputPath('school-year-list-vi-light.png') })
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
  await page.getByLabel('Lọc theo năm học').selectOption('none')
  await expect(page.getByTestId('classes-table')).toContainText(otherName)
  await expect(page.getByTestId('classes-table')).not.toContainText(name)
  await page.getByLabel('Lọc theo năm học').selectOption('all')
  await page.getByRole('link', { name, exact: true }).click()
  await page.getByTestId('class-edit').click()
  await expect(page.getByRole('dialog').getByLabel('Năm học', { exact: false })).toHaveValue('2026')
  // A number input exposes value='' for a malformed number as well as a cleared field.
  // Malformed input must not silently clear an existing school year.
  await page.getByRole('dialog').getByLabel('Năm học', { exact: false }).press('ControlOrMeta+A')
  await page.getByRole('dialog').getByLabel('Năm học', { exact: false }).press('e')
  await expect(page.getByTestId('class-submit')).toBeDisabled()
  await page.getByRole('dialog').getByLabel('Năm học', { exact: false }).fill('2027')
  await page.getByTestId('class-submit').click()
  await expect(page.getByTestId('class-school-year')).toHaveText('2027–2028')
  await page.getByTestId('class-edit').click()
  await page.getByRole('dialog').getByLabel('Năm học', { exact: false }).fill('')
  await page.getByTestId('class-submit').click()
  await expect(page.getByTestId('class-school-year')).toHaveText('Không thuộc năm học')
  if (isMobile) await page.getByTestId('user-menu').click()
  await page.getByTestId('locale-select').selectOption('en')
  await page.getByTestId('theme-select').selectOption('dark')
  if (isMobile) await page.getByTestId('user-menu').click()
  await page.getByRole('link', { name: 'All classes' }).click()
  await page.getByLabel('Filter by school year').selectOption('none')
  await page.getByPlaceholder('Search by class name').fill(prefix)
  await page.getByRole('button', { name: 'Search', exact: true }).click()
  await expect(page.getByTestId('classes-table').locator('tbody tr[data-name]')).toHaveCount(2)
  await page.screenshot({ path: testInfo.outputPath('school-year-list-en-dark.png') })
})

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
