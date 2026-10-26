import type { HealthResponse, ReadinessResponse } from '@mledu/contracts/common'
import { Hono } from 'hono'
import type { AppEnv } from '../../env'
import { createPublicClient } from '../../lib/supabase'

/** Health endpoints never return configuration, URLs or keys. */
export const healthRoutes = new Hono<AppEnv>()
  .get('/', (c) =>
    c.json({
      status: 'ok',
      service: 'mledu-api',
      version: c.env.APP_VERSION,
      environment: c.env.APP_ENV,
      time: new Date().toISOString(),
    } satisfies HealthResponse),
  )
  .get('/ready', async (c) => {
    let database: ReadinessResponse['checks']['database'] = 'unavailable'
    try {
      const { data, error } = await createPublicClient(c.env, c.get('requestId')).rpc(
        'health_check',
      )
      if (!error && data === true) database = 'ok'
    } catch {
      // Network failures are reported as `unavailable` below.
    }
    const body: ReadinessResponse = {
      status: database === 'ok' ? 'ok' : 'degraded',
      checks: { database },
    }
    return c.json(body, database === 'ok' ? 200 : 503)
  })
