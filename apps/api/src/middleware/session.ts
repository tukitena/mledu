import { AccountType } from '@mledu/contracts/common'
import { createMiddleware } from 'hono/factory'
import type { AppEnv } from '../env'
import { AppError, fromDatabaseError } from '../lib/errors'
import { createUserClient } from '../lib/supabase'

const BEARER = /^Bearer ([A-Za-z0-9._~+/-]+=*)$/

interface SessionOptions {
  /** Allow accounts that still must change their password (AUTH-01/02 flows only). */
  allowPasswordChange?: boolean
}

/**
 * Resolves the caller on every request from the database: the JWT must belong
 * to a live Auth session and an enabled, non-deleted account. Roles inside the
 * JWT are never used for authorization, so changes apply to the next request.
 */
export const requireSession = ({ allowPasswordChange = false }: SessionOptions = {}) =>
  createMiddleware<AppEnv>(async (c, next) => {
    const token = BEARER.exec(c.req.header('Authorization') ?? '')?.[1]
    if (!token) throw new AppError(401, 'unauthenticated', 'unauthenticated')

    const db = createUserClient(c.env, token, c.get('requestId'))
    const { data, error } = await db
      .rpc('current_session', { p_allow_password_change: allowPasswordChange })
      .single()
    if (error) throw fromDatabaseError(error)

    const accountType = AccountType.safeParse(data.account_type)
    if (!accountType.success) throw new AppError(500, 'internal_error', 'internal_error')

    c.set('db', db)
    c.set('accessToken', token)
    c.set('session', {
      accountId: data.account_id,
      accountType: accountType.data,
      mustChangePassword: data.must_change_password,
    })
    await next()
  })
