import { displayDate } from '../ui/date-support'
import { expect, test } from '@playwright/test'
import { accessToken, apiCall, FIXTURE_PASSWORD, signInThroughUi } from './support'

const day = (n: number) =>
  new Date(Date.now() + 7 * 3600_000 + n * 86_400_000).toISOString().slice(0, 10)
test('manage participation, return, transfer and retained history', async ({ page }, testInfo) => {
  const token = await accessToken('receptionist@example.com', FIXTURE_PASSWORD)
  const suffix = crypto.randomUUID().slice(0, 8)
  const student = await apiCall<{ id: string; code: string }>(token, '/v1/students', 'POST', {
    fullName: `Học sinh ${suffix}`,
    parentName: null,
    parentPhones: [],
    studentPhones: [],
    birthDate: null,
    school: null,
    generalNote: null,
  })
  expect(student.status).toBe(201)
  const createClass = (name: string) =>
    apiCall<{ id: string }>(token, '/v1/classes', 'POST', {
      name,
      subjectId: '10000000-0000-4000-8000-000000000001',
      gradeId: '10000000-0000-4000-8000-000000000011',
      startDate: day(-5),
      endDate: day(60),
      note: null,
    })
  const source = await createClass(`Nguồn ${suffix}`)
  const target = await createClass(`Đích ${suffix}`)
  await signInThroughUi(page, 'receptionist@example.com', FIXTURE_PASSWORD)
  await expect(page.getByTestId('welcome')).toBeVisible()
  await page.goto(`/classes/${source.body.id}?tab=students`)
  await page.getByTestId('enrollment-create').click()
  await page.getByLabel('Tìm học sinh').fill(`Học sinh ${suffix}`)
  await page.getByTestId('enrollment-search').click()
  await page
    .getByRole('dialog')
    .getByLabel('Học sinh', { exact: true })
    .selectOption(student.body.id)
  await expect(page.getByRole('dialog')).not.toContainText(student.body.code)
  await page.getByLabel('Ngày vào', { exact: true }).fill(displayDate(day(-2)))
  await page.screenshot({ path: testInfo.outputPath('enrollment-dialog-light-vi.png') })
  await page.getByTestId('enrollment-submit').click()
  const table = page.getByTestId('enrollments-table')
  await expect(table).toContainText('Đang học')
  await expect(table).not.toContainText(student.body.code)
  const filter = page.getByPlaceholder('Tìm tên học sinh', { exact: true })
  await filter.fill(student.body.code)
  await expect(table.locator('tbody tr[data-participation-id]')).toHaveCount(0)
  await filter.fill(`hoc sinh ${suffix}`)
  await expect(table.locator('tbody tr[data-participation-id]')).toHaveCount(1)
  await filter.fill('')
  await table.getByRole('button', { name: /^Thao tác/ }).click()
  await table.locator('[data-action="leave"]').click()
  await page.getByLabel('Ngày nghỉ', { exact: true }).fill(displayDate(day(1)))
  await page.getByTestId('enrollment-submit').click()
  await expect(page.getByRole('dialog')).toHaveCount(0)
  await table.getByRole('button', { name: /^Thao tác/ }).click()
  await table.locator('[data-action="reenroll"]').click()
  await page.getByLabel('Ngày vào', { exact: true }).fill(displayDate(day(1)))
  await page.getByTestId('enrollment-submit').click()
  await expect(table.locator('tbody tr')).toHaveCount(2)
  const future = table.locator('tbody tr').filter({ hasText: 'Chưa bắt đầu' })
  await future.getByRole('button', { name: /^Thao tác/ }).click()
  await future.locator('[data-action="transfer"]').click()
  await page.getByLabel('Tìm lớp đích').fill(`Đích ${suffix}`)
  await page.getByTestId('enrollment-search').click()
  await page.getByLabel('Lớp đích', { exact: true }).selectOption(target.body.id)
  await page.getByLabel('Ngày nghỉ', { exact: true }).fill(displayDate(day(3)))
  await page.getByLabel('Ngày vào lớp đích').fill(displayDate(day(3)))
  await page.getByTestId('enrollment-submit').click()
  await expect(page.getByRole('dialog')).toHaveCount(0)
  await page.reload()
  await expect(table.locator('tbody tr')).toHaveCount(2)
  await page.screenshot({
    path: testInfo.outputPath('participations-light-vi.png'),
    fullPage: true,
  })
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(
    true,
  )
  await page.goto(`/classes/${target.body.id}?tab=students`)
  await expect(table).toContainText(`Học sinh ${suffix}`)
  await table.getByRole('button', { name: /^Thao tác/ }).click()
  await table.locator('[data-action="cancel"]').click()
  await page.getByLabel('Lý do', { exact: true }).fill('Đổi kế hoạch')
  await page.getByTestId('enrollment-submit').click()
  await expect(table).toContainText('Đã hủy')
  const compact = (page.viewportSize()?.width ?? 1280) < 768
  if (compact) await page.getByTestId('user-menu').click()
  await page.getByTestId('locale-select').selectOption('en')
  await page.getByTestId('theme-select').selectOption('dark')
  if (compact) await page.getByTestId('user-menu').click()
  await expect(table).toContainText('Ended · Cancelled')
  await page.screenshot({ path: testInfo.outputPath('participations-dark-en.png'), fullPage: true })
  if (compact) await page.getByTestId('user-menu').click()
  await page.getByTestId('locale-select').selectOption('vi')
  if (compact) await page.getByTestId('user-menu').click()
  await page.getByTestId('class-close').click()
  await page.getByLabel('Lý do', { exact: true }).fill('Tạm đóng')
  await page.getByTestId('lifecycle-submit').click()
  await expect(page.getByTestId('enrollment-create')).toHaveCount(0)
  await expect(table).toContainText('Đã hủy')
})

test('same-name students remain distinguishable without internal codes', async ({
  page,
}, testInfo) => {
  const token = await accessToken('receptionist@example.com', FIXTURE_PASSWORD)
  const suffix = crypto.randomUUID().slice(0, 8)
  const name = `Trùng tên ${suffix}`
  const phoneBase = parseInt(suffix, 16) % 99999998
  const students = []
  for (let i = 0; i < 2; i++) {
    const parentPhone = `09${String(phoneBase + i).padStart(8, '0')}`
    const result = await apiCall<{ id: string; code: string }>(token, '/v1/students', 'POST', {
      fullName: name,
      parentName: null,
      parentPhones: [parentPhone],
      studentPhones: [],
      birthDate: i === 0 ? '2009-02-05' : '2010-03-06',
      school: null,
      generalNote: null,
    })
    expect(result.status).toBe(201)
    students.push({ ...result.body, parentPhone })
  }
  const klass = await apiCall<{ id: string }>(token, '/v1/classes', 'POST', {
    name: `Phân biệt ${suffix}`,
    subjectId: '10000000-0000-4000-8000-000000000001',
    gradeId: '10000000-0000-4000-8000-000000000011',
    startDate: day(-5),
    endDate: day(30),
    note: null,
  })
  for (const student of students) {
    expect(
      (
        await apiCall(token, `/v1/classes/${klass.body.id}/students`, 'POST', {
          studentId: student.id,
          joinDate: day(-1),
          leaveDate: null,
          note: null,
        })
      ).status,
    ).toBe(201)
  }
  await signInThroughUi(page, 'receptionist@example.com', FIXTURE_PASSWORD)
  await expect(page.getByTestId('welcome')).toBeVisible()
  await page.goto(`/classes/${klass.body.id}?tab=students`)
  const table = page.getByTestId('enrollments-table')
  await expect(table.locator('tbody tr[data-record-id]')).toHaveCount(2)
  for (const student of students) {
    const row = table.locator('tbody tr').filter({ hasText: student.parentPhone })
    await expect(row).toContainText(name)
    await expect(row).not.toContainText(student.code)
    await row.getByRole('button', { name: /Thao tác/ }).click()
    await row.locator('[data-action="leave"]').click()
    await expect(page.getByRole('dialog')).toContainText(student.parentPhone)
    await expect(page.getByRole('dialog')).not.toContainText(student.code)
    await page.getByRole('dialog').getByRole('button', { name: 'Hủy', exact: true }).click()
  }
  await page.screenshot({ path: testInfo.outputPath('same-name-students.png'), fullPage: true })
})
