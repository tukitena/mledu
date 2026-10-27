import { describe, expect, it } from 'vitest'
import { ChangePasswordRequest, CompletePasswordResetRequest } from './auth'
import { CreateAccountRequest, SetAccountTypeRequest } from './accounts'
import { UpdateMyProfileRequest } from './profile'
import { workspacesFor } from './common'

describe('auth and account contracts', () => {
  it('accepts 8+ characters without composition rules, up to 72 bytes', () => {
    expect(ChangePasswordRequest.safeParse({ password: 'aaaaaaaa' }).success).toBe(true)
    expect(ChangePasswordRequest.safeParse({ password: 'aaaaaaa' }).success).toBe(false)
    expect(ChangePasswordRequest.safeParse({ password: 'a'.repeat(72) }).success).toBe(true)
    // 25 three-byte characters = 75 bytes.
    expect(ChangePasswordRequest.safeParse({ password: 'ạ'.repeat(25) }).success).toBe(false)
  })

  it('rejects unknown keys, so email cannot ride along a profile update', () => {
    const body = { fullName: 'A', phone: null, birthDate: null, expectedVersion: 1 }
    expect(UpdateMyProfileRequest.safeParse(body).success).toBe(true)
    expect(UpdateMyProfileRequest.safeParse({ ...body, email: 'x@example.com' }).success).toBe(
      false,
    )
    expect(UpdateMyProfileRequest.safeParse({ ...body, fullName: '   ' }).success).toBe(false)
  })

  it('never lets the account API grant Admin (AUTH-06)', () => {
    expect(
      SetAccountTypeRequest.safeParse({ accountType: 'admin', expectedVersion: 1 }).success,
    ).toBe(false)
    expect(
      CreateAccountRequest.safeParse({
        email: 'a@example.com',
        fullName: 'A',
        accountType: 'admin',
      }).success,
    ).toBe(false)
  })

  it('accepts only reset link types issued by the templates', () => {
    const body = { tokenHash: 'x'.repeat(56), password: 'aaaaaaaa' }
    expect(CompletePasswordResetRequest.safeParse({ ...body, type: 'recovery' }).success).toBe(true)
    expect(CompletePasswordResetRequest.safeParse({ ...body, type: 'signup' }).success).toBe(false)
  })

  it('maps account types to workspaces (A.2)', () => {
    expect(workspacesFor('admin')).toEqual(['admin', 'receptionist', 'user'])
    expect(workspacesFor('receptionist')).toEqual(['receptionist'])
    expect(workspacesFor('user')).toEqual(['user'])
  })
})
