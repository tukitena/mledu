import { z } from 'zod'

/** Prefix of every versioned API route. */
export const API_VERSION = 'v1'

/** Header that carries the request ID in both directions. */
export const REQUEST_ID_HEADER = 'X-Request-Id'

/** Account type stored on the account profile (AUTH-07). Class roles are separate. */
export const AccountType = z.enum(['admin', 'receptionist', 'user'])
export type AccountType = z.infer<typeof AccountType>

/**
 * Stable machine-readable error codes. UI text is chosen by the client from the
 * code; `message` is a short English fallback for logs and developers.
 */
export const ErrorCode = z.enum([
  'bad_request',
  'validation_failed',
  'unauthenticated',
  'session_invalid',
  'account_disabled',
  'password_change_required',
  'forbidden',
  'not_found',
  'method_not_allowed',
  'version_conflict',
  'conflict',
  'payload_too_large',
  'rate_limited',
  'dependency_unavailable',
  'internal_error',
])
export type ErrorCode = z.infer<typeof ErrorCode>

export const ErrorResponse = z.object({
  error: z.object({
    code: ErrorCode,
    message: z.string(),
    requestId: z.string(),
    /** Field-level problems for `validation_failed`; never contains secrets. */
    details: z.array(z.object({ path: z.string(), message: z.string() })).optional(),
  }),
})
export type ErrorResponse = z.infer<typeof ErrorResponse>

export const PageQuery = z.object({
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(20),
})
export type PageQuery = z.infer<typeof PageQuery>

export const pageOf = <T extends z.ZodType>(item: T) =>
  z.object({
    items: z.array(item),
    page: z.number().int().min(1),
    pageSize: z.number().int().min(1),
    total: z.number().int().min(0),
  })

export const HealthResponse = z.object({
  status: z.literal('ok'),
  service: z.literal('mledu-api'),
  version: z.string(),
  environment: z.enum(['local', 'test', 'staging', 'production']),
  time: z.iso.datetime({ offset: true }),
})
export type HealthResponse = z.infer<typeof HealthResponse>

export const ReadinessResponse = z.object({
  status: z.enum(['ok', 'degraded']),
  checks: z.object({ database: z.enum(['ok', 'unavailable']) }),
})
export type ReadinessResponse = z.infer<typeof ReadinessResponse>
