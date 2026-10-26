import { createClient } from '@supabase/supabase-js';
import type { SupabaseClient } from '@supabase/supabase-js';

type Config = { url: string; anonKey: string; serviceKey?: string };

export async function applyAuthStatus(config: Config, user: SupabaseClient, target: string,
  action: 'disable' | 'enable', requestId: string) {
  const prepared = await user.rpc('spike_prepare_auth_command', {
    p_target: target, p_action: action, p_request_id: requestId,
  });
  if (prepared.error) return { data: null, error: prepared.error };
  if (!prepared.data.changed) return { data: { changed: false }, error: null };
  if (!config.serviceKey) return { data: null, error: { code: 'AUTH_BACKEND_UNAVAILABLE' } };
  // Created only after a user-scoped RPC verified the actor, target and action.
  const admin = createClient(config.url, config.serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  try {
    await admin.auth.admin.updateUserById(target, {
      ban_duration: action === 'disable' ? '876000h' : 'none',
      app_metadata: { spike_auth_command: prepared.data.commandId },
    });
  } catch {
    // The response may be lost after commit. Read the command instead of guessing/retrying.
  }
  const result = await user.rpc('spike_auth_command_result', { p_command: prepared.data.commandId });
  if (result.error) return { data: null, error: result.error };
  if (result.data.committed) return { data: { changed: result.data.changed as boolean }, error: null };
  return { data: null, error: { code: 'AUTH_COMMAND_FAILED' } };
}
