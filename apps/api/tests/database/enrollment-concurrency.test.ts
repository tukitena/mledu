import assert from 'node:assert/strict'
import { randomUUID } from 'node:crypto'
import { test } from 'node:test'
import pg from 'pg'

// Separate PostgreSQL connections are needed to control lock interleavings.
// This test is local-only and keeps fictional business fixtures for history.
const connectionString =
  process.env.TEST_DATABASE_URL ?? 'postgresql://postgres:postgres@127.0.0.1:54322/postgres'
const url = new URL(connectionString)
if (!['localhost', '127.0.0.1'].includes(url.hostname))
  throw new Error('Concurrency tests require a local database')

test('editing a note while its record is deleted cannot deadlock', async () => {
  const setup = new pg.Client({ connectionString })
  const removing = new pg.Client({ connectionString })
  const editing = new pg.Client({ connectionString })
  await Promise.all([setup.connect(), removing.connect(), editing.connect()])
  const session = randomUUID()
  const actor = '00000000-0000-4000-8000-000000000002'
  let pending: Promise<{ code?: string }> | undefined
  try {
    await setup.query(
      'insert into auth.sessions(id,user_id,created_at,updated_at) values($1,$2,now(),now())',
      [session, actor],
    )
    await setup.query(
      "insert into auth.mfa_amr_claims(id,session_id,created_at,updated_at,authentication_method) values($1,$2,now(),now(),'password')",
      [randomUUID(), session],
    )
    for (const client of [setup, removing, editing]) {
      await client.query("select set_config('request.jwt.claims',$1,false)", [
        JSON.stringify({ sub: actor, session_id: session, role: 'authenticated' }),
      ])
      await client.query("set statement_timeout = '8s'")
    }
    const student = (
      await setup.query("select api.create_student($1,null,'{}','{}',null,null,null) as data", [
        `Concurrency ${randomUUID()}`,
      ])
    ).rows[0].data
    const klass = (
      await setup.query(
        "select api.create_class($1,'10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000011',app_private.business_date(now())-1,app_private.business_date(now())+30,null) as data",
        [`Concurrency ${randomUUID()}`],
      )
    ).rows[0].data
    const record = (
      await setup.query(
        'select api.enroll_student($1,$2,app_private.business_date(now())-1) as data',
        [klass.id, student.id],
      )
    ).rows[0].data
    const editPid = (await editing.query('select pg_backend_pid() as pid')).rows[0].pid
    await removing.query('begin')
    await editing.query('begin')
    // Pause the deletion at the exact boundary before it ends participations.
    await removing.query('select app_private.lock_class_student($1,1)', [record.id])
    pending = editing
      .query('select api.set_participation_note($1,$2,1)', [
        record.participations[0].id,
        'Concurrent note',
      ])
      .then(
        () => ({}),
        (error: { code: string }) => ({ code: error.code }),
      )
    const deadline = Date.now() + 5000
    while (true) {
      const blocked = (
        await setup.query('select cardinality(pg_blocking_pids($1)) > 0 as blocked', [editPid])
      ).rows[0].blocked
      if (blocked) break
      assert.ok(Date.now() < deadline, 'note request must reach the controlled lock boundary')
      await new Promise((resolve) => setTimeout(resolve, 10))
    }
    const result = await removing.query(
      "select api.soft_delete_class_student($1,'Concurrent deletion',1) as data",
      [record.id],
    )
    assert.equal(result.rows[0].data.deleted, true)
    await removing.query('commit')
    const note = await pending
    assert.equal(
      note.code,
      'PT409',
      'the stale note gets a business conflict, never a deadlock/server error',
    )
    await editing.query('rollback')
    const rows = (await setup.query('select api.list_class_students($1,true) as data', [klass.id]))
      .rows[0].data
    assert.equal(rows[0].participations[0].note, null)
    assert.equal(rows[0].participations[0].endKind, 'record_deleted')
  } finally {
    await removing.query('rollback')
    await editing.query('rollback')
    if (pending) await pending
    await setup.query('delete from auth.sessions where id=$1', [session])
    await Promise.all([setup.end(), removing.end(), editing.end()])
  }
})
