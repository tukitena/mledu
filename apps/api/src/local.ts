import { serve } from '@hono/node-server';
import { localConfig } from '../../../scripts/auth-spike/config.ts';
import { createApp } from './spike-app.ts';

const app = createApp(localConfig());
serve({ fetch: app.fetch, hostname: '127.0.0.1', port: 8787 });
console.log('MLedu Auth spike: http://127.0.0.1:8787/health (local only)');
