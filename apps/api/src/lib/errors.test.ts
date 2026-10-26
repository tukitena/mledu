import { describe, expect, it } from 'vitest'
import { fromDatabaseError } from './errors'

describe('fromDatabaseError', () => {
  it('maps PTxyz SQLSTATEs raised by RPCs to their status and code', () => {
    expect(fromDatabaseError({ code: 'PT401', message: 'account_disabled' })).toMatchObject({
      status: 401,
      code: 'account_disabled',
    })
    expect(fromDatabaseError({ code: 'PT403', message: 'password_change_required' })).toMatchObject(
      {
        status: 403,
        code: 'password_change_required',
      },
    )
    expect(fromDatabaseError({ code: 'PT409', message: 'version_conflict' })).toMatchObject({
      status: 409,
      code: 'version_conflict',
    })
  })

  it('falls back to the status code when the message is not a known code', () => {
    expect(fromDatabaseError({ code: 'PT403', message: 'something else' })).toMatchObject({
      status: 403,
      code: 'forbidden',
    })
  })

  it('treats rejected JWTs as invalid sessions', () => {
    expect(fromDatabaseError({ code: 'PGRST301', message: 'JWT expired' })).toMatchObject({
      status: 401,
      code: 'session_invalid',
    })
  })

  it('never forwards SQL error text', () => {
    const error = fromDatabaseError({ code: '42P01', message: 'relation "app.x" does not exist' })
    expect(error).toMatchObject({ status: 500, code: 'internal_error', message: 'internal_error' })
  })
})
