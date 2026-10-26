import { ErrorResponse, HealthResponse, REQUEST_ID_HEADER } from '@mledu/contracts/common'
import { env } from 'cloudflare:workers'
import { describe, expect, it } from 'vitest'
import { createApp } from './app'
import { requireSession } from './middleware/session'

const app = createApp()
app.get('/probe/session', requireSession(), (c) => c.json(c.get('session')))
app.get('/probe/crash', () => {
  throw new Error('relation "app.secret_table" does not exist')
})

const request = (path: string, init?: RequestInit) => app.request(path, init, env)

describe('API foundation', () => {
  it('serves the health contract without configuration or keys', async () => {
    const response = await request('/v1/health')
    expect(response.status).toBe(200)
    const body = await response.json()
    expect(HealthResponse.parse(body)).toMatchObject({ environment: 'test' })

    const text = JSON.stringify(body)
    expect(text).not.toContain(env.SUPABASE_PUBLISHABLE_KEY)
    expect(text).not.toContain(env.SUPABASE_URL)
    expect(response.headers.get('Cache-Control')).toBe('no-store')
  })

  it('generates a request ID, or keeps a safe incoming one', async () => {
    const generated = await request('/v1/health')
    expect(generated.headers.get(REQUEST_ID_HEADER)).toMatch(/^[0-9a-f-]{36}$/)

    const kept = await request('/v1/health', { headers: { [REQUEST_ID_HEADER]: 'abc-123_x' } })
    expect(kept.headers.get(REQUEST_ID_HEADER)).toBe('abc-123_x')

    const unsafe = await request('/v1/health', {
      headers: { [REQUEST_ID_HEADER]: '<script>alert(1)</script>' },
    })
    expect(unsafe.headers.get(REQUEST_ID_HEADER)).toMatch(/^[0-9a-f-]{36}$/)
  })

  it('returns the error contract for unknown routes', async () => {
    const response = await request('/v1/nope', { headers: { [REQUEST_ID_HEADER]: 'req-404' } })
    expect(response.status).toBe(404)
    expect(ErrorResponse.parse(await response.json())).toEqual({
      error: { code: 'not_found', message: 'not_found', requestId: 'req-404' },
    })
  })

  it('hides internal error messages', async () => {
    const response = await request('/probe/crash')
    expect(response.status).toBe(500)
    const body = ErrorResponse.parse(await response.json())
    expect(body.error.code).toBe('internal_error')
    expect(JSON.stringify(body)).not.toContain('secret_table')
  })

  it('rejects calls without a bearer token before touching the database', async () => {
    const response = await request('/probe/session', { headers: { Authorization: 'Basic x' } })
    expect(response.status).toBe(401)
    expect(ErrorResponse.parse(await response.json()).error.code).toBe('unauthenticated')
  })

  it('allows CORS only for configured origins', async () => {
    const preflight = (origin: string) =>
      request('/v1/health', {
        method: 'OPTIONS',
        headers: { Origin: origin, 'Access-Control-Request-Method': 'GET' },
      })

    const allowed = await preflight('http://127.0.0.1:5173')
    expect(allowed.headers.get('Access-Control-Allow-Origin')).toBe('http://127.0.0.1:5173')

    const denied = await preflight('https://evil.example')
    expect(denied.headers.get('Access-Control-Allow-Origin')).toBeNull()
  })
})
