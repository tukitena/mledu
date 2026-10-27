import { ErrorResponse, REQUEST_ID_HEADER, type ErrorCode } from '@mledu/contracts/common'
import type { z } from 'zod'

/** Error returned by the API, or a network failure mapped to `dependency_unavailable`. */
export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: ErrorCode,
    readonly requestId: string,
    message: string,
    /** Field problems or, for conflicts, the other records involved (e.g. student codes). */
    readonly details: { path: string; message: string }[] = [],
  ) {
    super(message)
    this.name = 'ApiError'
  }
}

export interface ApiClientOptions {
  baseUrl: string
  /** Current Supabase access token; omitted for public endpoints. */
  getAccessToken?: () => Promise<string | null>
  fetch?: typeof fetch
}

export interface RequestOptions<T extends z.ZodType> {
  method?: 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE'
  body?: unknown
  /** Response schema; responses that do not match are treated as errors. */
  schema: T
}

const fallbackCode = (status: number): ErrorCode =>
  status === 401
    ? 'unauthenticated'
    : status === 403
      ? 'forbidden'
      : status === 404
        ? 'not_found'
        : status >= 500
          ? 'internal_error'
          : 'bad_request'

/** Calls the Worker API. Business data never goes to Supabase directly from the browser. */
export function createApiClient({ baseUrl, getAccessToken, fetch: fetchImpl }: ApiClientOptions) {
  const base = baseUrl.replace(/\/+$/, '')
  const doFetch = fetchImpl ?? globalThis.fetch.bind(globalThis)

  async function request<T extends z.ZodType>(
    path: string,
    { method = 'GET', body, schema }: RequestOptions<T>,
  ): Promise<z.infer<T>> {
    const requestId = crypto.randomUUID()
    const headers = new Headers({ [REQUEST_ID_HEADER]: requestId, Accept: 'application/json' })
    const token = await getAccessToken?.()
    if (token) headers.set('Authorization', `Bearer ${token}`)
    if (body !== undefined) headers.set('Content-Type', 'application/json')

    let response: Response
    try {
      response = await doFetch(`${base}${path}`, {
        method,
        headers,
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      })
    } catch {
      throw new ApiError(0, 'dependency_unavailable', requestId, 'Network request failed')
    }

    const responseId = response.headers.get(REQUEST_ID_HEADER) ?? requestId
    const payload: unknown = await response.json().catch(() => null)

    if (!response.ok) {
      const parsed = ErrorResponse.safeParse(payload)
      if (parsed.success) {
        const { code, message, requestId: id, details } = parsed.data.error
        throw new ApiError(response.status, code, id, message, details)
      }
      const code = fallbackCode(response.status)
      throw new ApiError(response.status, code, responseId, code)
    }

    const parsed = schema.safeParse(payload)
    if (!parsed.success) {
      throw new ApiError(response.status, 'internal_error', responseId, 'Unexpected response shape')
    }
    return parsed.data
  }

  return { request }
}

export type ApiClient = ReturnType<typeof createApiClient>
