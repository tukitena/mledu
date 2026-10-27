import { z } from 'zod'
import { AccountType, IsoDate, RowVersion } from './common'

/** AUTH-08: JPG/PNG/WebP up to 5,000,000 bytes, checked by the backend. */
export const AVATAR_MAX_BYTES = 5_000_000
export const AvatarContentType = z.enum(['image/jpeg', 'image/png', 'image/webp'])
export type AvatarContentType = z.infer<typeof AvatarContentType>

/** Name fields: 1–200 characters after trimming (C.1.1). */
export const PersonName = z.string().trim().min(1).max(200)
/** Optional phone; separators are removed by the backend. Empty clears it. */
export const OptionalPhone = z.string().trim().max(32).nullable()

/** GET /v1/me */
export const MyProfile = z.object({
  id: z.uuid(),
  email: z.string(),
  fullName: z.string(),
  accountType: AccountType,
  mustChangePassword: z.boolean(),
  phone: z.string().nullable(),
  birthDate: IsoDate.nullable(),
  /** Relative path in the private bucket; also the cache key of GET /v1/me/avatar. */
  avatarPath: z.string().nullable(),
  rowVersion: RowVersion,
})
export type MyProfile = z.infer<typeof MyProfile>

/** PATCH /v1/me — email, type, status and assignments are not self-service. */
export const UpdateMyProfileRequest = z.strictObject({
  fullName: PersonName,
  phone: OptionalPhone,
  birthDate: IsoDate.nullable(),
  expectedVersion: RowVersion,
})
export type UpdateMyProfileRequest = z.infer<typeof UpdateMyProfileRequest>

/** POST /v1/me/avatar/uploads — declared values are only a first check. */
export const AvatarUploadRequest = z.strictObject({
  contentType: AvatarContentType,
  size: z.number().int().min(1).max(AVATAR_MAX_BYTES),
})
export type AvatarUploadRequest = z.infer<typeof AvatarUploadRequest>

export const AvatarUploadResponse = z.object({
  path: z.string(),
  /** Signed URL for one PUT of the file to this path. Never stored or logged. */
  uploadUrl: z.url(),
})
export type AvatarUploadResponse = z.infer<typeof AvatarUploadResponse>

/** POST /v1/me/avatar — commits an uploaded file after the backend checks it. */
export const SetAvatarRequest = z.strictObject({
  path: z.string().min(1).max(200),
  expectedVersion: RowVersion,
})
export type SetAvatarRequest = z.infer<typeof SetAvatarRequest>

/** DELETE /v1/me/avatar */
export const ClearAvatarRequest = z.strictObject({ expectedVersion: RowVersion })
export type ClearAvatarRequest = z.infer<typeof ClearAvatarRequest>
