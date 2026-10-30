import { describe, expect, it } from 'vitest'
import { formatIsoDate, formatSchoolYear } from './format'

describe('formatIsoDate', () => {
  it('keeps the calendar day whatever the browser time zone', () => {
    expect(formatIsoDate('2026-01-31', 'vi')).toBe('31/01/2026')
    expect(formatIsoDate('2026-01-31', 'en')).toBe('31/01/2026')
    expect(formatIsoDate(null, 'vi')).toBe('')
  })
})

it('displays consecutive school years and leaves no-year labels to i18n', () => {
  expect(formatSchoolYear(2026)).toBe('2026–2027')
  expect(formatSchoolYear(9998)).toBe('9998–9999')
  expect(formatSchoolYear(null)).toBe('')
})
