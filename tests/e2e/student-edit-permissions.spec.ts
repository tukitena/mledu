import { displayDate } from '../ui/date-support'
import { expect, test } from '@playwright/test'
import { apiCall, readyAccount, signInThroughUi } from './support'

const day = (n: number) =>
  new Date(Date.now() + 7 * 3600_000 + n * 86_400_000).toISOString().slice(0, 10)

for (const role of ['teacher', 'assistant'] as const) {
  test(`${role} edits shared student and participation without management actions`, async ({
    page,
  }, info) => {
    const account = await readyAccount(`editor-${role}`)
    const name = `Học sinh ${crypto.randomUUID().slice(0, 8)}`
    const student = await apiCall<{ id: string; code: string }>(
      account.admin,
      '/v1/students',
      'POST',
      {
        fullName: name,
        parentName: null,
        parentPhones: [],
        studentPhones: [],
        birthDate: null,
        school: null,
        generalNote: null,
      },
    )
    expect(student.status).toBe(201)
    const klass = await apiCall<{ id: string }>(account.admin, '/v1/classes', 'POST', {
      name: `Lớp ${name}`,
      subjectId: '10000000-0000-4000-8000-000000000001',
      gradeId: '10000000-0000-4000-8000-000000000011',
      startDate: day(-5),
      endDate: day(30),
      note: null,
    })
    expect(klass.status).toBe(201)
    expect(
      (
        await apiCall(account.admin, `/v1/classes/${klass.body.id}/students`, 'POST', {
          studentId: student.body.id,
          joinDate: day(-1),
          leaveDate: null,
          note: null,
        })
      ).status,
    ).toBe(201)
    const assignment = await apiCall<{ id: string }>(
      account.admin,
      `/v1/classes/${klass.body.id}/assignments`,
      'POST',
      {
        accountId: account.id,
        role,
        startDate: day(-1),
        endDate: day(20),
        subjectNote: null,
      },
    )
    expect(assignment.status).toBe(201)
    await signInThroughUi(page, account.email, account.password)
    await expect(page.getByTestId('welcome')).toBeVisible()
    await page.goto('/students')
    await page.getByTestId('student-search').fill(name)
    await page.getByRole('button', { name: 'Tìm kiếm', exact: true }).click()
    const row = page.locator(`tr[data-student-id="${student.body.id}"]`)
    await row.getByRole('button', { name: /^Thao tác/ }).click()
    await expect(row.locator('[data-action="edit"]')).toBeVisible()
    await expect(row.locator('[data-action="delete"]')).toHaveCount(0)
    await expect(page.getByTestId('student-create')).toHaveCount(0)
    await row.locator('[data-action="edit"]').click()
    await expect(page.getByTestId('student-shared-hint')).toBeVisible()
    await page
      .getByLabel('Trường (không bắt buộc)', { exact: true })
      .fill('Trường chung đã cập nhật')
    await page.screenshot({ path: info.outputPath('shared-profile-light-vi.png') })
    await page.getByTestId('student-submit').click()
    await expect(row).toContainText('Trường chung đã cập nhật')
    await page.goto(`/classes/${klass.body.id}?tab=students`)
    await expect(page.getByTestId('enrollment-create')).toHaveCount(0)
    const table = page.getByTestId('enrollments-table')
    await table.getByRole('button', { name: /^Thao tác/ }).click()
    await expect(table.locator('[data-action]')).toHaveCount(2)
    await table.locator('[data-action="note"]').click()
    await page.getByRole('dialog').locator('textarea').fill('Ghi chú đúng lớp')
    await page.getByTestId('enrollment-submit').click()
    await expect(table).toContainText('Ghi chú đúng lớp')
    await table.getByRole('button', { name: /^Thao tác/ }).click()
    await table.locator('[data-action="leave"]').click()
    await expect(page.getByLabel('Ngày vào', { exact: true })).toHaveCount(0)
    await page.getByLabel('Ngày nghỉ', { exact: true }).fill(displayDate(day(1)))
    await page.getByTestId('enrollment-submit').click()
    await expect(page.getByRole('dialog')).toHaveCount(0)
    await table.getByRole('button', { name: /^Thao tác/ }).click()
    await expect(table.locator('[data-action]')).toHaveCount(1)
    await expect(table.locator('[data-action="note"]')).toBeVisible()
    await page.screenshot({ path: info.outputPath('participation-edit-menu.png') })
    await table.locator('[data-action="note"]').click()
    // Revoke after opening the form: save must fail even with the original JWT.
    expect(
      (
        await apiCall(account.admin, `/v1/assignments/${assignment.body.id}/end`, 'POST', {
          reason: 'Thu hồi phân công',
          expectedVersion: 1,
        })
      ).status,
    ).toBe(200)
    await page.getByRole('dialog').locator('textarea').fill('Không được ghi')
    await page.getByTestId('enrollment-submit').click()
    await expect(page.getByTestId('error-alert')).toContainText('Bạn không có quyền')
    await expect(page.getByRole('dialog')).toBeVisible()
    const current = await apiCall<{ participations: { note: string }[] }[]>(
      account.admin,
      `/v1/classes/${klass.body.id}/students`,
    )
    expect(current.body[0]!.participations[0]!.note).toBe('Ghi chú đúng lớp')
    await page.getByRole('dialog').getByRole('button', { name: 'Hủy', exact: true }).click()
    const compact = (page.viewportSize()?.width ?? 1280) < 768
    if (compact) await page.getByTestId('user-menu').click()
    await page.getByTestId('locale-select').selectOption('en')
    await page.getByTestId('theme-select').selectOption('dark')
    if (compact) await page.getByTestId('user-menu').click()
    await page.goto('/students')
    await page.getByTestId('student-search').fill(name)
    await page.getByRole('button', { name: 'Search', exact: true }).click()
    await row.getByRole('button', { name: /^Actions/ }).click()
    await expect(row.locator('[data-action="edit"]')).toHaveCount(0)
    await page.screenshot({ path: info.outputPath('revoked-edit-dark-en.png') })
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
  })
}
