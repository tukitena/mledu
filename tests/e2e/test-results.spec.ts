import { expect, test } from '@playwright/test'
import { FIXTURE_PASSWORD, accessToken, apiCall, signInThroughUi } from './support'

// GĐ 5 results of a test (TEST-01/04) on desktop and mobile: components with a
// computed total, Absent, an invalid value refused before sending, and a
// warning before a configuration change that needs scores entered again.
const unique = () => `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`
const day = (n: number) =>
  new Date(Date.now() + 7 * 3600_000 + n * 86_400_000).toISOString().slice(0, 10)

test('Admin enters component scores and Absent, then sees the re-entry warning', async ({
  page,
}) => {
  const admin = await accessToken('admin@example.com', FIXTURE_PASSWORD)
  const klass = await apiCall<{ id: string }>(admin, '/v1/classes', 'POST', {
    name: `Kết quả E2E ${unique()}`,
    subjectId: '10000000-0000-4000-8000-000000000001',
    gradeId: '10000000-0000-4000-8000-000000000011',
    startDate: day(-10),
    endDate: day(30),
    note: null,
  })
  expect(klass.status).toBe(201)
  const names = [`An ${unique()}`, `Bình ${unique()}`]
  for (const fullName of names) {
    const student = await apiCall<{ id: string }>(admin, '/v1/students', 'POST', {
      fullName,
      parentName: null,
      parentPhones: [],
      studentPhones: [],
      birthDate: null,
      school: null,
      generalNote: null,
    })
    expect(student.status).toBe(201)
    const enrolled = await apiCall(admin, `/v1/classes/${klass.body.id}/students`, 'POST', {
      studentId: student.body.id,
      joinDate: day(-5),
      leaveDate: null,
      note: null,
    })
    expect(enrolled.status).toBe(201)
  }
  const created = await apiCall(admin, `/v1/classes/${klass.body.id}/tests`, 'POST', {
    name: 'Theo phần',
    testOn: day(0),
    description: null,
    config: {
      scaleKind: 'numeric',
      inputMode: 'components',
      showComponents: false,
      components: [
        { name: 'Nghe', maxScore: 3 },
        { name: 'Viết', maxScore: 4 },
      ],
    },
    sourceTemplateVersionId: null,
  })
  expect(created.status).toBe(201)

  await signInThroughUi(page, 'admin@example.com', FIXTURE_PASSWORD)
  await expect(page.getByTestId('welcome')).toBeVisible()
  await page.goto(`/classes/${klass.body.id}?tab=tests`)
  const row = page.locator('tr[data-name="Theo phần"]')
  await expect(row.getByTestId('test-result-count')).toContainText('0 kết quả')
  await row.getByRole('button', { name: 'Thao tác: Theo phần' }).click()
  await row.locator('[data-action="results"]').click()

  const dialog = page.getByRole('dialog')
  const [an, binh] = names as [string, string]
  await dialog.getByLabel(`Nghe: ${an}`).fill('1,25')
  await dialog.getByLabel(`Viết: ${an}`).fill('3,5')
  await expect(dialog.locator(`tr[data-student="${an}"]`).getByTestId('result-total')).toHaveText(
    '4,75 / 7',
  )
  // Above the component maximum: shown as invalid and not sent.
  await dialog.getByLabel(`Nghe: ${binh}`).fill('3,5')
  await page.getByTestId('results-save').click()
  await expect(dialog.getByText('Có giá trị không hợp lệ')).toBeVisible()
  await dialog.getByLabel(`Nghe: ${binh}`).fill('')
  await dialog.getByLabel(`Vắng: ${binh}`).check()
  await page.getByTestId('results-save').click()

  const anRow = dialog.locator(`tr[data-student="${an}"]`)
  await expect(anRow.getByTestId('result-status')).toHaveText('Hoàn tất')
  await expect(
    dialog.locator(`tr[data-student="${binh}"]`).getByTestId('result-status'),
  ).toHaveText('Vắng')
  // A missing component keeps the result incomplete, never 0.
  await dialog.getByLabel(`Viết: ${an}`).fill('')
  await page.getByTestId('results-save').click()
  await expect(anRow.getByTestId('result-status')).toHaveText('Chưa hoàn tất')
  await expect(anRow.getByTestId('result-total')).toHaveText('1,25 / 7')
  await dialog.getByRole('button', { name: 'Đóng' }).last().click()

  await expect(row.getByTestId('test-result-count')).toContainText('2 kết quả')
  await row.getByRole('button', { name: 'Thao tác: Theo phần' }).click()
  await row.locator('[data-action="config"]').click()
  await expect(page.getByTestId('test-config-reentry')).toContainText('Bài đã có 2 kết quả')
})
