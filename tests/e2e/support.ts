import { expect, type Page } from '@playwright/test'
import { readTestEnvironment } from '../../scripts/testing/environment.ts'

const testEnv = readTestEnvironment()
const SUPABASE_URL = testEnv.SUPABASE_URL
const PUBLISHABLE_KEY = testEnv.SUPABASE_PUBLISHABLE_KEY

export const API_URL = 'http://127.0.0.1:8797'
export const FIXTURE_PASSWORD = '123456ab'
const MAILPIT_URL = testEnv.TEST_MAILPIT_URL

let counter = 0
export const uniqueEmail = (label: string) =>
  `e2e.${label}.${Date.now().toString(36)}${(counter++).toString(36)}@example.com`

export async function accessToken(email: string, password: string) {
  const response = await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: PUBLISHABLE_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  })
  expect(response.ok).toBe(true)
  return ((await response.json()) as { access_token: string }).access_token
}

export async function apiCall<T = { rowVersion: number }>(
  token: string,
  path: string,
  method = 'GET',
  body?: unknown,
) {
  const response = await fetch(`${API_URL}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  })
  return { status: response.status, body: (await response.json()) as T }
}

/** Admin creates an account through the API and completes the first password change. */
export async function readyAccount(label: string) {
  const admin = await accessToken('admin@example.com', FIXTURE_PASSWORD)
  const email = uniqueEmail(label)
  const created = await apiCall<{ account: { id: string }; temporaryPassword: string }>(
    admin,
    '/v1/accounts',
    'POST',
    {
      email,
      fullName: `E2E ${label}`,
    },
  )
  expect(created.status).toBe(201)
  const token = await accessToken(email, created.body.temporaryPassword)
  const password = `e2e-${label}-pass`
  expect((await apiCall(token, '/v1/me/password', 'POST', { password })).status).toBe(200)
  return { id: created.body.account.id, email, password, admin }
}

export async function signInThroughUi(page: Page, email: string, password: string) {
  await page.goto('/login')
  await page.getByLabel(/^(Email)$/).fill(email)
  await page.getByLabel(/^(Mật khẩu|Password)$/).fill(password)
  await page.getByRole('button', { name: /^(Đăng nhập|Sign in)$/ }).click()
}

/** Token hash of the newest reset email sent to the address (local Mailpit). */
export async function resetLinkPath(email: string) {
  for (let attempt = 0; attempt < 50; attempt++) {
    const listing = (await (
      await fetch(`${MAILPIT_URL}/api/v1/search?query=${encodeURIComponent(`to:"${email}"`)}`)
    ).json()) as { messages: { ID: string; Created: string }[] }
    const newest = listing.messages.sort((a, b) => b.Created.localeCompare(a.Created))[0]
    if (newest) {
      const message = (await (
        await fetch(`${MAILPIT_URL}/api/v1/message/${newest.ID}`)
      ).json()) as {
        HTML: string
      }
      const match = /\/reset-password\?token_hash=[^"\s]+/.exec(message.HTML)
      if (match) return match[0].replaceAll('&amp;', '&')
    }
    await new Promise((resolve) => setTimeout(resolve, 100))
  }
  throw new Error(`no reset email for ${email}`)
}
