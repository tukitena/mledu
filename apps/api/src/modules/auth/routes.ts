import type { AcceptedResponse, PasswordChangedResponse } from '@mledu/contracts/auth'
import { CompletePasswordResetRequest, PasswordResetRequest } from '@mledu/contracts/auth'
import { Hono } from 'hono'
import type { AppEnv } from '../../env'
import { settleAuthCommand } from '../../lib/auth-command'
import { AppError, fromDatabaseError } from '../../lib/errors'
import {
  requestRecovery,
  signOutSession,
  updateOwnPassword,
  verifyEmailLink,
} from '../../lib/gotrue'
import { createUserClient } from '../../lib/supabase'
import { parseJson } from '../../lib/validation'

const linkInvalid = () => new AppError(400, 'reset_link_invalid', 'reset_link_invalid')

/** Public password-reset endpoints (AUTH-02); sign-in itself uses the Auth SDK. */
export const authRoutes = new Hono<AppEnv>()
  // The answer never tells whether the email belongs to an account, including
  // when Auth rate-limits a known address.
  .post('/password-reset', async (c) => {
    const { email } = await parseJson(c, PasswordResetRequest)
    const result = await requestRecovery(c.env, c.get('requestId'), email.toLowerCase())
    if (!result.ok && result.status !== 429) {
      // Delivery problems are for operators (Admin notification: GĐ 9); no email in the log.
      console.error(
        JSON.stringify({
          requestId: c.get('requestId'),
          error: 'recovery_request_failed',
          status: result.status,
        }),
      )
    }
    return c.json({ status: 'accepted' } satisfies AcceptedResponse, 202)
  })

  // Verifies the link and sets the password in this one request. The link
  // session stays inside the Worker; the database allows one reset per link
  // even if Auth lets the same link verify twice concurrently (G1-01).
  .post('/password-reset/complete', async (c) => {
    const body = await parseJson(c, CompletePasswordResetRequest)
    const requestId = c.get('requestId')

    const verified = await verifyEmailLink(c.env, requestId, body.tokenHash, body.type)
    const linkToken = verified.body?.access_token
    if (!verified.ok || !linkToken) throw linkInvalid()

    try {
      const db = createUserClient(c.env, linkToken, requestId)
      const { data: commandId, error } = await db.rpc('prepare_password_reset')
      if (error) {
        const mapped = fromDatabaseError(error)
        throw mapped.status === 401 || mapped.code === 'reset_link_invalid' ? linkInvalid() : mapped
      }

      const result = await updateOwnPassword(c.env, requestId, linkToken, body.password)
      if (result.errorCode === 'same_password') {
        throw new AppError(400, 'password_unchanged', 'password_unchanged')
      }
      if ((await settleAuthCommand(c.env, requestId, commandId, result)) !== 'committed') {
        throw linkInvalid()
      }
      return c.json({
        status: 'password_changed',
        signInRequired: true,
      } satisfies PasswordChangedResponse)
    } finally {
      // The reset already invalidated it; this only removes the Auth session row.
      await signOutSession(c.env, requestId, linkToken)
    }
  })
