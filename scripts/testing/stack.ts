import { execFileSync } from 'node:child_process'
import {
  cpSync,
  existsSync,
  lstatSync,
  mkdirSync,
  readFileSync,
  realpathSync,
  rmSync,
  writeFileSync,
} from 'node:fs'
import { join, resolve, sep } from 'node:path'
import { fileURLToPath } from 'node:url'
import {
  ROOT,
  TEST_WORKDIR,
  TEST_PROJECT,
  TEST_ENV_FILE,
  TEST_WORKER_CONFIG,
  assertTestEnvironment,
} from './environment.ts'

const EXCLUDED = 'studio,imgproxy,postgres-meta,vector,logflare,supavisor,edge-runtime'

function cli(args: string[], capture = false): string {
  try {
    return (
      execFileSync('supabase', [...args, '--workdir', TEST_WORKDIR], {
        cwd: ROOT,
        encoding: 'utf8',
        stdio: capture ? ['ignore', 'pipe', 'inherit'] : 'inherit',
      }) ?? ''
    )
  } catch {
    // Never echo captured stdout: start/status include local database credentials.
    throw new Error(`Supabase ${args.join(' ')} failed; see CLI diagnostics above`)
  }
}

export function testConfig(source: string): string {
  if (!/^project_id = "mledu-dev"$/m.test(source)) throw new Error('Unexpected development project')
  return source
    .replace(/^project_id = "mledu-dev"$/m, `project_id = "${TEST_PROJECT}"`)
    .replace(/\b5432(\d)\b/g, '5532$1')
    .replace(/^inspector_port = 8083$/m, 'inspector_port = 8183')
    .replace(/:5173/g, ':5183')
    .replace(
      /^sql_paths = .*$/m,
      'sql_paths = ["./seeds/00-account.sql", "./seeds/10-catalogs.sql", "./seeds/20-students.sql", "./seeds/30-classes.sql"]',
    )
}

/** Copies only committed test inputs. The development seeds directory is never read. */
export function prepareTestStack(root = ROOT, workdir = TEST_WORKDIR): void {
  const expected = resolve(root, 'tmp/supabase-test')
  if (resolve(workdir) !== expected) throw new Error('Unexpected test work directory')
  mkdirSync(join(workdir, 'supabase'), { recursive: true })
  const base = realpathSync(join(workdir, 'supabase'))
  if (base !== resolve(workdir, 'supabase'))
    throw new Error('Test work directory must not be a symlink')
  for (const [source, target] of [
    ['supabase/migrations', 'migrations'],
    ['supabase/templates', 'templates'],
    ['supabase/tests', 'tests'],
    ['tests/fixtures/database', 'seeds'],
  ]) {
    const destination = resolve(base, target!)
    if (
      !destination.startsWith(base + sep) ||
      (existsSync(destination) && lstatSync(destination).isSymbolicLink())
    ) {
      throw new Error('Refusing to replace a path outside the generated test inputs')
    }
    rmSync(destination, { recursive: true, force: true })
    cpSync(join(root, source!), destination, { recursive: true })
  }
  writeFileSync(
    join(base, 'config.toml'),
    testConfig(readFileSync(join(root, 'supabase/config.toml'), 'utf8')),
  )
}

function assertTestProject(): void {
  const config = readFileSync(join(TEST_WORKDIR, 'supabase/config.toml'), 'utf8')
  if (!/^project_id = "mledu-test"$/m.test(config) || !/^port = 55322$/m.test(config)) {
    throw new Error('Refusing to operate on anything other than the generated test project')
  }
}

function writeEnvironment(): void {
  assertTestProject()
  const output = cli(['status', '-o', 'json'], true)
  const status = JSON.parse(output.slice(output.indexOf('{'))) as Record<string, string>
  const env = {
    projectId: TEST_PROJECT,
    SUPABASE_URL: status.API_URL,
    SUPABASE_PUBLISHABLE_KEY: status.PUBLISHABLE_KEY,
    SUPABASE_SECRET_KEY: status.SECRET_KEY,
    SUPABASE_ANON_KEY: status.ANON_KEY,
    SUPABASE_SERVICE_ROLE_KEY: status.SERVICE_ROLE_KEY,
    TEST_DATABASE_URL: status.DB_URL,
    TEST_MAILPIT_URL: status.MAILPIT_URL ?? status.INBUCKET_URL,
  }
  assertTestEnvironment(env)
  writeFileSync(TEST_ENV_FILE, JSON.stringify(env, null, 2) + '\n', { mode: 0o600 })
  // A separate config directory prevents Wrangler loading the developer's .dev.vars.
  // Generated credentials remain outside source, reports and deploy artifacts.
  const base = readFileSync(join(ROOT, 'apps/api/wrangler.jsonc'), 'utf8')
  const compatibilityDate = /"compatibility_date":\s*"([^"]+)"/.exec(base)?.[1]
  if (!compatibilityDate) throw new Error('Missing Worker compatibility date')
  writeFileSync(
    TEST_WORKER_CONFIG,
    JSON.stringify(
      {
        name: 'mledu-api-test',
        main: join(ROOT, 'apps/api/src/index.ts'),
        compatibility_date: compatibilityDate,
        vars: {
          APP_ENV: 'test',
          APP_VERSION: 'test',
          ALLOWED_ORIGINS: 'http://127.0.0.1:5183',
        },
      },
      null,
      2,
    ) + '\n',
    { mode: 0o600 },
  )
  writeFileSync(
    join(TEST_WORKDIR, '.dev.vars'),
    [
      `SUPABASE_URL=${env.SUPABASE_URL}`,
      `SUPABASE_PUBLISHABLE_KEY=${env.SUPABASE_PUBLISHABLE_KEY}`,
      `SUPABASE_SECRET_KEY=${env.SUPABASE_SECRET_KEY}`,
      '',
    ].join('\n'),
    { mode: 0o600 },
  )
  console.log('Configured mledu-test; development environment files are unchanged.')
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const command = process.argv[2]
  if (command === 'prepare' || command === 'start' || command === 'reset') prepareTestStack()
  if (command !== 'prepare') assertTestProject()
  switch (command) {
    case 'prepare':
      break
    case 'start':
      cli(['start', '-x', EXCLUDED], true)
      writeEnvironment()
      break
    case 'reset':
      cli(['db', 'reset', '--local'])
      writeEnvironment()
      break
    case 'stop':
      cli(['stop'])
      break
    case 'env':
      writeEnvironment()
      break
    case 'db':
      writeEnvironment()
      cli(['test', 'db'])
      break
    case 'types': {
      writeEnvironment()
      const types = cli(['gen', 'types', 'typescript', '--local', '--schema', 'api'], true)
      const target = join(ROOT, 'apps/api/src/generated/database.types.ts')
      writeFileSync(target, types)
      execFileSync(
        process.execPath,
        [join(ROOT, 'node_modules/prettier/bin/prettier.cjs'), '--write', target],
        { stdio: 'inherit' },
      )
      break
    }
    default:
      throw new Error('Expected prepare, start, reset, stop, env, db or types')
  }
}
