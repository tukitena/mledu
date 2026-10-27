import type { IssuedPasswordResponse } from '@mledu/contracts/accounts'
import {
  AccountPage,
  AccountSummary,
  CreateAccountRequest,
  ListAccountsQuery,
  SetAccountTypeRequest,
  SoftDeleteAccountRequest,
  VersionedRequest,
} from '@mledu/contracts/accounts'
import { Hono, type Context } from 'hono'
import { z } from 'zod'
import type { AppEnv } from '../../env'
import { settleAuthCommand } from '../../lib/auth-command'
import { AppError, fromDatabaseError, type PostgrestLikeError } from '../../lib/errors'
import { adminCreateUser, adminSetPassword } from '../../lib/gotrue'
import { nullable } from '../../lib/supabase'
import { generateTemporaryPassword } from '../../lib/temporary-password'
import { expectShape, parseJson, parseQuery, uuidParam } from '../../lib/validation'
import { requireSession } from '../../middleware/session'

/**
 * Account administration (AUTH-02–07). Every RPC re-checks that the caller is
 * an Admin and that the target is not an Admin account (AUTH-06).
 */
const summary = (result: { data: unknown; error: PostgrestLikeError | null }) => {
  if (result.error) throw fromDatabaseError(result.error)
  return expectShape(AccountSummary, result.data)
}

async function getAccount(c: Context<AppEnv>, accountId: string) {
  return summary(await c.get('db').rpc('get_account', { p_account_id: accountId }))
}

const CreatedCommand = z.array(z.object({ command_id: z.uuid(), account_id: z.uuid() })).length(1)

export const accountRoutes = new Hono<AppEnv>()
  .use(requireSession())

  .get('/', async (c) => {
    const query = parseQuery(c, ListAccountsQuery)
    const { data, error } = await c.get('db').rpc('list_accounts', {
      p_search: nullable(query.search || null),
      p_status: nullable(query.status),
      p_limit: query.pageSize,
      p_offset: (query.page - 1) * query.pageSize,
    })
    if (error) throw fromDatabaseError(error)
    const page = expectShape(z.object({ total: z.number(), items: z.array(z.unknown()) }), data)
    return c.json(expectShape(AccountPage, { ...page, page: query.page, pageSize: query.pageSize }))
  })

  .get('/:id', async (c) => c.json(await getAccount(c, uuidParam(c, 'id'))))

  // AUTH-07: the profile, history and audit are written by the Auth trigger
  // in the same transaction that creates the Auth user.
  .post('/', async (c) => {
    const body = await parseJson(c, CreateAccountRequest)
    const requestId = c.get('requestId')
    const prepared = await c.get('db').rpc('prepare_account_create', {
      p_email: body.email,
      p_full_name: body.fullName,
      p_phone: nullable(body.phone || null),
      p_birth_date: nullable(body.birthDate),
    })
    if (prepared.error) throw fromDatabaseError(prepared.error)
    const [command] = expectShape(CreatedCommand, prepared.data)

    const temporaryPassword = generateTemporaryPassword()
    const result = await adminCreateUser(c.env, requestId, {
      id: command!.account_id,
      email: body.email.trim().toLowerCase(),
      password: temporaryPassword,
      commandId: command!.command_id,
    })
    if (result.errorCode === 'email_exists') throw new AppError(409, 'email_taken', 'email_taken')
    if ((await settleAuthCommand(c.env, requestId, command!.command_id, result)) !== 'committed') {
      throw new AppError(409, 'conflict', 'conflict')
    }

    const account = await getAccount(c, command!.account_id)
    return c.json({ account, temporaryPassword } satisfies IssuedPasswordResponse, 201)
  })

  // AUTH-02: ends every session and old reset links; forces a change at sign-in.
  .post('/:id/temporary-password', async (c) => {
    const accountId = uuidParam(c, 'id')
    const { expectedVersion } = await parseJson(c, VersionedRequest)
    const requestId = c.get('requestId')
    const { data: commandId, error } = await c.get('db').rpc('prepare_temporary_password', {
      p_account_id: accountId,
      p_expected_version: expectedVersion,
    })
    if (error) throw fromDatabaseError(error)

    const temporaryPassword = generateTemporaryPassword()
    const result = await adminSetPassword(c.env, requestId, accountId, temporaryPassword, commandId)
    if ((await settleAuthCommand(c.env, requestId, commandId, result)) !== 'committed') {
      throw new AppError(409, 'conflict', 'conflict')
    }

    const account = await getAccount(c, accountId)
    return c.json({ account, temporaryPassword } satisfies IssuedPasswordResponse)
  })

  // AUTH-03
  .post('/:id/disable', async (c) => {
    const { expectedVersion } = await parseJson(c, VersionedRequest)
    return c.json(
      summary(
        await c.get('db').rpc('set_account_enabled', {
          p_account_id: uuidParam(c, 'id'),
          p_enabled: false,
          p_expected_version: expectedVersion,
        }),
      ),
    )
  })

  .post('/:id/enable', async (c) => {
    const { expectedVersion } = await parseJson(c, VersionedRequest)
    return c.json(
      summary(
        await c.get('db').rpc('set_account_enabled', {
          p_account_id: uuidParam(c, 'id'),
          p_enabled: true,
          p_expected_version: expectedVersion,
        }),
      ),
    )
  })

  // AUTH-04
  .post('/:id/delete', async (c) => {
    const body = await parseJson(c, SoftDeleteAccountRequest)
    return c.json(
      summary(
        await c.get('db').rpc('soft_delete_account', {
          p_account_id: uuidParam(c, 'id'),
          p_reason: body.reason,
          p_expected_version: body.expectedVersion,
        }),
      ),
    )
  })

  // AUTH-05
  .post('/:id/restore', async (c) => {
    const { expectedVersion } = await parseJson(c, VersionedRequest)
    return c.json(
      summary(
        await c.get('db').rpc('restore_account', {
          p_account_id: uuidParam(c, 'id'),
          p_expected_version: expectedVersion,
        }),
      ),
    )
  })

  // AUTH-07
  .put('/:id/type', async (c) => {
    const body = await parseJson(c, SetAccountTypeRequest)
    return c.json(
      summary(
        await c.get('db').rpc('set_account_type', {
          p_account_id: uuidParam(c, 'id'),
          p_account_type: body.accountType,
          p_expected_version: body.expectedVersion,
        }),
      ),
    )
  })
