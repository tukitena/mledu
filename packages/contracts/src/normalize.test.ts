import { describe, expect, it } from 'vitest'
import { nameKey } from './normalize'

describe('nameKey (STU-04)', () => {
  it('matches names regardless of accents, đ, case and spacing', () => {
    expect(nameKey('  Đặng  Thị Ánh ')).toBe('dang thi anh')
    expect(nameKey('dang thi anh')).toBe('dang thi anh')
  })

  it('keeps punctuation', () => {
    expect(nameKey('Nguyễn Văn Ước, Jr.')).toBe('nguyen van uoc, jr.')
  })
})
