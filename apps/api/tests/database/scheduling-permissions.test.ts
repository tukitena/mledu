import assert from 'node:assert/strict'
import { randomUUID } from 'node:crypto'
import { test } from 'node:test'
import pg from 'pg'
import { readTestEnvironment } from '../../../../scripts/testing/environment.ts'

for (const command of ['schedule', 'attendance'] as const)
  for (const boundary of ['revoked', 'expired'] as const) {
    test(`${command} rechecks assignment ${boundary} after waiting for the class lock`, async () => {
      const connectionString = readTestEnvironment().TEST_DATABASE_URL
      const setup = new pg.Client({ connectionString }),
        blocking = new pg.Client({ connectionString }),
        editing = new pg.Client({ connectionString })
      await Promise.all([setup.connect(), blocking.connect(), editing.connect()])
      const actors = [
        '00000000-0000-4000-8000-000000000002',
        '00000000-0000-4000-8000-000000000003',
      ]
      const sessions = [randomUUID(), randomUUID()]
      let pending: Promise<string> | undefined
      try {
        for (const [i, actor] of actors.entries()) {
          await setup.query(
            'insert into auth.sessions(id,user_id,created_at,updated_at) values($1,$2,now(),now())',
            [sessions[i], actor],
          )
          await setup.query(
            "insert into auth.mfa_amr_claims(id,session_id,created_at,updated_at,authentication_method) values($1,$2,now(),now(),'password')",
            [randomUUID(), sessions[i]],
          )
        }
        for (const [client, index] of [
          [setup, 0],
          [blocking, 0],
          [editing, 1],
        ] as const) {
          await client.query("select set_config('request.jwt.claims',$1,false)", [
            JSON.stringify({
              sub: actors[index],
              session_id: sessions[index],
              role: 'authenticated',
            }),
          ])
          await client.query("set statement_timeout='8s'")
        }
        const klass = (
          await setup.query(
            "select api.create_class($1,'10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000011',app_private.business_date(now())-5,app_private.business_date(now())+10) data",
            [`Schedule permission ${randomUUID()}`],
          )
        ).rows[0].data.id
        const assignment = (
          await setup.query(
            "select api.create_class_assignment($1,$2,'teacher',app_private.business_date(now())-2,app_private.business_date(now())+5) data",
            [klass, actors[1]],
          )
        ).rows[0].data.id
        const session = (
          await setup.query(
            "insert into app.class_sessions(class_id,kind,original_day,original_start,starts_at,ends_at,status) values($1,'makeup',app_private.business_date(now())-1,'09:00',app_private.day_start(app_private.business_date(now())-1)+interval '9 hours',app_private.day_start(app_private.business_date(now())-1)+interval '10 hours','scheduled') returning id",
            [klass],
          )
        ).rows[0].id
        const fingerprint = (
          await setup.query("select api.get_attendance($1)->>'fingerprint' fingerprint", [session])
        ).rows[0].fingerprint
        const pid = (await editing.query('select pg_backend_pid() pid')).rows[0].pid
        await blocking.query('begin')
        await blocking.query('select 1 from app.classes where id=$1 for update', [klass])
        await editing.query('begin')
        const query =
          command === 'schedule'
            ? editing.query(
                "select api.preview_schedule_change($1,jsonb_build_object('op','makeup','date',app_private.business_date(now())+1,'startTime','09:00','endTime','10:00','roomId',null))",
                [klass],
              )
            : editing.query("select api.save_attendance($1,'[]',$2)", [session, fingerprint])
        pending = query.then(
          () => 'saved',
          (error: { code: string }) => error.code,
        )
        const deadline = Date.now() + 5000
        while (
          !(await setup.query('select cardinality(pg_blocking_pids($1))>0 blocked', [pid])).rows[0]
            .blocked
        ) {
          assert.ok(Date.now() < deadline, 'command must reach the controlled class lock')
          await new Promise((resolve) => setTimeout(resolve, 10))
        }
        // Fixture controls the exact cutoff without waiting behind the command's scheduling mutex.
        const cutoff = (
          await setup.query(
            `select clock_timestamp()+interval '${boundary === 'expired' ? '80 milliseconds' : '0 milliseconds'}' cutoff`,
          )
        ).rows[0].cutoff
        await setup.query(
          "update app.class_assignments set ended_at=$2,end_kind='ended_early',effective_period=app_private.dated_period(start_date,end_date,$2) where id=$1",
          [assignment, cutoff],
        )
        while (
          !(await setup.query('select clock_timestamp()>$1::timestamptz expired', [cutoff])).rows[0]
            .expired
        )
          await new Promise((resolve) => setTimeout(resolve, 10))
        await blocking.query('commit')
        assert.equal(await pending, 'PT403', 'permission must be current after the wait')
        await editing.query('rollback')
      } finally {
        await blocking.query('rollback')
        await editing.query('rollback')
        if (pending) await pending
        await setup.query('delete from auth.sessions where id=any($1::uuid[])', [sessions])
        await Promise.all([setup.end(), blocking.end(), editing.end()])
      }
    })
  }
