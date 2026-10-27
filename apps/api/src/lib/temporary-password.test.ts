import { PASSWORD_MIN_LENGTH } from '@mledu/contracts/auth'
import { describe, expect, it } from 'vitest'
import { generateTemporaryPassword } from './temporary-password'

describe('generateTemporaryPassword', () => {
  it('meets the password policy and avoids look-alike characters', () => {
    for (let i = 0; i < 200; i++) {
      const password = generateTemporaryPassword()
      expect(password.length).toBeGreaterThanOrEqual(PASSWORD_MIN_LENGTH)
      expect(password).toMatch(/^[A-HJ-NP-Za-km-np-z2-9]{12}$/)
    }
  })

  it('does not repeat', () => {
    const seen = new Set(Array.from({ length: 500 }, generateTemporaryPassword))
    expect(seen.size).toBe(500)
  })
})
