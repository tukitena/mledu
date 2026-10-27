// Connection settings for the GĐ 0 Auth spike (apps/api/src/local.ts and
// apps/api/tests). Uses only the isolated test stack, never the developer's DB.
import { readTestEnvironment } from '../testing/environment.ts';

export type SpikeConfig = { url: string; anonKey: string; serviceKey: string; databaseUrl: string };

let cached: SpikeConfig | undefined;

export function localConfig(): SpikeConfig {
  if (cached) return cached;
  const env = readTestEnvironment();
  const config = {
    url: env.SUPABASE_URL,
    anonKey: env.SUPABASE_ANON_KEY,
    serviceKey: env.SUPABASE_SERVICE_ROLE_KEY,
    databaseUrl: env.TEST_DATABASE_URL,
  };
  const host = new URL(config.databaseUrl).hostname;
  if (!['127.0.0.1', 'localhost', '::1'].includes(host)) {
    throw new Error('The Auth spike only runs against a local database.');
  }
  cached = config;
  return config;
}
