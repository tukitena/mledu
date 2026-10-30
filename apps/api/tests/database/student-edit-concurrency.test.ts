import assert from 'node:assert/strict'
import { randomUUID } from 'node:crypto'
import { test } from 'node:test'
import pg from 'pg'
import { readTestEnvironment } from '../../../../scripts/testing/environment.ts'

const connectionString = readTestEnvironment().TEST_DATABASE_URL
const manager = '00000000-0000-4000-8000-000000000002'
const editor = '00000000-0000-4000-8000-000000000003'

// Pause real RPCs at their row locks, revoke the assignment, then let them
// proceed. Authorization must use the committed state after the wait.
for (const command of ['profile', 'note', 'leave'] as const) {
  for (const boundary of ['revoked', 'expired'] as const) {
    test(`${command} rechecks assignment ${boundary} while waiting for a business lock`, async () => {
      const setup = new pg.Client({ connectionString })
      const blocking = new pg.Client({ connectionString })
      const editing = new pg.Client({ connectionString })
      const sessions = [randomUUID(), randomUUID()]
      let pending: Promise<{ code?: string; message?: string }> | undefined
      await Promise.all([setup.connect(), blocking.connect(), editing.connect()])
      try {
        for (const [index, actor] of [manager, editor].entries()) {
          await setup.query(
            'insert into auth.sessions(id,user_id,created_at,updated_at) values($1,$2,now(),now())',
            [sessions[index], actor],
          )
          await setup.query(
            "insert into auth.mfa_amr_claims(id,session_id,created_at,updated_at,authentication_method) values($1,$2,now(),now(),'password')",
            [randomUUID(), sessions[index]],
          )
        }
        for (const [client, actor, session] of [
          [setup, manager, sessions[0]],
          [blocking, manager, sessions[0]],
          [editing, editor, sessions[1]],
        ] as const) {
          await client.query("select set_config('request.jwt.claims',$1,false)", [
            JSON.stringify({ sub: actor, session_id: session, role: 'authenticated' }),
          ])
          await client.query("set statement_timeout = '8s'")
        }
        const student = (
          await setup.query('select api.create_student($1) as data', [
            `Permission race ${randomUUID()}`,
          ])
        ).rows[0].data
        const klass = (
          await setup.query(
            "select api.create_class($1,'10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000011',current_date-5,current_date+30) as data",
            [`Permission race ${randomUUID()}`],
          )
        ).rows[0].data
        const record = (
          await setup.query('select api.enroll_student($1,$2,current_date-1) as data', [
            klass.id,
            student.id,
          ])
        ).rows[0].data
        const assignment = (
          await setup.query(
            "select api.create_class_assignment($1,$2,'teacher',current_date-1,current_date+20) as data",
            [klass.id, editor],
          )
        ).rows[0].data
        const pid = (await editing.query('select pg_backend_pid() as pid')).rows[0].pid
        await blocking.query('begin')
        await editing.query('begin')
        if (command === 'profile')
          await blocking.query('select 1 from app.students where id=$1 for update', [student.id])
        else await blocking.query('select app_private.lock_class_student($1,1)', [record.id])

        const query =
          command === 'profile'
            ? editing.query(
                "select api.update_student($1,$2,null,'{}','{}',null,'Must not save',null,1)",
                [student.id, student.fullName],
              )
            : command === 'note'
              ? editing.query("select api.set_participation_note($1,'Must not save',1)", [
                  record.participations[0].id,
                ])
              : editing.query('select api.set_participation_leave_date($1,current_date+1,1)', [
                  record.participations[0].id,
                ])
        pending = query.then(
          () => ({}),
          (error: { code: string; message: string }) => ({
            code: error.code,
            message: error.message,
          }),
        )
        const deadline = Date.now() + 5000
        while (
          !(await setup.query('select cardinality(pg_blocking_pids($1)) > 0 as blocked', [pid]))
            .rows[0].blocked
        ) {
          assert.ok(Date.now() < deadline, 'edit must reach the controlled lock boundary')
          await new Promise((resolve) => setTimeout(resolve, 10))
        }
        if (boundary === 'revoked') {
          await setup.query("select api.end_class_assignment($1,'Revoke during write',1)", [
            assignment.id,
          ])
        } else {
          // Move the fixture's precise assignment cutoff just ahead of wall time.
          // The edit transaction began before this cutoff: now() stays old, so
          // only a check at the actual write time can reject it after waiting.
          const cutoff = (
            await setup.query("select clock_timestamp() + interval '100 milliseconds' as cutoff")
          ).rows[0].cutoff
          await setup.query(
            `update app.class_assignments
          set ended_at=$2, end_kind='ended_early', end_reason='Timed boundary', ended_by=$3,
              effective_period=app_private.dated_period(start_date,end_date,$2)
          where id=$1`,
            [assignment.id, cutoff, manager],
          )
          while (
            !(await setup.query('select clock_timestamp() >= $1::timestamptz as expired', [cutoff]))
              .rows[0].expired
          ) {
            await new Promise((resolve) => setTimeout(resolve, 10))
          }
        }
        await blocking.query('commit')
        const outcome = await pending
        assert.equal(outcome.code, 'PT403', `${boundary} assignment cannot authorize queued writes`)
        assert.equal(outcome.message, 'forbidden')
        await editing.query('rollback')
        const after = (await setup.query('select api.get_student($1) as data', [student.id]))
          .rows[0].data
        assert.equal(after.rowVersion, 1)
        assert.equal(after.school, null)
        const current = (
          await setup.query('select api.list_class_students($1) as data', [klass.id])
        ).rows[0].data[0].participations[0]
        assert.equal(current.rowVersion, 1)
        assert.equal(current.note, null)
        assert.equal(current.leaveDate, null)
        assert.equal(
          (
            await setup.query(
              "select count(*)::int as n from app.audit_events where actor_id=$1 and entity_refs->>'student_id'=$2",
              [editor, student.id],
            )
          ).rows[0].n,
          0,
        )
      } finally {
        await blocking.query('rollback')
        await editing.query('rollback')
        if (pending) await pending
        await setup.query('delete from auth.sessions where id=any($1::uuid[])', [sessions])
        await Promise.all([setup.end(), blocking.end(), editing.end()])
      }
    })
  }
}
