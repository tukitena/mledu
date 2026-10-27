import { API_VERSION, REQUEST_ID_HEADER, type ErrorResponse } from '@mledu/contracts/common'
import { Hono, type Context } from 'hono'
import { cors } from 'hono/cors'
import { HTTPException } from 'hono/http-exception'
import { requestId } from 'hono/request-id'
import { secureHeaders } from 'hono/secure-headers'
import type { AppEnv } from './env'
import { AppError, codeForStatus } from './lib/errors'
import { accountRoutes } from './modules/accounts/routes'
import { authRoutes } from './modules/auth/routes'
import { healthRoutes } from './modules/health/routes'
import { profileRoutes } from './modules/profile/routes'

const allowedOrigins = (value: string) =>
  value
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean)

function errorResponse(c: Context<AppEnv>, error: AppError) {
  const body: ErrorResponse = {
    error: {
      code: error.code,
      message: error.message,
      requestId: c.get('requestId'),
      ...(error.details ? { details: error.details } : {}),
    },
  }
  return c.json(body, error.status)
}

export function createApp() {
  const app = new Hono<AppEnv>()

  app.use(requestId({ headerName: REQUEST_ID_HEADER, limitLength: 64 }))
  app.use(secureHeaders())
  app.use('*', async (c, next) => {
    await next()
    // API responses may contain personal data; never cache them in shared caches.
    c.header('Cache-Control', 'no-store')
  })
  // CORS only controls which browsers may read responses; it is not authorization.
  app.use(
    cors({
      origin: (origin, c) =>
        allowedOrigins((c as Context<AppEnv>).env.ALLOWED_ORIGINS).includes(origin) ? origin : null,
      allowHeaders: ['Authorization', 'Content-Type', REQUEST_ID_HEADER],
      allowMethods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'],
      exposeHeaders: [REQUEST_ID_HEADER],
      maxAge: 600,
    }),
  )

  app.route(`/${API_VERSION}/health`, healthRoutes)
  app.route(`/${API_VERSION}/auth`, authRoutes)
  app.route(`/${API_VERSION}/me`, profileRoutes)
  app.route(`/${API_VERSION}/accounts`, accountRoutes)

  app.notFound((c) => errorResponse(c, new AppError(404, 'not_found', 'not_found')))
  app.onError((error, c) => {
    if (error instanceof AppError) return errorResponse(c, error)
    if (error instanceof HTTPException) {
      const code = codeForStatus(error.status)
      return errorResponse(c, new AppError(error.status, code, code))
    }
    // Log only the request ID and error type; messages may contain input data.
    console.error(JSON.stringify({ requestId: c.get('requestId'), error: error.name }))
    return errorResponse(c, new AppError(500, 'internal_error', 'internal_error'))
  })

  return app
}
