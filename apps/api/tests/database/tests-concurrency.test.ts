import assert from 'node:assert/strict'
import { randomUUID } from 'node:crypto'
import { test } from 'node:test'
import pg from 'pg'
import { readTestEnvironment } from '../../../../scripts/testing/environment.ts'

// TEST-05 lock interleavings on separate connections: creating a test checks
// the template and the assignment again after waiting for a concurrent change.
const connectionString = readTestEnvironment().TEST_DATABASE_URL
const ADMIN = '00000000-0000-4000-8000-000000000001'
const USER = '00000000-0000-4000-8000-000000000003'
const DIRECT = JSON.stringify({ scaleKind: 'numeric', inputMode: 'direct', maxScore: 10 })

async function connect(actor: string) {
  const client = new pg.Client({ connectionString })
  await client.connect()
  const session = randomUUID()
  await client.query(
    'insert into auth.sessions(id,user_id,created_at,updated_at) values($1,$2,now(),now())',
    [session, actor],
  )
  await client.query(
    "insert into auth.mfa_amr_claims(id,session_id,created_at,updated_at,authentication_method) values($1,$2,now(),now(),'password')",
    [randomUUID(), session],
  )
  await client.query("select set_config('request.jwt.claims',$1,false)", [
    JSON.stringify({ sub: actor, session_id: session, role: 'authenticated' }),
  ])
  await client.query("set statement_timeout = '8s'")
  return client
}

const backendPid = async (client: pg.Client) =>
  (await client.query('select pg_backend_pid() as pid')).rows[0].pid as number

/** pid is read before the waiter is busy: a client runs one query at a time. */
async function waitUntilBlocked(observer: pg.Client, pid: number) {
  const deadline = Date.now() + 5000
  while (
    !(await observer.query('select cardinality(pg_blocking_pids($1)) > 0 as b', [pid])).rows[0].b
  ) {
    assert.ok(Date.now() < deadline, 'the request must wait for the concurrent lock')
    await new Promise((resolve) => setTimeout(resolve, 10))
  }
}

const settle = (query: Promise<unknown>) =>
  query.then(
    () => ({ code: 'ok', message: '' }),
    (error: { code: string; message: string }) => ({ code: error.code, message: error.message }),
  )

async function createClass(client: pg.Client) {
  return (
    await client.query(
      "select (api.create_class($1,'10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000011',app_private.business_date(now())-5,app_private.business_date(now())+30,null)->>'id') as id",
      [`Bài kiểm tra ${randomUUID()}`],
    )
  ).rows[0].id as string
}

test('a test cannot copy a template that is archived while it waits', async () => {
  const [setup, archiving, creating] = await Promise.all([
    connect(ADMIN),
    connect(ADMIN),
    connect(ADMIN),
  ])
  try {
    const classId = await createClass(setup)
    const template = (
      await setup.query('select api.create_test_template($1,null,$2::jsonb) as data', [
        `Mẫu ${randomUUID()}`,
        DIRECT,
      ])
    ).rows[0].data
    await archiving.query('begin')
    await archiving.query("select api.archive_test_template($1,'Ngừng dùng',$2)", [
      template.id,
      template.rowVersion,
    ])
    const pid = await backendPid(creating)
    const pending = settle(
      creating.query(
        "select api.create_test($1,'Đồng thời',app_private.business_date(now()),null,$2::jsonb,$3)",
        [classId, DIRECT, template.currentVersionId],
      ),
    )
    await waitUntilBlocked(setup, pid)
    await archiving.query('commit')
    const result = await pending
    assert.equal(result.code, 'PT409')
    assert.equal(result.message, 'template_unavailable')
    const count = (
      await setup.query('select count(*)::int as n from app.tests where class_id = $1', [classId])
    ).rows[0].n
    assert.equal(count, 0)
  } finally {
    await Promise.all([setup.end(), archiving.end(), creating.end()])
  }
})

test('an assistant whose assignment ends while waiting cannot create a test', async () => {
  const [setup, ending, assistant] = await Promise.all([
    connect(ADMIN),
    connect(ADMIN),
    connect(USER),
  ])
  try {
    const classId = await createClass(setup)
    const assignment = (
      await setup.query(
        "select api.create_class_assignment($1,$2,'assistant',app_private.business_date(now())-1,app_private.business_date(now())+10,null) as data",
        [classId, USER],
      )
    ).rows[0].data
    await ending.query('begin')
    await ending.query("select api.end_class_assignment($1,'Thu hồi',$2)", [
      assignment.id,
      assignment.rowVersion,
    ])
    const pid = await backendPid(assistant)
    const pending = settle(
      assistant.query(
        "select api.create_test($1,'Sau thu hồi',app_private.business_date(now()),null,$2::jsonb,null)",
        [classId, DIRECT],
      ),
    )
    await waitUntilBlocked(setup, pid)
    await ending.query('commit')
    const result = await pending
    assert.equal(result.code, 'PT403')
    const count = (
      await setup.query('select count(*)::int as n from app.tests where class_id = $1', [classId])
    ).rows[0].n
    assert.equal(count, 0)
  } finally {
    await Promise.all([setup.end(), ending.end(), assistant.end()])
  }
})
