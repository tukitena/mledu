import type { z } from 'zod'
import { fromDatabaseError, type PostgrestLikeError } from './errors'
import { expectShape } from './validation'

/** Unwraps an RPC result, mapping database errors and checking the contract shape. */
export function rpcResult<T extends z.ZodType>(
  schema: T,
  result: { data: unknown; error: PostgrestLikeError | null },
): z.infer<T> {
  if (result.error) throw fromDatabaseError(result.error)
  return expectShape(schema, result.data)
}
