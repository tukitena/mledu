import type { Bindings } from '../env'
import { AppError } from './errors'
import type { GoTrueResult } from './gotrue'
import { createServiceClient } from './supabase'

/**
 * Outcome of the GoTrue call that executes a prepared Auth command. GoTrue's
 * transaction includes the deferred completion trigger, so an answered error
 * means nothing was changed. Only a lost response is resolved by reading the
 * command; an outcome that is still unknown is reported, not guessed.
 */
export async function settleAuthCommand(
  env: Bindings,
  requestId: string,
  commandId: string,
  result: GoTrueResult,
): Promise<'committed' | 'failed'> {
  if (result.ok) return 'committed'
  if (result.status !== 0) return 'failed'

  const { data, error } = await createServiceClient(env, requestId).rpc('auth_command_status', {
    p_command_id: commandId,
  })
  if (!error && data === 'committed') return 'committed'
  if (!error && data === 'expired') return 'failed'
  throw new AppError(503, 'dependency_unavailable', 'dependency_unavailable')
}
