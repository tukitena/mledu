import { expect, test } from '@playwright/test'
import { pickMonth } from './date-support'

const account = {
  id: '10000000-0000-4000-8000-000000000001',
  email: 'alice@example.com',
  fullName: 'Alice Davis',
  accountType: 'user',
  status: 'active',
  mustChangePassword: false,
  phone: null,
  birthDate: null,
  hasAvatar: false,
  rowVersion: 1,
  createdAt: '2026-10-27T01:00:00Z',
  deletedAt: null,
  deletedReason: null,
}

test.beforeEach(async ({ page }) => {
  const me = {
    id: '10000000-0000-4000-8000-000000000002',
    email: 'admin@example.com',
    fullName: 'John Doe',
    accountType: 'admin',
    mustChangePassword: false,
    phone: null,
    birthDate: null,
    avatarPath: null,
    rowVersion: 1,
  }
  const user = {
    id: me.id,
    email: me.email,
    aud: 'authenticated',
    role: 'authenticated',
    app_metadata: {},
    user_metadata: {},
    created_at: '2026-10-27T01:00:00Z',
  }
  const encode = (value: unknown) => Buffer.from(JSON.stringify(value)).toString('base64url')
  const token = `${encode({ alg: 'HS256', typ: 'JWT' })}.${encode({ sub: me.id, exp: Math.floor(Date.now() / 1000) + 3600, role: 'authenticated' })}.ui-test-signature`
  await page.route('**/auth/v1/**', (route) =>
    route.fulfill({
      json: {
        access_token: token,
        refresh_token: 'ui-fixture',
        token_type: 'bearer',
        expires_in: 3600,
        user,
      },
    }),
  )
  await page.route('**/v1/me', (route) => route.fulfill({ json: me }))
  await page.route('**/v1/accounts?**', async (route) => {
    const status = new URL(route.request().url()).searchParams.get('status')
    await route.fulfill({
      json: {
        items: status && status !== 'active' ? [] : [account],
        total: status && status !== 'active' ? 0 : 1,
        page: 1,
        pageSize: 20,
      },
    })
  })
  await page.goto('/login')
  await expect(page.getByRole('heading', { name: 'Đăng nhập' })).toBeVisible()
  await page.getByLabel('Email', { exact: true }).fill(me.email)
  await page.getByLabel('Mật khẩu', { exact: true }).fill('ui-fixture-password')
  await page.getByRole('button', { name: 'Đăng nhập', exact: true }).click()
  await expect(page.getByTestId('dashboard-stats')).toBeVisible()
})

test('Metis shell resizes, navigates and keeps account actions usable', async ({
  page,
  isMobile,
}, testInfo) => {
  await expect(page.getByTestId('dashboard-stats')).toBeVisible()
  await expect(page.getByTestId('welcome')).toContainText('John Doe')
  await page.screenshot({ path: testInfo.outputPath('dashboard.png'), fullPage: true })
  if (isMobile) {
    await page.getByTestId('mobile-menu').click()
  } else {
    await page.getByTestId('desktop-menu').click()
    await expect(page.locator('.app-shell')).toHaveClass(/sidebar-collapsed/)
    // The toggle must stay clear of the brand so the sidebar can be reopened.
    const brand = await page.locator('.app-brand').boundingBox()
    const toggle = await page.getByTestId('desktop-menu').boundingBox()
    expect(toggle!.x).toBeGreaterThanOrEqual(brand!.x + brand!.width)
    await page.getByTestId('desktop-menu').click()
    await expect(page.locator('.app-shell')).not.toHaveClass(/sidebar-collapsed/)
  }
  await page.getByTestId('nav-accounts').click()
  if (isMobile) {
    await expect
      .poll(async () =>
        page.locator('.app-sidebar').evaluate((el) => el.getBoundingClientRect().right),
      )
      .toBeLessThanOrEqual(0)
  }
  const row = page.locator('tr[data-email="alice@example.com"]')
  await expect(row).toBeVisible()
  await expect(row.getByText(/^ID:/)).toHaveCount(0)
  await expect(row.locator('[title="10000000-0000-4000-8000-000000000001"]')).toHaveCount(0)
  const beforeMenu = await row.boundingBox()
  const tableBeforeMenu = await page.getByTestId('accounts-table').boundingBox()
  await row.getByRole('button', { name: /Thao tác/ }).click()
  const menu = row.locator('.account-action-menu')
  await expect(menu).toBeVisible()
  const afterMenu = await row.boundingBox()
  const tableAfterMenu = await page.getByTestId('accounts-table').boundingBox()
  expect(afterMenu?.height).toBe(beforeMenu?.height)
  expect(tableAfterMenu?.width).toBe(tableBeforeMenu?.width)
  await expect
    .poll(() =>
      menu.evaluate((element) => {
        const rect = element.getBoundingClientRect()
        return (
          element.matches(':popover-open') &&
          rect.left >= 0 &&
          rect.top >= 0 &&
          rect.right <= window.innerWidth &&
          rect.bottom <= window.innerHeight
        )
      }),
    )
    .toBe(true)
  await page.screenshot({ path: testInfo.outputPath('account-menu.png') })
  await expect(menu).toBeVisible()
  await page.getByRole('heading', { name: 'Tài khoản', exact: true }).click()
  await expect(menu).toBeHidden()
  await row.getByRole('button', { name: /Thao tác/ }).click()
  await page.keyboard.press('Escape')
  await expect(menu).toBeHidden()
  await row.getByRole('button', { name: /Thao tác/ }).click()
  await row.locator('[data-action="disable"]').click()
  await expect(menu).toBeHidden()
  await expect(page.getByRole('dialog')).toBeVisible()
  await page.getByRole('button', { name: 'Hủy', exact: true }).click()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(
    true,
  )
  await page.screenshot({ path: testInfo.outputPath('accounts.png'), fullPage: true })
  expect(await page.evaluate(() => window.scrollX)).toBe(0)
})

test('action feedback floats above the page, closes automatically and can be dismissed', async ({
  page,
}, testInfo) => {
  await page.route('**/v1/me', async (route) => {
    const updated = route.request().postDataJSON()
    await route.fulfill({
      json: { ...account, ...updated, accountType: 'admin', avatarPath: null, rowVersion: 2 },
    })
  })
  await page.getByTestId('user-menu').click()
  await page.locator('.user-menu').getByRole('link').click()
  await page.getByLabel('Họ tên', { exact: true }).fill('John Updated')
  await page.getByRole('button', { name: 'Lưu', exact: true }).click()
  const toast = page.getByTestId('profile-saved')
  await expect(toast).toBeVisible()
  await expect(page.locator('#app-alerts')).toContainText('Đã lưu hồ sơ.')
  await expect(page.locator('#app-alerts')).toHaveCSS('position', 'fixed')
  await page.screenshot({ path: testInfo.outputPath('floating-alert.png'), fullPage: true })
  await expect(toast).toHaveCount(0, { timeout: 7000 })
  await page.getByLabel('Họ tên', { exact: true }).fill('John Again')
  await page.getByRole('button', { name: 'Lưu', exact: true }).click()
  await expect(toast).toBeVisible()
  await toast.getByRole('button', { name: 'Đóng', exact: true }).click()
  await expect(toast).toHaveCount(0)
  await page.getByLabel('Họ tên', { exact: true }).fill('John Third')
  await page.getByRole('button', { name: 'Lưu', exact: true }).click()
  await expect(toast).toBeVisible()
  await page.mouse.move(0, 0)
  await expect(toast).toHaveCount(0, { timeout: 7000 })
  await page.route('**/v1/me', (route) => route.fulfill({ status: 409, json: {} }))
  await page.getByRole('button', { name: 'Lưu', exact: true }).click()
  const error = page.getByTestId('error-alert')
  await expect(page.locator('#app-alerts')).toContainText('Yêu cầu không hợp lệ.')
  await expect(error).toBeVisible()
  await error.getByRole('button', { name: 'Đóng', exact: true }).click()
  await expect(error).toHaveCount(0)
})

test('language, themes and keyboard navigation work with the new header', async ({
  page,
  isMobile,
}, testInfo) => {
  if (isMobile) await page.getByTestId('user-menu').click()
  await page.getByTestId('theme-select').selectOption('dark')
  await expect(page.locator('html')).toHaveAttribute('data-bs-theme', 'dark')
  await page.getByTestId('locale-select').selectOption('en')
  await expect(page.getByRole('heading', { name: 'Overview', exact: true })).toBeVisible()
  if (isMobile) await page.keyboard.press('Escape')
  else {
    await page.keyboard.press('Control+k')
    await page.getByTestId('nav-search').fill('Accounts')
    await page.getByTestId('nav-search').press('Enter')
    await expect(page).toHaveURL(/\/admin\/accounts$/)
    await page.keyboard.press('Control+k')
    await page.getByTestId('nav-search').fill('')
    const searchResults = page.locator('.header-search').getByRole('link')
    await expect(searchResults.last()).toHaveText('My profile')
    for (const result of await searchResults.all()) {
      await page.keyboard.press('Tab')
      await expect(result).toBeFocused()
    }
    await expect(
      page.locator('.header-search').getByRole('link', { name: 'My profile' }),
    ).toBeFocused()
    await page.keyboard.press('Enter')
    await expect(page).toHaveURL(/\/profile$/)
  }
  await page.screenshot({ path: testInfo.outputPath('dark.png'), fullPage: true })
})

test('320px header fits and switching workspace removes admin statistics', async ({
  page,
}, testInfo) => {
  await page.setViewportSize({ width: 320, height: 700 })
  await expect
    .poll(() =>
      page
        .locator('.header-tools')
        .evaluate((element) => element.getBoundingClientRect().right <= window.innerWidth),
    )
    .toBe(true)
  await page.getByTestId('quick-theme').click()
  await expect(page.locator('html')).toHaveAttribute('data-bs-theme', 'dark')
  await page.getByTestId('workspace-select').selectOption('user')
  await expect(page.getByTestId('workspace-note')).toContainText('Giảng dạy')
  await expect(page.getByText('Tổng tài khoản', { exact: true })).toHaveCount(0)
  await expect(page.getByTestId('dashboard-stats')).toBeVisible()
  await page.screenshot({ path: testInfo.outputPath('narrow-workspace.png'), fullPage: true })
})

test('dates use dd-mm-yyyy with an English browser and keep ISO API values', async ({
  page,
  isMobile,
}, testInfo) => {
  const bodies: { birthDate: string | null }[] = []
  await page.route('**/v1/me', async (route) => {
    if (route.request().method() !== 'PATCH') return route.fallback()
    const body = route.request().postDataJSON()
    bodies.push(body)
    await route.fulfill({
      json: {
        ...account,
        ...body,
        accountType: 'admin',
        avatarPath: null,
        rowVersion: bodies.length + 1,
      },
    })
  })
  await page.goto('/profile')
  const birth = page.locator('#profile-birth')
  await birth.fill('31-02-2026')
  await page.getByRole('button', { name: 'Lưu', exact: true }).click()
  await expect(birth).toHaveAttribute('aria-invalid', 'true')
  expect(bodies).toHaveLength(0)
  await birth.fill('29-02-2024')
  await page.getByRole('button', { name: 'Lưu', exact: true }).click()
  await expect.poll(() => bodies.length).toBe(1)
  expect(bodies[0]!.birthDate).toBe('2024-02-29')
  await expect(birth).toHaveValue('29-02-2024')
  await birth.locator('..').getByRole('button', { name: 'Mở lịch' }).click()
  const calendar = page.locator(`[id="${await birth.getAttribute('aria-controls')}"]`)
  await expect(calendar.getByLabel('Tháng', { exact: true })).toHaveValue('2')
  await expect(calendar).toContainText('Tháng 2')
  await expect(calendar.getByRole('button', { name: '29-02-2024', exact: true })).toHaveAttribute(
    'aria-pressed',
    'true',
  )
  await page.screenshot({ path: testInfo.outputPath('date-calendar-light-vi.png'), fullPage: true })
  await calendar.getByLabel('Tháng', { exact: true }).selectOption('9')
  await expect
    .poll(() =>
      calendar.evaluate((el) => {
        const bounds = el.getBoundingClientRect()
        return (
          bounds.top >= 0 &&
          bounds.bottom <= innerHeight &&
          bounds.left >= 0 &&
          bounds.right <= innerWidth
        )
      }),
    )
    .toBe(true)
  await calendar.getByRole('button', { name: 'Xóa ngày' }).click()
  await page.getByRole('button', { name: 'Lưu', exact: true }).click()
  await expect.poll(() => bodies.length).toBe(2)
  expect(bodies[1]!.birthDate).toBeNull()
  if (isMobile) await page.getByTestId('user-menu').click()
  await page.getByTestId('locale-select').selectOption('en')
  await page.getByTestId('theme-select').selectOption('dark')
  if (isMobile) await page.getByTestId('user-menu').click()
  await birth.fill('05-03-1990')
  await birth.locator('..').getByRole('button', { name: 'Open calendar' }).click()
  await expect(calendar.getByLabel('Month', { exact: true })).toHaveValue('3')
  await expect(birth).toHaveValue('05-03-1990')
  await page.screenshot({ path: testInfo.outputPath('date-calendar-dark-en.png'), fullPage: true })
  await page.keyboard.press('Escape')
  await expect(calendar).not.toBeVisible()
  await expect(birth).toBeFocused()
})

test('schedule month labels follow app locale and all session dates use dd-mm-yyyy', async ({
  page,
  isMobile,
}, testInfo) => {
  await page.clock.setFixedTime(new Date('2026-10-30T05:00:00Z'))
  const id = '20000000-0000-4000-8000-000000000001'
  const catalog = { id, name: 'Toán', archived: false }
  const klass = {
    id,
    name: 'Lớp Toán',
    subject: catalog,
    grade: catalog,
    schoolYearStart: 2026,
    startDate: '2026-01-01',
    endDate: '2027-12-31',
    note: null,
    adminState: 'open',
    period: 'running',
    deleted: false,
    deletedAt: null,
    deletedReason: null,
    currentStaff: [],
    rowVersion: 1,
    myRole: null,
  }
  const sessions = ['2026-11-01', '2026-11-30', '2026-12-01'].map((date, i) => ({
    id: `30000000-0000-4000-8000-00000000000${i}`,
    classId: id,
    className: klass.name,
    kind: 'weekly',
    date,
    startTime: '14:00',
    endTime: '15:30',
    startsAt: `${date}T07:00:00Z`,
    endsAt: `${date}T08:30:00Z`,
    roomId: null,
    roomName: null,
    siteName: 'Cơ sở A',
    siteAddress: null,
    status: 'scheduled',
    isException: false,
    rowVersion: 1,
    attendanceVersion: 0,
  }))
  await page.route(`**/v1/classes/${id}`, (route) => route.fulfill({ json: klass }))
  await page.route(`**/v1/classes/${id}/schedule`, (route) =>
    route.fulfill({
      json: {
        sessions,
        weekly: [],
        holidays: [{ date: '2026-11-20', name: 'Ngày lễ' }],
        warnings: [],
      },
    }),
  )
  await page.route('**/v1/rooms', (route) => route.fulfill({ json: [] }))
  await page.goto(`/classes/${id}?tab=schedule`)
  const month = page.getByLabel('Tháng', { exact: true })
  await pickMonth(page, month, '2026-11')
  await expect(month).toHaveValue('Tháng 11 2026')
  const table = page.getByTestId('sessions-table')
  await expect(table.locator('tbody tr[data-session]')).toHaveCount(2)
  await expect(table).toContainText('01-11-2026')
  await expect(table).toContainText('30-11-2026')
  await expect(page.locator('.schedule-panel')).toContainText('20-11-2026')
  await expect(page.getByTestId('class-title')).toBeVisible()
  await expect(page.locator('.page-header')).toContainText('01-01-2026 – 31-12-2027')
  await page.screenshot({
    path: testInfo.outputPath('schedule-header-light-vi.png'),
    fullPage: true,
  })
  const row = table.locator('tbody tr[data-session]').first()
  const rowBefore = await row.boundingBox()
  const tableBefore = await table.boundingBox()
  await row.getByRole('button', { name: /Thao tác/ }).click()
  const menu = row.locator('.account-action-menu')
  await expect(menu).toBeVisible()
  await expect(menu.getByRole('button')).toHaveText(['Đổi buổi', 'Ghi nghỉ'])
  expect((await row.boundingBox())?.height).toBe(rowBefore?.height)
  expect((await table.boundingBox())?.width).toBe(tableBefore?.width)
  await page.screenshot({
    path: testInfo.outputPath('schedule-month-light-vi.png'),
    fullPage: true,
  })
  await menu.getByRole('button', { name: 'Đổi buổi', exact: true }).click()
  await expect(page.getByRole('dialog')).toBeVisible()
  await expect(page.locator('#session-date')).toHaveValue('01-11-2026')
  await page.getByRole('dialog').locator('.btn-close').click()
  // min/max must apply even though this form uses novalidate.
  await page.getByTestId('class-edit').click()
  await page.locator('#class-start').fill('01-01-2026')
  await page.locator('#class-end').fill('31-12-2025')
  await expect(page.locator('#class-end')).toHaveAttribute('aria-invalid', 'true')
  await page.locator('#class-end').fill('31-12-2027')
  await page.locator('#class-start').locator('..').getByRole('button', { name: 'Mở lịch' }).click()
  await page.keyboard.press('Escape')
  await expect(page.getByRole('dialog')).toBeVisible()
  await page.getByRole('button', { name: 'Hủy', exact: true }).click()
  if (isMobile) await page.getByTestId('user-menu').click()
  await page.getByTestId('locale-select').selectOption('en')
  await page.getByTestId('theme-select').selectOption('dark')
  if (isMobile) await page.getByTestId('user-menu').click()
  await expect(page.getByLabel('Month', { exact: true })).toHaveValue('November 2026')
  await expect(table).toContainText('01-11-2026')
  await pickMonth(page, page.getByLabel('Month', { exact: true }), '2026-12')
  await expect(table.locator('tbody tr[data-session]')).toHaveCount(1)
  await expect(table).toContainText('01-12-2026')
  await page.screenshot({ path: testInfo.outputPath('schedule-month-dark-en.png'), fullPage: true })
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
})
