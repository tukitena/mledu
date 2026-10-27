import type { Context } from 'hono'
import type { z } from 'zod'
import { AppError } from './errors'

const toAppError = (error: z.ZodError) =>
  new AppError(
    400,
    'validation_failed',
    'validation_failed',
    error.issues.map((issue) => ({ path: issue.path.join('.'), message: issue.code })),
  )

/** Parses a JSON body; unknown keys are rejected by the strict contract schemas. */
export async function parseJson<T extends z.ZodType>(c: Context, schema: T): Promise<z.infer<T>> {
  const body: unknown = await c.req.json().catch(() => {
    throw new AppError(400, 'bad_request', 'bad_request')
  })
  const parsed = schema.safeParse(body)
  if (!parsed.success) throw toAppError(parsed.error)
  return parsed.data
}

export function parseQuery<T extends z.ZodType>(c: Context, schema: T): z.infer<T> {
  const parsed = schema.safeParse(c.req.query())
  if (!parsed.success) throw toAppError(parsed.error)
  return parsed.data
}

/** Validates a database/JSON result against its contract before returning it. */
export function expectShape<T extends z.ZodType>(schema: T, value: unknown): z.infer<T> {
  const parsed = schema.safeParse(value)
  if (!parsed.success) throw new AppError(500, 'internal_error', 'internal_error')
  return parsed.data
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export function uuidParam(c: Context, name: string): string {
  const value = c.req.param(name)
  if (!value || !UUID.test(value)) throw new AppError(404, 'not_found', 'not_found')
  return value.toLowerCase()
}
