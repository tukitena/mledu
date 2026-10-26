import { HealthResponse, ReadinessResponse } from '@mledu/contracts/common'
import { exports } from 'cloudflare:workers'
import { describe, expect, it } from 'vitest'

// Calls the deployed entrypoint (src/index.ts) inside workerd against Supabase local.
const worker = (path: string) => exports.default.fetch(new Request(`http://api.test${path}`))

describe('GET /v1/health', () => {
  it('reports liveness through the Worker entrypoint', async () => {
    const response = await worker('/v1/health')
    expect(response.status).toBe(200)
    expect(HealthResponse.parse(await response.json()).service).toBe('mledu-api')
  })

  it('reports the database as reachable through the exposed api schema', async () => {
    const response = await worker('/v1/health/ready')
    expect(response.status).toBe(200)
    expect(ReadinessResponse.parse(await response.json())).toEqual({
      status: 'ok',
      checks: { database: 'ok' },
    })
  })
})
