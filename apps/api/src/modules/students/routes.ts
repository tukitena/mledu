import {
  CreateStudentRequest,
  ListStudentsQuery,
  RestoreStudentRequest,
  SoftDeleteStudentRequest,
  Student,
  StudentPage,
  UpdateStudentRequest,
  type StudentFields,
} from '@mledu/contracts/students'
import { Hono } from 'hono'
import { z } from 'zod'
import type { AppEnv } from '../../env'
import { rpcResult } from '../../lib/rpc'
import { nullable } from '../../lib/supabase'
import { expectShape, parseJson, parseQuery, uuidParam } from '../../lib/validation'
import { requireSession } from '../../middleware/session'

/**
 * Student master records (STU-04/01/02). Normalization, duplicate rules and
 * permissions are enforced by the RPCs; this layer only checks shapes.
 */
const fieldArgs = (body: StudentFields) => ({
  p_full_name: body.fullName,
  p_parent_name: nullable(body.parentName),
  p_parent_phones: body.parentPhones,
  p_student_phones: body.studentPhones,
  p_birth_date: nullable(body.birthDate),
  p_school: nullable(body.school),
  p_general_note: nullable(body.generalNote),
})

export const studentRoutes = new Hono<AppEnv>()
  .use(requireSession())

  .get('/', async (c) => {
    const query = parseQuery(c, ListStudentsQuery)
    const page = rpcResult(
      z.object({ total: z.number(), items: z.array(z.unknown()) }),
      await c.get('db').rpc('list_students', {
        p_search: nullable(query.search || null),
        p_status: query.status,
        p_limit: query.pageSize,
        p_offset: (query.page - 1) * query.pageSize,
      }),
    )
    return c.json(expectShape(StudentPage, { ...page, page: query.page, pageSize: query.pageSize }))
  })

  .get('/:id', async (c) =>
    c.json(rpcResult(Student, await c.get('db').rpc('get_student', { p_id: uuidParam(c, 'id') }))),
  )

  .post('/', async (c) => {
    const body = await parseJson(c, CreateStudentRequest)
    const student = rpcResult(Student, await c.get('db').rpc('create_student', fieldArgs(body)))
    return c.json(student, 201)
  })

  .put('/:id', async (c) => {
    const { expectedVersion, ...fields } = await parseJson(c, UpdateStudentRequest)
    return c.json(
      rpcResult(
        Student,
        await c.get('db').rpc('update_student', {
          p_id: uuidParam(c, 'id'),
          ...fieldArgs(fields),
          p_expected_version: expectedVersion,
        }),
      ),
    )
  })

  // STU-01
  .post('/:id/delete', async (c) => {
    const body = await parseJson(c, SoftDeleteStudentRequest)
    return c.json(
      rpcResult(
        Student,
        await c.get('db').rpc('soft_delete_student', {
          p_id: uuidParam(c, 'id'),
          p_reason: body.reason,
          p_expected_version: body.expectedVersion,
        }),
      ),
    )
  })

  // STU-02
  .post('/:id/restore', async (c) => {
    const { expectedVersion, ...fields } = await parseJson(c, RestoreStudentRequest)
    return c.json(
      rpcResult(
        Student,
        await c.get('db').rpc('restore_student', {
          p_id: uuidParam(c, 'id'),
          ...fieldArgs(fields),
          p_expected_version: expectedVersion,
        }),
      ),
    )
  })
