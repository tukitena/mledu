import {
  AssignableAccount,
  Assignment,
  ClassDetail,
  ClassPage,
  ClassSummary,
  CreateAssignmentRequest,
  CreateClassRequest,
  EndAssignmentRequest,
  ListClassesQuery,
  UpdateAssignmentRequest,
  UpdateClassRequest,
  type ClassFields,
} from '@mledu/contracts/classes'
import { Hono } from 'hono'
import { z } from 'zod'
import type { AppEnv } from '../../env'
import { rpcResult } from '../../lib/rpc'
import { nullable } from '../../lib/supabase'
import { expectShape, parseJson, parseQuery, uuidParam } from '../../lib/validation'
import { requireSession } from '../../middleware/session'

/**
 * Classes (CLASS-03) and assignments (CLASS-01/02). The RPCs check the caller
 * on every request: managers see everything, a User only classes in which an
 * assignment is in effect now.
 */
const classArgs = (body: ClassFields) => ({
  p_name: body.name,
  p_subject_id: body.subjectId,
  p_grade_id: body.gradeId,
  p_start_date: body.startDate,
  p_end_date: body.endDate,
  p_note: nullable(body.note),
})

export const classRoutes = new Hono<AppEnv>()
  .use(requireSession())

  .get('/', async (c) => {
    const query = parseQuery(c, ListClassesQuery)
    const page = rpcResult(
      z.object({ total: z.number(), items: z.array(z.unknown()) }),
      await c.get('db').rpc('list_classes', {
        p_search: nullable(query.search || null),
        p_deleted: query.deleted,
        p_limit: query.pageSize,
        p_offset: (query.page - 1) * query.pageSize,
      }),
    )
    return c.json(expectShape(ClassPage, { ...page, page: query.page, pageSize: query.pageSize }))
  })

  .get('/:id', async (c) =>
    c.json(
      rpcResult(ClassDetail, await c.get('db').rpc('get_class', { p_id: uuidParam(c, 'id') })),
    ),
  )

  .post('/', async (c) => {
    const body = await parseJson(c, CreateClassRequest)
    const created = rpcResult(ClassSummary, await c.get('db').rpc('create_class', classArgs(body)))
    return c.json(created, 201)
  })

  .put('/:id', async (c) => {
    const { expectedVersion, ...fields } = await parseJson(c, UpdateClassRequest)
    return c.json(
      rpcResult(
        ClassSummary,
        await c.get('db').rpc('update_class', {
          p_id: uuidParam(c, 'id'),
          ...classArgs(fields),
          p_expected_version: expectedVersion,
        }),
      ),
    )
  })

  .get('/:id/assignments', async (c) =>
    c.json(
      rpcResult(
        z.array(Assignment),
        await c.get('db').rpc('list_class_assignments', { p_class_id: uuidParam(c, 'id') }),
      ),
    ),
  )

  .post('/:id/assignments', async (c) => {
    const body = await parseJson(c, CreateAssignmentRequest)
    const assignment = rpcResult(
      Assignment,
      await c.get('db').rpc('create_class_assignment', {
        p_class_id: uuidParam(c, 'id'),
        p_account_id: body.accountId,
        p_role: body.role,
        p_start_date: body.startDate,
        p_end_date: body.endDate,
        p_subject_note: nullable(body.subjectNote),
      }),
    )
    return c.json(assignment, 201)
  })

export const assignmentRoutes = new Hono<AppEnv>()
  .use(requireSession())

  .get('/assignable-accounts', async (c) =>
    c.json(
      rpcResult(z.array(AssignableAccount), await c.get('db').rpc('list_assignable_accounts')),
    ),
  )

  .put('/:id', async (c) => {
    const body = await parseJson(c, UpdateAssignmentRequest)
    return c.json(
      rpcResult(
        Assignment,
        await c.get('db').rpc('update_class_assignment', {
          p_id: uuidParam(c, 'id'),
          p_role: body.role,
          p_start_date: body.startDate,
          p_end_date: body.endDate,
          p_subject_note: nullable(body.subjectNote),
          p_expected_version: body.expectedVersion,
        }),
      ),
    )
  })

  .post('/:id/end', async (c) => {
    const body = await parseJson(c, EndAssignmentRequest)
    return c.json(
      rpcResult(
        Assignment,
        await c.get('db').rpc('end_class_assignment', {
          p_id: uuidParam(c, 'id'),
          p_reason: body.reason,
          p_expected_version: body.expectedVersion,
        }),
      ),
    )
  })
