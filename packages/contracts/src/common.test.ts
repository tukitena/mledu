import { describe, expect, it } from 'vitest'
import { ErrorResponse, HealthResponse, PageQuery } from './common'

describe('common contracts', () => {
  it('bounds page size', () => {
    expect(PageQuery.parse({})).toEqual({ page: 1, pageSize: 20 })
    expect(PageQuery.safeParse({ pageSize: '101' }).success).toBe(false)
    expect(PageQuery.safeParse({ page: '0' }).success).toBe(false)
  })

  it('rejects unknown error codes', () => {
    const body = { error: { code: 'teapot', message: 'x', requestId: 'r' } }
    expect(ErrorResponse.safeParse(body).success).toBe(false)
  })

  it('accepts a health payload with an offset timestamp', () => {
    const body = {
      status: 'ok',
      service: 'mledu-api',
      version: 'dev',
      environment: 'local',
      time: '2026-10-26T15:00:00.000Z',
    }
    expect(HealthResponse.parse(body)).toEqual(body)
  })
})
