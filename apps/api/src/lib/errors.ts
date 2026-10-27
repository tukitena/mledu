import { ErrorCode } from '@mledu/contracts/common'
import type { ContentfulStatusCode } from 'hono/utils/http-status'

export interface ErrorDetail {
  path: string
  message: string
}

/** An error that is safe to return to the client as-is. */
export class AppError extends Error {
  constructor(
    readonly status: ContentfulStatusCode,
    readonly code: ErrorCode,
    message: string,
    readonly details?: ErrorDetail[],
  ) {
    super(message)
    this.name = 'AppError'
  }
}

const STATUS_CODES: Partial<Record<number, ErrorCode>> = {
  400: 'bad_request',
  401: 'unauthenticated',
  403: 'forbidden',
  404: 'not_found',
  405: 'method_not_allowed',
  409: 'conflict',
  413: 'payload_too_large',
  429: 'rate_limited',
  503: 'dependency_unavailable',
}

export const codeForStatus = (status: number): ErrorCode =>
  STATUS_CODES[status] ?? (status >= 500 ? 'internal_error' : 'bad_request')

/** Shape of errors returned by PostgREST through supabase-js. */
export interface PostgrestLikeError {
  code?: string
  message?: string
  /** DETAIL of the raised error; app_private.raise_api_conflict puts ErrorDetail[] JSON here. */
  details?: string | null
}

/** Conflict details from the database: only {path, message} strings are passed on. */
function conflictDetails(details: string | null | undefined): ErrorDetail[] | undefined {
  if (!details) return undefined
  try {
    const parsed: unknown = JSON.parse(details)
    if (!Array.isArray(parsed)) return undefined
    const items = parsed.filter(
      (item): item is ErrorDetail =>
        typeof item?.path === 'string' && typeof item?.message === 'string',
    )
    return items.length ? items.slice(0, 20) : undefined
  } catch {
    return undefined
  }
}

/**
 * Database functions raise `PTxyz` SQLSTATEs (PostgREST maps them to HTTP xyz)
 * with an ErrorCode as the message. Everything else is hidden behind a generic
 * error so SQL details never reach the client.
 */
export function fromDatabaseError(error: PostgrestLikeError): AppError {
  const sqlstate = error.code ?? ''
  const raised = ErrorCode.safeParse(error.message)
  const ptStatus = /^PT(\d{3})$/.exec(sqlstate)?.[1]
  if (ptStatus) {
    const status = Number(ptStatus) as ContentfulStatusCode
    const code = raised.success ? raised.data : codeForStatus(status)
    return new AppError(
      status,
      code,
      code,
      status === 409 ? conflictDetails(error.details) : undefined,
    )
  }
  switch (sqlstate) {
    // PostgREST rejected the JWT (expired, malformed or wrong signature).
    case 'PGRST301':
    case 'PGRST303':
      return new AppError(401, 'session_invalid', 'session_invalid')
    case '23505':
      return new AppError(409, 'conflict', 'conflict')
    case '22023':
    case '23514':
      return new AppError(400, 'validation_failed', 'validation_failed')
    default:
      return new AppError(500, 'internal_error', 'internal_error')
  }
}
