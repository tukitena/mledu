import type { Locator, Page } from '@playwright/test'

export const displayDate = (iso: string) => iso.split('-').reverse().join('-')

export async function pickMonth(page: Page, input: Locator, iso: string) {
  await input.click()
  const picker = page.locator(`[id="${await input.getAttribute('aria-controls')}"]`)
  await picker.locator('input[type="number"]').fill(iso.slice(0, 4))
  await picker
    .locator('.date-calendar-months button')
    .nth(Number(iso.slice(5, 7)) - 1)
    .click()
}
