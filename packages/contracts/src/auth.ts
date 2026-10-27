import { z } from 'zod'

/** AUTH-01/08: at least 8 characters, no composition rules. */
export const PASSWORD_MIN_LENGTH = 8
/** Supabase Auth hashes with bcrypt, which only uses the first 72 bytes. */
export const PASSWORD_MAX_BYTES = 72

// Counted by code point so the contract needs no runtime-specific TextEncoder.
const utf8Length = (value: string) => {
  let bytes = 0
  for (const char of value) {
    const codePoint = char.codePointAt(0)!
    bytes += codePoint < 0x80 ? 1 : codePoint < 0x800 ? 2 : codePoint < 0x10000 ? 3 : 4
  }
  return bytes
}

export const Password = z
  .string()
  .min(PASSWORD_MIN_LENGTH)
  .refine((value) => utf8Length(value) <= PASSWORD_MAX_BYTES, { message: 'too_long' })

/** POST /v1/me/password — own change, also the forced first change (AUTH-01/08). */
export const ChangePasswordRequest = z.strictObject({ password: Password })
export type ChangePasswordRequest = z.infer<typeof ChangePasswordRequest>

/** POST /v1/auth/password-reset — always answered the same way (AUTH-02). */
export const PasswordResetRequest = z.strictObject({ email: z.string().trim().min(3).max(254) })
export type PasswordResetRequest = z.infer<typeof PasswordResetRequest>

/**
 * POST /v1/auth/password-reset/complete — token hash from the email link. The
 * Worker verifies it and sets the password in the same request; no session
 * from the link ever reaches the browser.
 */
export const CompletePasswordResetRequest = z.strictObject({
  tokenHash: z.string().min(10).max(200),
  type: z.enum(['recovery', 'magiclink']),
  password: Password,
})
export type CompletePasswordResetRequest = z.infer<typeof CompletePasswordResetRequest>

export const AcceptedResponse = z.object({ status: z.literal('accepted') })
export type AcceptedResponse = z.infer<typeof AcceptedResponse>

export const PasswordChangedResponse = z.object({
  status: z.literal('password_changed'),
  /** True when every session ended and the user must sign in again (reset). */
  signInRequired: z.boolean(),
})
export type PasswordChangedResponse = z.infer<typeof PasswordChangedResponse>
