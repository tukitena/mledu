import { HealthResponse, REQUEST_ID_HEADER } from '@mledu/contracts/common'
import { describe, expect, it, vi } from 'vitest'
import { ApiError, createApiClient } from './api-client'

const health = {
  status: 'ok',
  service: 'mledu-api',
  version: 'dev',
  environment: 'local',
  time: '2026-10-26T15:00:00.000Z',
}

const json = (body: unknown, status = 200, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...headers },
  })

describe('createApiClient', () => {
  it('sends a request ID and bearer token, and validates the response', async () => {
    const fetch = vi.fn<typeof globalThis.fetch>(async () => json(health))
    const client = createApiClient({
      baseUrl: 'http://api.test/',
      getAccessToken: async () => 'jwt-value',
      fetch,
    })

    await expect(client.request('/v1/health', { schema: HealthResponse })).resolves.toEqual(health)

    const [url, init] = fetch.mock.calls[0]!
    const headers = new Headers(init?.headers)
    expect(url).toBe('http://api.test/v1/health')
    expect(headers.get('Authorization')).toBe('Bearer jwt-value')
    expect(headers.get(REQUEST_ID_HEADER)).toMatch(/^[0-9a-f-]{36}$/)
  })

  it('surfaces API error codes with the server request ID', async () => {
    const body = {
      error: { code: 'session_invalid', message: 'session_invalid', requestId: 'r-1' },
    }
    const client = createApiClient({
      baseUrl: 'http://api.test',
      fetch: async () => json(body, 401),
    })

    const error = await client.request('/v1/me', { schema: HealthResponse }).catch((e) => e)
    expect(error).toBeInstanceOf(ApiError)
    expect(error).toMatchObject({ status: 401, code: 'session_invalid', requestId: 'r-1' })
  })

  it('maps non-contract failures and network errors to stable codes', async () => {
    const gateway = createApiClient({
      baseUrl: 'http://api.test',
      fetch: async () => new Response('Bad gateway', { status: 502 }),
    })
    await expect(gateway.request('/x', { schema: HealthResponse })).rejects.toMatchObject({
      code: 'internal_error',
    })

    const offline = createApiClient({
      baseUrl: 'http://api.test',
      fetch: async () => {
        throw new TypeError('offline')
      },
    })
    await expect(offline.request('/x', { schema: HealthResponse })).rejects.toMatchObject({
      status: 0,
      code: 'dependency_unavailable',
    })
  })

  it('rejects responses that do not match the contract', async () => {
    const client = createApiClient({
      baseUrl: 'http://api.test',
      fetch: async () => json({ status: 'ok' }),
    })
    await expect(client.request('/v1/health', { schema: HealthResponse })).rejects.toMatchObject({
      code: 'internal_error',
    })
  })
})
