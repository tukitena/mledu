import { expect, test } from '@playwright/test'
import {
  FIXTURE_PASSWORD,
  apiCall,
  readyAccount,
  resetLinkPath,
  signInThroughUi,
  uniqueEmail,
} from './support'

// GĐ 2 browser flows on desktop and mobile (AUTH-01–08, UX-01). Accounts are
// fictional and created per test on the local stack.

const PNG_1X1 = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  'base64',
)

test('Admin creates an account; the new user must change the temporary password first', async ({
  page,
}) => {
  await signInThroughUi(page, 'admin@example.com', FIXTURE_PASSWORD)
  await expect(page.getByTestId('welcome')).toBeVisible()
  await page.goto('/admin/accounts')

  const email = uniqueEmail('created')
  await page.getByTestId('create-account').click()
  await page.getByLabel('Email đăng nhập').fill(email)
  await page.getByLabel('Họ tên').fill('Giáo viên E2E')
  await page.getByTestId('submit-create').click()
  const temporaryPassword = await page.getByTestId('temporary-password').inputValue()
  expect(temporaryPassword).toMatch(/^[A-Za-z2-9]{12}$/)
  await page.getByRole('button', { name: 'Đóng', exact: true }).last().click()
  await expect(page.locator(`tr[data-email="${email}"]`)).toContainText('Chờ đổi mật khẩu')

  await page.getByTestId('user-menu').click()
  await page.getByRole('button', { name: 'Đăng xuất' }).click()
  await expect(page).toHaveURL(/\/login$/)

  await signInThroughUi(page, email, temporaryPassword)
  await expect(page).toHaveURL(/\/change-password$/)
  // Business pages stay closed until the change is done.
  await page.goto('/profile')
  await expect(page).toHaveURL(/\/change-password$/)

  await page.getByLabel('Mật khẩu mới', { exact: true }).fill('short')
  await page.getByLabel('Xác nhận mật khẩu mới').fill('short')
  await page.getByRole('button', { name: 'Đổi mật khẩu' }).click()
  await expect(page.getByText('Dữ liệu chưa hợp lệ')).toBeVisible()

  await page.getByLabel('Mật khẩu mới', { exact: true }).fill('e2e-chosen-1')
  await page.getByLabel('Xác nhận mật khẩu mới').fill('e2e-chosen-2')
  await page.getByRole('button', { name: 'Đổi mật khẩu' }).click()
  await expect(page.getByText('Mật khẩu xác nhận không khớp.')).toBeVisible()

  await page.getByLabel('Xác nhận mật khẩu mới').fill('e2e-chosen-1')
  await page.getByRole('button', { name: 'Đổi mật khẩu' }).click()
  await expect(page.getByTestId('welcome')).toContainText('Giáo viên E2E')
  // A User has a single workspace and no account administration.
  await expect(page.getByTestId('workspace-select')).toHaveCount(0)
  await page.goto('/admin/accounts')
  await expect(page).toHaveURL(/\/$/)
})

test('a disabled account cannot sign in and an open session ends', async ({ page }) => {
  await signInThroughUi(page, 'disabled@example.com', FIXTURE_PASSWORD)
  await expect(page.getByText('Tài khoản không được phép truy cập.')).toBeVisible()

  const account = await readyAccount('disable')
  await signInThroughUi(page, account.email, account.password)
  await expect(page.getByTestId('welcome')).toBeVisible()

  const me = await apiCall(account.admin, `/v1/accounts/${account.id}`)
  const disabled = await apiCall(account.admin, `/v1/accounts/${account.id}/disable`, 'POST', {
    expectedVersion: me.body.rowVersion,
  })
  expect(disabled.status).toBe(200)

  await page.reload()
  await expect(page).toHaveURL(/\/login/)
  await expect(page.getByText('Tài khoản không được phép truy cập.')).toBeVisible()
})

test('a type change reaches the open session without signing in again (AUTH-07)', async ({
  page,
}) => {
  const account = await readyAccount('type')
  await signInThroughUi(page, account.email, account.password)
  await expect(page.getByTestId('workspace-note')).toContainText('Giảng dạy')

  const me = await apiCall(account.admin, `/v1/accounts/${account.id}`)
  await apiCall(account.admin, `/v1/accounts/${account.id}/type`, 'PUT', {
    accountType: 'receptionist',
    expectedVersion: me.body.rowVersion,
  })
  // The API applies the new type to the next request; the SPA re-reads the
  // profile every 5 minutes (not on focus) or when the page is reloaded.
  await page.evaluate(() => window.dispatchEvent(new Event('focus')))
  await expect(page.getByTestId('workspace-note')).toContainText('Giảng dạy')
  await page.reload()
  await expect(page.getByTestId('workspace-note')).toContainText('Lễ tân')
})

test('Admin switches workspaces; account administration belongs to Admin only', async ({
  page,
}) => {
  await signInThroughUi(page, 'admin@example.com', FIXTURE_PASSWORD)
  await expect(page.getByTestId('nav-accounts')).toBeVisible()
  await page.getByTestId('workspace-select').selectOption('receptionist')
  await expect(page.getByTestId('nav-accounts')).toHaveCount(0)
  await expect(page.getByTestId('workspace-note')).toContainText('Lễ tân')

  await page.goto('/admin/accounts')
  await expect(page.getByTestId('accounts-table')).toBeVisible()
  await expect(page.getByTestId('workspace-select')).toHaveValue('admin')
  // Admin accounts offer no actions in the application (AUTH-06).
  await expect(page.locator('tr[data-email="admin@example.com"] button')).toHaveCount(0)
})

test('reset by email works once and signs every session out', async ({ page, baseURL }) => {
  const account = await readyAccount('reset')
  await page.goto('/forgot-password')
  await page.getByLabel('Email').fill(account.email)
  await page.getByRole('button', { name: 'Gửi hướng dẫn' }).click()
  await expect(page.getByTestId('reset-sent')).toBeVisible()

  const path = await resetLinkPath(account.email)
  await page.goto(new URL(path, baseURL).toString())
  await expect(page).toHaveURL(/\/reset-password$/)
  await page.getByLabel('Mật khẩu mới', { exact: true }).fill('e2e-reset-new')
  await page.getByLabel('Xác nhận mật khẩu mới').fill('e2e-reset-new')
  await page.getByRole('button', { name: 'Đặt lại mật khẩu' }).click()
  await expect(page.getByTestId('reset-done')).toBeVisible()

  // The same link cannot be used again.
  await page.goto(new URL(path, baseURL).toString())
  await page.getByLabel('Mật khẩu mới', { exact: true }).fill('e2e-reset-again')
  await page.getByLabel('Xác nhận mật khẩu mới').fill('e2e-reset-again')
  await page.getByRole('button', { name: 'Đặt lại mật khẩu' }).click()
  await expect(page.getByTestId('error-alert')).toContainText('Liên kết đặt lại không hợp lệ')

  await signInThroughUi(page, account.email, 'e2e-reset-new')
  await expect(page.getByTestId('welcome')).toBeVisible()
})

test('profile edits and the avatar are saved; the email stays read-only', async ({ page }) => {
  const account = await readyAccount('profile')
  await signInThroughUi(page, account.email, account.password)
  await page.getByTestId('user-menu').click()
  await page.locator('.user-menu').getByRole('link', { name: 'Hồ sơ cá nhân' }).click()

  await expect(page.getByLabel('Email đăng nhập')).toHaveAttribute('readonly', '')
  await page.getByLabel('Họ tên').fill('Tên Đã Đổi')
  await page.getByLabel(/Số điện thoại/).fill('0901 234 567')
  await page.getByRole('button', { name: 'Lưu' }).click()
  await expect(page.getByTestId('profile-saved')).toBeVisible()

  await page.getByTestId('avatar-input').setInputFiles({
    name: 'avatar.png',
    mimeType: 'image/png',
    buffer: PNG_1X1,
  })
  await expect(page.getByText('Đã cập nhật ảnh hồ sơ.')).toBeVisible()
  await expect(page.getByTestId('avatar-image').first()).toBeVisible()

  // A text file renamed to .png is refused by the backend check.
  await page.getByTestId('avatar-input').setInputFiles({
    name: 'fake.png',
    mimeType: 'image/png',
    buffer: Buffer.from('not really an image, just text bytes'),
  })
  await expect(page.getByTestId('error-alert')).toContainText('Ảnh không hợp lệ')

  await page.reload()
  await expect(page.getByLabel('Họ tên')).toHaveValue('Tên Đã Đổi')
  await expect(page.getByLabel(/Số điện thoại/)).toHaveValue('0901234567')
})

test('language and theme are kept per browser; system follows the OS (UX-01)', async ({ page }) => {
  await page.emulateMedia({ colorScheme: 'dark' })
  await page.goto('/login')
  await expect(page.locator('html')).toHaveAttribute('data-bs-theme', 'dark')
  await page.emulateMedia({ colorScheme: 'light' })
  await expect(page.locator('html')).toHaveAttribute('data-bs-theme', 'light')

  await page.getByTestId('locale-select').selectOption('en')
  await page.getByTestId('theme-select').selectOption('dark')
  await expect(page.getByRole('heading', { name: 'Sign in' })).toBeVisible()
  await page.reload()
  await expect(page.getByRole('heading', { name: 'Sign in' })).toBeVisible()
  await expect(page.locator('html')).toHaveAttribute('data-bs-theme', 'dark')
  await expect(page.locator('html')).toHaveAttribute('lang', 'en')
})
