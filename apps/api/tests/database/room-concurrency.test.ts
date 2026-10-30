import assert from 'node:assert/strict'
import { randomUUID } from 'node:crypto'
import { test } from 'node:test'
import pg from 'pg'
import { readTestEnvironment } from '../../../../scripts/testing/environment.ts'

test('DB exclusion rejects two concurrent overlapping room reservations and permits adjacency', async () => {
  const connectionString = readTestEnvironment().TEST_DATABASE_URL
  const setup = new pg.Client({ connectionString })
  const first = new pg.Client({ connectionString })
  const second = new pg.Client({ connectionString })
  await Promise.all([setup.connect(), first.connect(), second.connect()])
  const session = randomUUID()
  const actor = '00000000-0000-4000-8000-000000000002'
  let pending: Promise<string> | undefined
  try {
    await setup.query(
      'insert into auth.sessions(id,user_id,created_at,updated_at) values($1,$2,now(),now())',
      [session, actor],
    )
    await setup.query(
      "insert into auth.mfa_amr_claims(id,session_id,created_at,updated_at,authentication_method) values($1,$2,now(),now(),'password')",
      [randomUUID(), session],
    )
    for (const client of [setup, first, second]) {
      await client.query("select set_config('request.jwt.claims',$1,false)", [
        JSON.stringify({ sub: actor, session_id: session, role: 'authenticated' }),
      ])
      await client.query("set statement_timeout='8s'")
    }
    const room = (
      await setup.query("select api.create_room('11000000-0000-4000-8000-000000000001',$1) data", [
        `Concurrent ${randomUUID()}`,
      ])
    ).rows[0].data.id
    const classes: string[] = []
    for (let i = 0; i < 2; i++)
      classes.push(
        (
          await setup.query(
            "select api.create_class($1,'10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000011',app_private.business_date(now()),app_private.business_date(now())+10,null) data",
            [`Room ${randomUUID()}`],
          )
        ).rows[0].data.id,
      )
    const insert = `insert into app.class_sessions(class_id,kind,original_day,original_start,starts_at,ends_at,room_id,status)
      values($1,'makeup',app_private.business_date(now())+1,$3::time,
      (app_private.business_date(now())+1+$3::time) at time zone 'Asia/Ho_Chi_Minh',
      (app_private.business_date(now())+1+$4::time) at time zone 'Asia/Ho_Chi_Minh',$2,'scheduled')`
    await first.query('begin')
    await second.query('begin')
    await first.query(insert, [classes[0], room, '13:00', '14:00'])
    const pid = (await second.query('select pg_backend_pid() pid')).rows[0].pid
    pending = second.query(insert, [classes[1], room, '13:30', '14:30']).then(
      () => 'saved',
      (error: { code: string }) => error.code,
    )
    const deadline = Date.now() + 5000
    while (
      !(await setup.query('select cardinality(pg_blocking_pids($1))>0 blocked', [pid])).rows[0]
        .blocked
    ) {
      assert.ok(Date.now() < deadline, 'second request must reach the concurrent exclusion lock')
      await new Promise((resolve) => setTimeout(resolve, 10))
    }
    await first.query('commit')
    assert.equal(await pending, '23P01', 'the losing transaction cannot persist an overlap')
    await second.query('rollback')
    await second.query(insert, [classes[1], room, '14:00', '15:00'])
    assert.equal(
      (await setup.query('select count(*)::int n from app.class_sessions where room_id=$1', [room]))
        .rows[0].n,
      2,
    )
  } finally {
    await first.query('rollback')
    await second.query('rollback')
    if (pending) await pending
    await setup.query('delete from auth.sessions where id=$1', [session])
    await Promise.all([setup.end(), first.end(), second.end()])
  }
})
