// Writes local-only config from `supabase status` for the Worker and the SPA:
//   apps/api/.dev.vars   (ignored by Git) SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY
//   apps/web/.env.local  (ignored by Git) VITE_* public values
// The secret key is not written: GĐ 1 code does not need it. Set SUPABASE_WORKDIR
// to read a Supabase project in another directory.
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
if (!url || !publishableKey) {
  throw new Error('supabase status did not return API_URL and PUBLISHABLE_KEY; is it running?')
}

writeFileSync(
  join(root, 'apps/api/.dev.vars'),
  `SUPABASE_URL=${url}\nSUPABASE_PUBLISHABLE_KEY=${publishableKey}\n`,
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
