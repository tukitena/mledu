import { describe, expect, it } from 'vitest'
import { nameKey, phoneKey } from './normalize'

describe('nameKey (STU-04)', () => {
  it('matches names regardless of accents, đ, case and spacing', () => {
    expect(nameKey('  Đặng  Thị Ánh ')).toBe('dang thi anh')
    expect(nameKey('dang thi anh')).toBe('dang thi anh')
  })

  it('keeps punctuation', () => {
    expect(nameKey('Nguyễn Văn Ước, Jr.')).toBe('nguyen van uoc, jr.')
  })
})

describe('phoneKey (STU-04)', () => {
  it('matches Vietnamese numbers written with +84, 0084 or separators', () => {
    expect(phoneKey('0912 345 678')).toBe('0912345678')
    expect(phoneKey('+84 912345678')).toBe('0912345678')
    expect(phoneKey('0084 (912) 345-678')).toBe('0912345678')
  })

  it('keeps foreign numbers and refuses invalid input', () => {
    expect(phoneKey('+44 20.7946.0958')).toBe('+442079460958')
    expect(phoneKey('09l2345678')).toBeNull()
    expect(phoneKey('091234')).toBeNull()
  })
})
