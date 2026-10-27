// Writes local-only config from `supabase status` for the Worker and the SPA:
//   apps/api/.dev.vars   (ignored by Git) SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY,
//                        SUPABASE_SECRET_KEY (backend only: Auth Admin API, avatars)
//   apps/web/.env.local  (ignored by Git) VITE_* public values, never the secret key
// Set SUPABASE_WORKDIR to read a Supabase project in another directory.
import { execFileSync } from 'node:child_process'
import { writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = fileURLToPath(new URL('../..', import.meta.url))
const args = ['status', '-o', 'json']
if (process.env.SUPABASE_WORKDIR) args.push('--workdir', process.env.SUPABASE_WORKDIR)

const output = execFileSync('supabase', args, {
  cwd: root,
  encoding: 'utf8',
  stdio: ['ignore', 'pipe', 'ignore'],
})
const status = JSON.parse(output.slice(output.indexOf('{')))
const url = status.API_URL
const publishableKey = status.PUBLISHABLE_KEY
const secretKey = status.SECRET_KEY
if (!url || !publishableKey || !secretKey) {
  throw new Error('supabase status did not return API_URL and the API keys; is it running?')
}
// Local stack only: refuse anything that is not a loopback Supabase URL.
if (!/^http:\/\/(127\.0\.0\.1|localhost):\d+$/.test(url)) {
  throw new Error(`refusing to write local config for non-local Supabase URL ${url}`)
}

writeFileSync(
  join(root, 'apps/api/.dev.vars'),
  `SUPABASE_URL=${url}\nSUPABASE_PUBLISHABLE_KEY=${publishableKey}\nSUPABASE_SECRET_KEY=${secretKey}\n`,
)
writeFileSync(
  join(root, 'apps/web/.env.local'),
  [
    'VITE_API_BASE_URL=http://127.0.0.1:8787',
    `VITE_SUPABASE_URL=${url}`,
    `VITE_SUPABASE_PUBLISHABLE_KEY=${publishableKey}`,
    '',
  ].join('\n'),
)
console.log(`Wrote apps/api/.dev.vars and apps/web/.env.local for ${url}`)
