import { ErrorCode } from '@mledu/contracts/common'
import { ApiError } from '../lib/api-client'

/** A user-facing message for an API (or Auth SDK) failure, chosen from the error code. */
export interface DescribedError {
  code: ErrorCode
  requestId?: string
}

export function describeError(error: unknown): DescribedError {
  if (error instanceof ApiError) {
    return { code: error.code, ...(error.requestId ? { requestId: error.requestId } : {}) }
  }
  // Auth SDK errors carry the access token hook message (account_disabled, …).
  const message = (error as { message?: unknown } | null)?.message
  const parsed = ErrorCode.safeParse(message)
  if (parsed.success) return { code: parsed.data }
  const status = (error as { status?: unknown } | null)?.status
  if (status === 429) return { code: 'rate_limited' }
  return { code: 'internal_error' }
}
