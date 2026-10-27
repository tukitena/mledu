import type { PasswordChangedResponse } from '@mledu/contracts/auth'
import { ChangePasswordRequest } from '@mledu/contracts/auth'
import {
  AVATAR_MAX_BYTES,
  AvatarUploadRequest,
  AvatarUploadResponse,
  ClearAvatarRequest,
  MyProfile,
  SetAvatarRequest,
  UpdateMyProfileRequest,
} from '@mledu/contracts/profile'
import { Hono, type Context } from 'hono'
import { z } from 'zod'
import type { AppEnv } from '../../env'
import { settleAuthCommand } from '../../lib/auth-command'
import { AppError, fromDatabaseError } from '../../lib/errors'
import { updateOwnPassword } from '../../lib/gotrue'
import { createServiceClient, nullable } from '../../lib/supabase'
import { expectShape, parseJson } from '../../lib/validation'
import { requireSession } from '../../middleware/session'
import { AVATAR_EXTENSION, CONTENT_TYPE_OF_EXTENSION, detectImageType } from './image'

const BUCKET = 'avatars'
const AVATAR_PATH = /^([0-9a-f-]{36})\/[A-Za-z0-9_-]{1,64}\.(jpg|png|webp)$/

const AvatarChange = z.object({ profile: MyProfile, previousPath: z.string().nullable() })

const invalidAvatar = () => new AppError(400, 'avatar_invalid', 'avatar_invalid')

/**
 * Marks an upload that will not be committed (or a replaced avatar) and
 * deletes its file when no profile references it. Failures leave an orphan
 * file for the clean-up job (GĐ 9); they never undo a committed change.
 */
async function discardAvatarFile(c: Context<AppEnv>, path: string) {
  try {
    const service = createServiceClient(c.env, c.get('requestId'))
    const { data: safe, error } = await service.rpc('discard_avatar_upload', { p_path: path })
    if (!error && safe) await service.storage.from(BUCKET).remove([path])
  } catch {
    console.error(JSON.stringify({ requestId: c.get('requestId'), error: 'avatar_cleanup_failed' }))
  }
}

export const profileRoutes = new Hono<AppEnv>()
  // Readable during the forced password change so the SPA can route there.
  .get('/', requireSession({ allowPasswordChange: true }), async (c) => {
    const { data, error } = await c.get('db').rpc('get_my_profile')
    if (error) throw fromDatabaseError(error)
    return c.json(expectShape(MyProfile, data))
  })

  .patch('/', requireSession(), async (c) => {
    const body = await parseJson(c, UpdateMyProfileRequest)
    const { data, error } = await c.get('db').rpc('update_my_profile', {
      p_full_name: body.fullName,
      // Empty values clear optional fields; the database normalizes the rest.
      p_phone: nullable(body.phone || null),
      p_birth_date: nullable(body.birthDate),
      p_expected_version: body.expectedVersion,
    })
    if (error) throw fromDatabaseError(error)
    return c.json(expectShape(MyProfile, data))
  })

  // AUTH-01/08: own password, including the forced first change. The current
  // session is kept; Supabase Auth ends the others in the same transaction.
  .post('/password', requireSession({ allowPasswordChange: true }), async (c) => {
    const { password } = await parseJson(c, ChangePasswordRequest)
    const requestId = c.get('requestId')
    const { data: commandId, error } = await c.get('db').rpc('prepare_password_change')
    if (error) throw fromDatabaseError(error)

    const result = await updateOwnPassword(c.env, requestId, c.get('accessToken'), password)
    if (result.errorCode === 'same_password') {
      throw new AppError(400, 'password_unchanged', 'password_unchanged')
    }
    if (result.errorCode === 'weak_password') {
      throw new AppError(400, 'validation_failed', 'validation_failed')
    }
    if ((await settleAuthCommand(c.env, requestId, commandId, result)) !== 'committed') {
      throw new AppError(409, 'conflict', 'conflict')
    }
    return c.json({
      status: 'password_changed',
      signInRequired: false,
    } satisfies PasswordChangedResponse)
  })

  // Step 1 of an avatar change: a new single-use path and a signed upload URL.
  .post('/avatar/uploads', requireSession(), async (c) => {
    const body = await parseJson(c, AvatarUploadRequest)
    const { data: path, error } = await c.get('db').rpc('reserve_avatar_upload', {
      p_extension: AVATAR_EXTENSION[body.contentType],
    })
    if (error) throw fromDatabaseError(error)

    const service = createServiceClient(c.env, c.get('requestId'))
    const signed = await service.storage.from(BUCKET).createSignedUploadUrl(path)
    if (signed.error) throw new AppError(503, 'dependency_unavailable', 'dependency_unavailable')
    return c.json(
      expectShape(AvatarUploadResponse, { path, uploadUrl: signed.data.signedUrl }),
      201,
    )
  })

  // Step 2: check the stored file itself, then switch avatar_path with audit.
  .post('/avatar', requireSession(), async (c) => {
    const body = await parseJson(c, SetAvatarRequest)
    const match = AVATAR_PATH.exec(body.path)
    if (!match || match[1] !== c.get('session').accountId) throw invalidAvatar()

    const service = createServiceClient(c.env, c.get('requestId'))
    const file = await service.storage.from(BUCKET).download(body.path)
    if (file.error) throw invalidAvatar()
    const bytes = new Uint8Array(await file.data.arrayBuffer())
    if (
      bytes.length === 0 ||
      bytes.length > AVATAR_MAX_BYTES ||
      detectImageType(bytes) !== CONTENT_TYPE_OF_EXTENSION[match[2]!]
    ) {
      await discardAvatarFile(c, body.path)
      throw invalidAvatar()
    }

    const marked = await service.rpc('mark_avatar_verified', { p_path: body.path })
    if (marked.error) throw fromDatabaseError(marked.error)

    const { data, error } = await c.get('db').rpc('set_my_avatar', {
      p_path: body.path,
      p_expected_version: body.expectedVersion,
    })
    if (error) {
      // The old avatar stays current; the new file is not referenced.
      await discardAvatarFile(c, body.path)
      throw fromDatabaseError(error)
    }
    const change = expectShape(AvatarChange, data)
    if (change.previousPath) await discardAvatarFile(c, change.previousPath)
    return c.json(change.profile)
  })

  .delete('/avatar', requireSession(), async (c) => {
    const body = await parseJson(c, ClearAvatarRequest)
    const { data, error } = await c.get('db').rpc('clear_my_avatar', {
      p_expected_version: body.expectedVersion,
    })
    if (error) throw fromDatabaseError(error)
    const change = expectShape(AvatarChange, data)
    if (change.previousPath) await discardAvatarFile(c, change.previousPath)
    return c.json(change.profile)
  })

  // Served through the Worker so read access is checked on every request.
  .get('/avatar', requireSession(), async (c) => {
    const { data, error } = await c.get('db').rpc('get_my_profile')
    if (error) throw fromDatabaseError(error)
    const { avatarPath } = expectShape(MyProfile, data)
    if (!avatarPath) throw new AppError(404, 'not_found', 'not_found')

    const file = await createServiceClient(c.env, c.get('requestId'))
      .storage.from(BUCKET)
      .download(avatarPath)
    if (file.error) throw new AppError(404, 'not_found', 'not_found')
    const extension = avatarPath.slice(avatarPath.lastIndexOf('.') + 1)
    return c.body(await file.data.arrayBuffer(), 200, {
      'Content-Type': CONTENT_TYPE_OF_EXTENSION[extension] ?? 'application/octet-stream',
      'X-Content-Type-Options': 'nosniff',
    })
  })
