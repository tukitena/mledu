import assert from 'node:assert/strict'
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, existsSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { test } from 'node:test'
import { assertTestEnvironment } from './environment.ts'
import { prepareTestStack } from './stack.ts'

const env = {
  projectId: 'mledu-test',
  SUPABASE_URL: 'http://127.0.0.1:55321',
  SUPABASE_PUBLISHABLE_KEY: 'fake-public',
  SUPABASE_SECRET_KEY: 'fake-secret',
  SUPABASE_ANON_KEY: 'fake-anon',
  SUPABASE_SERVICE_ROLE_KEY: 'fake-service',
  TEST_DATABASE_URL: 'postgresql://postgres:postgres@127.0.0.1:55322/postgres',
  TEST_MAILPIT_URL: 'http://127.0.0.1:55324',
}

test('test connections reject development and remote endpoints', () => {
  assert.doesNotThrow(() => assertTestEnvironment(env))
  for (const invalid of [
    { projectId: 'mledu-dev' },
    { SUPABASE_URL: 'http://127.0.0.1:54321' },
    { TEST_DATABASE_URL: 'postgresql://postgres:postgres@127.0.0.1:54322/postgres' },
    { TEST_DATABASE_URL: 'postgresql://postgres:postgres@remote.example:55322/postgres' },
    { TEST_MAILPIT_URL: 'http://127.0.0.1:54324' },
    { SUPABASE_SECRET_KEY: '' },
  ])
    assert.throws(() => assertTestEnvironment({ ...env, ...invalid }))
})

test('preparing tests never copies private seeds or changes development env files', () => {
  const root = mkdtempSync(join(tmpdir(), 'mledu-seed-isolation-'))
  assert.ok(
    resolve(root).startsWith(resolve(tmpdir()) + '\\') ||
      resolve(root).startsWith(resolve(tmpdir()) + '/'),
  )
  try {
    for (const directory of [
      'supabase/migrations',
      'supabase/templates',
      'supabase/tests',
      'supabase/seeds',
      'tests/fixtures/database',
      'apps/api',
      'apps/web',
    ]) {
      mkdirSync(join(root, directory), { recursive: true })
    }
    writeFileSync(
      join(root, 'supabase/config.toml'),
      'project_id = "mledu-dev"\n[db]\nport = 54322\n[db.seed]\nsql_paths = ["./seeds/*.sql"]\n',
    )
    writeFileSync(join(root, 'supabase/seeds/00-account.sql'), 'PRIVATE ACCOUNT SENTINEL')
    writeFileSync(join(root, 'supabase/seeds/private.sql'), 'PRIVATE DATA SENTINEL')
    writeFileSync(join(root, 'tests/fixtures/database/00-account.sql'), 'FICTIONAL FIXTURE')
    writeFileSync(join(root, 'apps/api/.dev.vars'), 'DEVELOPMENT API SENTINEL')
    writeFileSync(join(root, 'apps/web/.env.local'), 'DEVELOPMENT WEB SENTINEL')
    const workdir = join(root, 'tmp/supabase-test')
    prepareTestStack(root, workdir)
    assert.equal(
      readFileSync(join(workdir, 'supabase/seeds/00-account.sql'), 'utf8'),
      'FICTIONAL FIXTURE',
    )
    assert.equal(existsSync(join(workdir, 'supabase/seeds/private.sql')), false)
    assert.equal(readFileSync(join(root, 'apps/api/.dev.vars'), 'utf8'), 'DEVELOPMENT API SENTINEL')
    assert.equal(
      readFileSync(join(root, 'apps/web/.env.local'), 'utf8'),
      'DEVELOPMENT WEB SENTINEL',
    )
    // A checkout used by CI has no developer seed directory at all.
    rmSync(join(root, 'supabase/seeds'), { recursive: true })
    prepareTestStack(root, workdir)
    assert.match(
      readFileSync(join(workdir, 'supabase/config.toml'), 'utf8'),
      /project_id = "mledu-test"/,
    )
    assert.throws(() => prepareTestStack(root, join(root, 'supabase')))
  } finally {
    rmSync(root, { recursive: true, force: true })
  }
})
