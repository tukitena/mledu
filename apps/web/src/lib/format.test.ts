import { describe, expect, it } from 'vitest'
import {
  formatIsoDate,
  formatInstant,
  formatMonth,
  parseDisplayDate,
  formatSchoolYear,
} from './format'

describe('formatIsoDate', () => {
  it('keeps the calendar day whatever the browser time zone', () => {
    expect(formatIsoDate('2026-01-31')).toBe('31-01-2026')
    expect(formatIsoDate(null)).toBe('')
  })
})

it('parses the exact display format without rolling invalid days into another month', () => {
  expect(parseDisplayDate('29-02-2024')).toBe('2024-02-29')
  expect(parseDisplayDate('01-01-1900')).toBe('1900-01-01')
  for (const value of ['29-02-2026', '31-04-2026', '01-13-2026', '01-01-26', '2026-01-01', '']) {
    expect(parseDisplayDate(value)).toBeNull()
  }
})

it('formats instants in business time and month labels in the app language', () => {
  expect(formatInstant('2026-12-31T18:05:00Z')).toBe('01-01-2027 01:05')
  expect(formatInstant(null)).toBe('')
  expect(formatMonth('2026-11', 'vi')).toBe('Tháng 11 2026')
  expect(formatMonth('2026-11', 'en')).toBe('November 2026')
})

it('displays consecutive school years and leaves no-year labels to i18n', () => {
  expect(formatSchoolYear(2026)).toBe('2026–2027')
  expect(formatSchoolYear(9998)).toBe('9998–9999')
  expect(formatSchoolYear(null)).toBe('')
})
