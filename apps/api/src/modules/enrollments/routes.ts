import { Hono } from 'hono'
import { z } from 'zod'
import { ClassSummary } from '@mledu/contracts/classes'
import {
  ClassStudent,
  EnrollStudentRequest,
  ListClassStudentsQuery,
  SetLeaveDateRequest,
  SetParticipationNoteRequest,
  ReasonVersionRequest,
  TransferStudentRequest,
  VersionRequest,
  StudentDeleteImpact,
  ClassLifecycleImpact,
} from '@mledu/contracts/enrollments'
import type { AppEnv } from '../../env'
import { rpcResult } from '../../lib/rpc'
import { nullable } from '../../lib/supabase'
import { parseJson, parseQuery, uuidParam } from '../../lib/validation'
import { requireSession } from '../../middleware/session'

/** Every command is one RPC; permissions, versions and audit live in that transaction. */
export const enrollmentClassRoutes = new Hono<AppEnv>()
  .use(requireSession())
  .get('/:id/students', async (c) => {
    const query = parseQuery(c, ListClassStudentsQuery)
    return c.json(
      rpcResult(
        z.array(ClassStudent),
        await c.get('db').rpc('list_class_students', {
          p_class_id: uuidParam(c, 'id'),
          p_include_deleted: query.includeDeleted,
        }),
      ),
    )
  })
  .post('/:id/students', async (c) => {
    const body = await parseJson(c, EnrollStudentRequest)
    return c.json(
      rpcResult(
        ClassStudent,
        await c.get('db').rpc('enroll_student', {
          p_class_id: uuidParam(c, 'id'),
          p_student_id: body.studentId,
          p_join_date: body.joinDate,
          p_leave_date: nullable(body.leaveDate),
          p_note: nullable(body.note),
        }),
      ),
      201,
    )
  })
  .get('/:id/lifecycle-impact', async (c) =>
    c.json(
      rpcResult(
        ClassLifecycleImpact,
        await c.get('db').rpc('class_lifecycle_impact', { p_id: uuidParam(c, 'id') }),
      ),
    ),
  )

for (const [path, rpc] of [
  ['close', 'close_class'],
  ['delete', 'soft_delete_class'],
] as const) {
  enrollmentClassRoutes.post(`/:id/${path}`, async (c) => {
    const body = await parseJson(c, ReasonVersionRequest)
    return c.json(
      rpcResult(
        ClassSummary,
        await c.get('db').rpc(rpc, {
          p_id: uuidParam(c, 'id'),
          p_reason: body.reason,
          p_expected_version: body.expectedVersion,
        }),
      ),
    )
  })
}
for (const [path, rpc] of [
  ['reopen', 'reopen_class'],
  ['restore', 'restore_class'],
] as const) {
  enrollmentClassRoutes.post(`/:id/${path}`, async (c) => {
    const body = await parseJson(c, VersionRequest)
    return c.json(
      rpcResult(
        ClassSummary,
        await c.get('db').rpc(rpc, {
          p_id: uuidParam(c, 'id'),
          p_expected_version: body.expectedVersion,
        }),
      ),
    )
  })
}

export const enrollmentStudentRoutes = new Hono<AppEnv>()
  .use(requireSession())
  .get('/:id/classes', async (c) =>
    c.json(
      rpcResult(
        z.array(ClassStudent),
        await c.get('db').rpc('list_student_classes', { p_student_id: uuidParam(c, 'id') }),
      ),
    ),
  )
  .get('/:id/delete-impact', async (c) =>
    c.json(
      rpcResult(
        StudentDeleteImpact,
        await c.get('db').rpc('student_delete_impact', { p_id: uuidParam(c, 'id') }),
      ),
    ),
  )

export const classStudentRoutes = new Hono<AppEnv>()
  .use(requireSession())
  .post('/:id/delete', async (c) => {
    const body = await parseJson(c, ReasonVersionRequest)
    return c.json(
      rpcResult(
        ClassStudent,
        await c.get('db').rpc('soft_delete_class_student', {
          p_id: uuidParam(c, 'id'),
          p_reason: body.reason,
          p_expected_version: body.expectedVersion,
        }),
      ),
    )
  })

export const participationRoutes = new Hono<AppEnv>()
  .use(requireSession())
  .post('/:id/leave', async (c) => {
    const body = await parseJson(c, SetLeaveDateRequest)
    return c.json(
      rpcResult(
        ClassStudent,
        await c.get('db').rpc('set_participation_leave_date', {
          p_id: uuidParam(c, 'id'),
          p_leave_date: body.leaveDate,
          p_expected_version: body.expectedVersion,
        }),
      ),
    )
  })
  .put('/:id/note', async (c) => {
    const body = await parseJson(c, SetParticipationNoteRequest)
    return c.json(
      rpcResult(
        ClassStudent,
        await c.get('db').rpc('set_participation_note', {
          p_id: uuidParam(c, 'id'),
          p_note: nullable(body.note),
          p_expected_version: body.expectedVersion,
        }),
      ),
    )
  })
  .post('/:id/cancel', async (c) => {
    const body = await parseJson(c, ReasonVersionRequest)
    return c.json(
      rpcResult(
        ClassStudent,
        await c.get('db').rpc('cancel_participation', {
          p_id: uuidParam(c, 'id'),
          p_reason: body.reason,
          p_expected_version: body.expectedVersion,
        }),
      ),
    )
  })
  .post('/:id/transfer', async (c) => {
    const body = await parseJson(c, TransferStudentRequest)
    return c.json(
      rpcResult(
        ClassStudent,
        await c.get('db').rpc('transfer_student', {
          p_participation_id: uuidParam(c, 'id'),
          p_target_class_id: body.targetClassId,
          p_leave_date: nullable(body.leaveDate),
          p_join_date: body.joinDate,
          p_note: nullable(body.note),
          p_expected_version: body.expectedVersion,
        }),
      ),
    )
  })
