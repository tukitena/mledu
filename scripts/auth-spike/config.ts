// Connection settings for the GĐ 0 Auth spike (apps/api/src/local.ts and
// apps/api/tests). Read from `supabase status` of this repository's local stack;
// MLEDU_SPIKE_* environment variables override each value. Local only.
import { execFileSync } from 'node:child_process';

export type SpikeConfig = { url: string; anonKey: string; serviceKey: string; databaseUrl: string };

let cached: SpikeConfig | undefined;

export function localConfig(): SpikeConfig {
  if (cached) return cached;
  const output = execFileSync('supabase', ['status', '-o', 'json'], {
    cwd: new URL('../..', import.meta.url),
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'ignore'],
  });
  const status = JSON.parse(output.slice(output.indexOf('{'))) as Record<string, string | undefined>;
  const value = (name: string, fallback: string | undefined) => {
    const resolved = process.env[`MLEDU_SPIKE_${name}`] ?? fallback;
    if (!resolved) throw new Error(`Spike config is missing ${name}; is Supabase local running?`);
    return resolved;
  };
  const config = {
    url: value('URL', status.API_URL),
    anonKey: value('ANON_KEY', status.ANON_KEY),
    serviceKey: value('SERVICE_KEY', status.SERVICE_ROLE_KEY),
    databaseUrl: value('DATABASE_URL', status.DB_URL),
  };
  const host = new URL(config.databaseUrl).hostname;
  if (!['127.0.0.1', 'localhost', '::1'].includes(host)) {
    throw new Error('The Auth spike only runs against a local database.');
  }
  cached = config;
  return config;
}
