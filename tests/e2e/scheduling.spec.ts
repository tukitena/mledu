import { displayDate, pickMonth } from '../ui/date-support'
import { expect, test } from '@playwright/test'
import pg from 'pg'
import { readTestEnvironment } from '../../scripts/testing/environment.ts'
import { accessToken, apiCall, FIXTURE_PASSWORD, signInThroughUi } from './support'

const day = (n: number) =>
  new Date(Date.now() + 7 * 3600_000 + n * 86400_000).toISOString().slice(0, 10)
test('schedule preview, cancellation, makeup and historical attendance', async ({
  page,
}, testInfo) => {
  const token = await accessToken('receptionist@example.com', FIXTURE_PASSWORD)
  const suffix = crypto.randomUUID().slice(0, 8)
  const klass = await apiCall<{ id: string }>(token, '/v1/classes', 'POST', {
    name: `Lịch ${suffix}`,
    subjectId: '10000000-0000-4000-8000-000000000001',
    gradeId: '10000000-0000-4000-8000-000000000011',
    startDate: day(-10),
    endDate: day(20),
    note: null,
  })
  const student = await apiCall<{ id: string }>(token, '/v1/students', 'POST', {
    fullName: `Điểm danh ${suffix}`,
    parentName: null,
    parentPhones: [],
    studentPhones: [],
    birthDate: null,
    school: null,
    generalNote: null,
  })
  expect(
    (
      await apiCall(token, `/v1/classes/${klass.body.id}/students`, 'POST', {
        studentId: student.body.id,
        joinDate: day(-5),
        leaveDate: day(0),
        note: null,
      })
    ).status,
  ).toBe(201)
  // Historical session fixture: public commands deliberately reject past creation.
  const db = new pg.Client({ connectionString: readTestEnvironment().TEST_DATABASE_URL })
  await db.connect()
  let pastId: string
  try {
    await db.query("select set_config('request.jwt.claims',$1,false)", [
      JSON.stringify({ sub: '00000000-0000-4000-8000-000000000002' }),
    ])
    const result = await db.query(
      `insert into app.class_sessions(class_id,kind,original_day,original_start,starts_at,ends_at,status)
      values($1,'makeup',$2,'09:00',app_private.day_start($2::date)+interval '9 hours',app_private.day_start($2::date)+interval '10 hours','scheduled') returning id`,
      [klass.body.id, day(-1)],
    )
    pastId = result.rows[0].id
  } finally {
    await db.end()
  }
  await signInThroughUi(page, 'receptionist@example.com', FIXTURE_PASSWORD)
  await expect(page.getByTestId('welcome')).toBeVisible()
  await page.goto(`/classes/${klass.body.id}?tab=schedule`)
  const monthFilter = page.getByLabel('Tháng', { exact: true })
  await pickMonth(page, monthFilter, day(-1).slice(0, 7))
  await page.getByTestId('schedule-makeup').click()
  await page.getByLabel('Ngày học', { exact: true }).fill(displayDate(day(1)))
  await page.getByLabel('Giờ bắt đầu', { exact: true }).fill('09:00')
  await page.getByLabel('Giờ kết thúc', { exact: true }).fill('10:00')
  await page.getByTestId('schedule-preview').click()
  await expect(page.getByTestId('schedule-impact')).toContainText('09:00')
  await page.screenshot({ path: testInfo.outputPath('schedule-preview-light-vi.png') })
  await page.getByTestId('schedule-cancel-preview').click()
  await expect(page.getByTestId('sessions-table').locator('tbody tr')).toHaveCount(1)
  await page.getByTestId('schedule-preview').click()
  await page.getByTestId('schedule-confirm').click()
  await expect(page.getByRole('dialog')).toHaveCount(0)
  await pickMonth(page, monthFilter, day(1).slice(0, 7))
  await expect(page.getByTestId('sessions-table').locator('tbody tr')).toHaveCount(
    day(-1).slice(0, 7) === day(1).slice(0, 7) ? 2 : 1,
  )
  await page.getByTestId('class-close').click()
  await page.getByLabel('Lý do', { exact: true }).fill('Kiểm tra lịch đóng')
  await page.getByTestId('lifecycle-submit').click()
  await pickMonth(page, monthFilter, day(-1).slice(0, 7))
  await expect(page.getByTestId('sessions-table').locator('tbody tr')).toHaveCount(1)
  await page.getByTestId('class-reopen').click()
  await page.locator('#reopen-start-0').fill('11:00')
  await page.locator('#reopen-end-0').fill('12:00')
  await page.getByTestId('schedule-preview').click()
  await expect(page.getByTestId('schedule-impact')).toContainText('11:00')
  await page.getByTestId('schedule-confirm').click()
  await expect(page.getByRole('dialog')).toHaveCount(0)
  await pickMonth(page, monthFilter, day(1).slice(0, 7))
  await expect(page.getByTestId('sessions-table')).toContainText('11:00')
  await pickMonth(page, monthFilter, day(-1).slice(0, 7))
  const pastRow = page.locator(`[data-session="${pastId}"]`)
  await pastRow.getByRole('button', { name: /Thao tác/ }).click()
  await pastRow.locator('[data-action="attendance"]').click()
  await expect(page.getByTestId('attendance-table')).toContainText(`Điểm danh ${suffix}`)
  await expect(page.getByTestId('attendance-table')).toContainText('Chưa điểm danh')
  await page.getByLabel('Vắng', { exact: true }).check()
  await page.getByLabel('Ghi chú', { exact: true }).fill('Ghi chú nội bộ')
  await page.getByTestId('attendance-save').click()
  await expect(page.getByTestId('attendance-table')).toContainText('Vắng')
  await page.screenshot({ path: testInfo.outputPath('attendance-light-vi.png') })
  await page
    .getByRole('dialog')
    .locator('.modal-footer')
    .getByRole('button', { name: 'Đóng', exact: true })
    .click()
  await page.getByTestId('schedule-weekly').click()
  await page.getByLabel('Ngày áp dụng', { exact: true }).fill(displayDate(day(1)))
  await page.getByRole('button', { name: 'Thêm lịch', exact: true }).click()
  const weekday = String(new Date(`${day(1)}T12:00:00+07:00`).getUTCDay() || 7)
  await page.locator('#weekday-0').selectOption(weekday)
  await page.locator('#start-0').fill('14:00')
  await page.locator('#end-0').fill('15:00')
  await page.getByTestId('schedule-preview').click()
  await page.getByTestId('schedule-confirm').click()
  await expect(page.getByRole('dialog')).toHaveCount(0)
  await pickMonth(page, monthFilter, day(1).slice(0, 7))
  await expect(page.getByTestId('sessions-table')).toContainText('Lịch tuần')
  await page.getByTestId('schedule-weekly').click()
  await page.getByLabel('Ngày áp dụng', { exact: true }).fill(displayDate(day(1)))
  await expect(page.locator('#start-0')).toHaveValue('14:00')
  await page.screenshot({ path: testInfo.outputPath('weekly-form-light-vi.png') })
  await page
    .getByRole('dialog')
    .locator('.modal-footer')
    .getByRole('button', { name: 'Đóng', exact: true })
    .click()
  const compact = (page.viewportSize()?.width ?? 1280) < 768
  if (compact) await page.getByTestId('user-menu').click()
  await page.getByTestId('locale-select').selectOption('en')
  await page.getByTestId('theme-select').selectOption('dark')
  if (compact) await page.getByTestId('user-menu').click()
  await expect(page.getByTestId('sessions-table')).toContainText('Makeup')
  await page.evaluate(() => {
    window.scrollTo(0, 0)
    document.querySelectorAll('.table-responsive').forEach((element) => {
      element.scrollLeft = 0
    })
  })
  await page.screenshot({ path: testInfo.outputPath('schedule-dark-en.png'), fullPage: true })
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
})

test('Admin can review a centre holiday and cancel without changing schedules', async ({
  page,
}, testInfo) => {
  const token = await accessToken('admin@example.com', FIXTURE_PASSWORD)
  const klass = await apiCall<{ id: string }>(token, '/v1/classes', 'POST', {
    name: `Ngày lễ ${crypto.randomUUID().slice(0, 8)}`,
    subjectId: '10000000-0000-4000-8000-000000000001',
    gradeId: '10000000-0000-4000-8000-000000000011',
    startDate: day(-1),
    endDate: day(20),
    note: null,
  })
  await signInThroughUi(page, 'admin@example.com', FIXTURE_PASSWORD)
  await expect(page.getByTestId('welcome')).toBeVisible()
  await page.goto(`/classes/${klass.body.id}?tab=schedule`)
  await page.getByRole('button', { name: 'Thêm ngày lễ', exact: true }).click()
  await page.getByLabel('Ngày nghỉ lễ', { exact: true }).fill(displayDate(day(2)))
  await page.getByLabel('Tên ngày lễ', { exact: true }).fill('Lễ thử nghiệm')
  await page.getByTestId('schedule-preview').click()
  await expect(page.getByTestId('schedule-impact')).toBeVisible()
  await page.screenshot({ path: testInfo.outputPath('holiday-preview-light-vi.png') })
  await page
    .getByRole('dialog')
    .locator('.modal-footer')
    .getByRole('button', { name: 'Đóng', exact: true })
    .click()
  await expect(page.getByRole('dialog')).toHaveCount(0)
  const schedule = await apiCall<{ holidays: { date: string }[] }>(
    token,
    `/v1/classes/${klass.body.id}/schedule`,
  )
  expect(schedule.body.holidays.some((item) => item.date === day(2))).toBe(false)
})
