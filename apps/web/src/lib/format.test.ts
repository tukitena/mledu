import { describe, expect, it } from 'vitest'
import { formatIsoDate } from './format'

describe('formatIsoDate', () => {
  it('keeps the calendar day whatever the browser time zone', () => {
    expect(formatIsoDate('2026-01-31', 'vi')).toBe('31/01/2026')
    expect(formatIsoDate('2026-01-31', 'en')).toBe('31/01/2026')
    expect(formatIsoDate(null, 'vi')).toBe('')
  })
})
