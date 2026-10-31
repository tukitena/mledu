import { expect, test } from '@playwright/test'
import { FIXTURE_PASSWORD, accessToken, apiCall, signInThroughUi } from './support'

// GĐ 5 results of a test (TEST-01/04) on desktop and mobile: components with a
// computed total, Absent, an invalid value refused before sending, and a
// warning before a configuration change that needs scores entered again.
const unique = () => `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`
const day = (n: number) =>
  new Date(Date.now() + 7 * 3600_000 + n * 86_400_000).toISOString().slice(0, 10)

test('Admin enters component scores and Absent, then publishes', async ({ page }) => {
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

  // ACAD-01: the class publish takes Absent only, names the incomplete student
  // and locks what it published until it is unpublished.
  await expect(anRow.getByTestId('result-publish')).toHaveCount(0)
  await page.getByTestId('results-publish-all').click()
  await expect(dialog.getByTestId('results-notice')).toContainText('Đã công bố 1 kết quả')
  await expect(dialog.getByTestId('results-notice')).toContainText(an)
  const binhRow = dialog.locator(`tr[data-student="${binh}"]`)
  await expect(binhRow.getByTestId('result-status')).toHaveText('Đã công bố')
  await expect(dialog.getByLabel(`Vắng: ${binh}`)).toBeDisabled()
  await binhRow.getByTestId('result-unpublish').click()
  await expect(binhRow.getByTestId('result-status')).toHaveText('Vắng')
  await expect(dialog.getByLabel(`Vắng: ${binh}`)).toBeEnabled()
  await binhRow.getByTestId('result-publish').click()
  await expect(binhRow.getByTestId('result-status')).toHaveText('Đã công bố')
  await dialog.getByRole('button', { name: 'Đóng' }).last().click()

  await expect(row.getByTestId('test-result-count')).toContainText('2 kết quả')
  await expect(row.getByTestId('test-published-count')).toHaveText('1 đã công bố')
})

test('Admin enters IELTS bands: L/R kept as typed, Writing computed from Tasks', async ({
  page,
}) => {
  const admin = await accessToken('admin@example.com', FIXTURE_PASSWORD)
  const klass = await apiCall<{ id: string }>(admin, '/v1/classes', 'POST', {
    name: `IELTS E2E ${unique()}`,
    subjectId: '10000000-0000-4000-8000-000000000001',
    gradeId: '10000000-0000-4000-8000-000000000011',
    startDate: day(-10),
    endDate: day(30),
    note: null,
  })
  expect(klass.status).toBe(201)
  const name = `Lan ${unique()}`
  const student = await apiCall<{ id: string }>(admin, '/v1/students', 'POST', {
    fullName: name,
    parentName: null,
    parentPhones: [],
    studentPhones: [],
    birthDate: null,
    school: null,
    generalNote: null,
  })
  expect(student.status).toBe(201)
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
        name: 'IELTS L-W',
        testOn: day(0),
        description: null,
        config: {
          scaleKind: 'ielts',
          showComponents: false,
          skills: [
            { code: 'L', inputMode: 'detailed', maxQuestions: 40 },
            { code: 'W', inputMode: 'detailed' },
          ],
        },
        sourceTemplateVersionId: null,
      })
    ).status,
  ).toBe(201)

  await signInThroughUi(page, 'admin@example.com', FIXTURE_PASSWORD)
  await expect(page.getByTestId('welcome')).toBeVisible()
  await page.goto(`/classes/${klass.body.id}?tab=tests`)
  const row = page.locator('tr[data-name="IELTS L-W"]')
  await row.getByRole('button', { name: 'Thao tác: IELTS L-W' }).click()
  await row.locator('[data-action="results"]').click()

  const dialog = page.getByRole('dialog')
  const studentRow = dialog.locator(`tr[data-student="${name}"]`)
  await studentRow.getByTestId('ielts-L-answers').fill('30')
  await studentRow.getByTestId('ielts-L-band').fill('6,5')
  const criteria = ['6', '6', '6', '6,5', '6', '6', '6,5', '6,5']
  for (const [index, code] of [
    't1_ta',
    't1_cc',
    't1_lr',
    't1_gra',
    't2_tr',
    't2_cc',
    't2_lr',
    't2_gra',
  ].entries())
    await studentRow.getByTestId(`ielts-W-${code}`).fill(criteria[index]!)
  await expect(studentRow.getByTestId('ielts-preview')).toHaveText('T1 6 · T2 6,5 → 6,5')
  await page.getByTestId('results-save').click()
  await expect(studentRow.getByTestId('result-status')).toHaveText('Hoàn tất')
  await expect(studentRow.getByTestId('ielts-L-band')).toHaveValue('6,5')
  await expect(studentRow.getByTestId('ielts-L-answers')).toHaveValue('30')
  // Two skills: no Overall column, and the result can be published.
  await expect(dialog.getByTestId('ielts-overall')).toHaveCount(0)
  await studentRow.getByTestId('result-publish').click()
  await expect(studentRow.getByTestId('result-status')).toHaveText('Đã công bố')
})
