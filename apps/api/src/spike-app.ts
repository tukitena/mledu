import { Hono } from 'hono';
import type { Context } from 'hono';
import { createClient } from '@supabase/supabase-js';
import type { SupabaseClient } from '@supabase/supabase-js';
import { applyAuthStatus } from './auth-bridge.ts';

type Env = { Variables: { requestId: string; db: SupabaseClient; identity: unknown } };
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function failure(c: Context<Env>, code: string, status: 400 | 401 | 403 | 404 | 409 | 500 | 501) {
  return c.json({ code, requestId: c.get('requestId') }, status);
}

function databaseFailure(c: Context<Env>, error: { code?: string }) {
  if (error.code?.startsWith('PGRST30')) return failure(c, 'UNAUTHENTICATED', 401);
  if (error.code === '42501') return failure(c, 'ACCESS_DENIED', 403);
  if (error.code === 'P0002') return failure(c, 'NOT_FOUND', 404);
  if (error.code === '22023' || error.code === '22P02') return failure(c, 'INVALID_INPUT', 400);
  if (error.code === '0A000') return failure(c, 'NOT_IMPLEMENTED', 501);
  if (error.code === 'PT409') return failure(c, 'STATE_CONFLICT', 409);
  return failure(c, 'INTERNAL_ERROR', 500);
}

export function createApp(config: { url: string; anonKey: string; serviceKey?: string }) {
  const app = new Hono<Env>();
  app.use('*', async (c, next) => {
    const requestId = crypto.randomUUID();
    c.set('requestId', requestId);
    c.header('x-request-id', requestId);
    c.header('cache-control', 'no-store');
    await next();
  });
  app.onError((_error, c) => failure(c, 'INTERNAL_ERROR', 500));
  app.notFound((c) => failure(c, 'NOT_FOUND', 404));
  app.get('/health', (c) => c.json({ status: 'ok', mode: 'auth-spike' }));

  app.use('/v1/*', async (c, next) => {
    const authorization = c.req.header('authorization');
    if (!authorization || !/^Bearer [a-zA-Z0-9._-]+$/.test(authorization)) {
      return failure(c, 'UNAUTHENTICATED', 401);
    }
    // PostgREST verifies the user JWT; requests do not use an admin client.
    const db = createClient(config.url, config.anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    });
    const { data, error } = await db.rpc('spike_identity');
    if (error) return databaseFailure(c, error);
    c.set('db', db);
    c.set('identity', data);
    await next();
  });
  app.get('/v1/me', (c) => c.json(c.get('identity')));
  for (const [path, rpc] of [['/v1/business', 'spike_business'], ['/v1/reception', 'spike_reception']]) {
    app.get(path, async (c) => {
      const { data, error } = await c.get('db').rpc(rpc);
      return error ? databaseFailure(c, error) : c.json(data);
    });
  }
  app.post('/v1/accounts/:id/:operation', async (c) => {
    const id = c.req.param('id');
    const operation = c.req.param('operation');
    if (!uuid.test(id)) return failure(c, 'INVALID_INPUT', 400);
    if (!['disable', 'enable', 'role'].includes(operation)) return failure(c, 'NOT_FOUND', 404);
    if (operation === 'disable' || operation === 'enable') {
      const { data, error } = await applyAuthStatus(config, c.get('db'), id, operation, c.get('requestId'));
      return error ? databaseFailure(c, error) : c.json(data);
    }
    let role: string | null = null;
    if (operation === 'role') {
      const body = await c.req.json().catch(() => null);
      if (!body || !['User', 'Receptionist'].includes(body.role) || Object.keys(body).some(k => k !== 'role')) {
        return failure(c, 'INVALID_INPUT', 400);
      }
      role = body.role;
    }
    const { data, error } = await c.get('db').rpc('spike_set_account', {
      p_target: id, p_operation: operation === 'role' ? 'set_role' : operation, p_role: role,
    });
    return error ? databaseFailure(c, error) : c.json(data);
  });
  return app;
}
