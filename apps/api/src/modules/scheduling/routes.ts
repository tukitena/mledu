import {
  ClassSchedule,
  ConfirmScheduleChange,
  ScheduleChange,
  SchedulePreview,
} from '@mledu/contracts/scheduling'
import { Attendance, SaveAttendance } from '@mledu/contracts/attendance'
import { Hono } from 'hono'
import type { AppEnv } from '../../env'
import { rpcResult } from '../../lib/rpc'
import { nullable } from '../../lib/supabase'
import { parseJson, uuidParam } from '../../lib/validation'
import { requireSession } from '../../middleware/session'
import { AppError } from '../../lib/errors'

export const schedulingClassRoutes = new Hono<AppEnv>()
  .use(requireSession())
  .get('/:id/schedule', async (c) =>
    c.json(
      rpcResult(
        ClassSchedule,
        await c.get('db').rpc('get_class_schedule', { p_class_id: uuidParam(c, 'id') }),
      ),
    ),
  )
  .post('/:id/schedule/preview', async (c) => {
    const change = await parseJson(c, ScheduleChange)
    if (change.op === 'holiday' || change.op === 'remove_holiday')
      throw new AppError(400, 'validation_failed', 'validation_failed')
    return c.json(
      rpcResult(
        SchedulePreview,
        await c
          .get('db')
          .rpc('preview_schedule_change', { p_class_id: uuidParam(c, 'id'), p_change: change }),
      ),
    )
  })
  .post('/:id/schedule', async (c) => {
    const body = await parseJson(c, ConfirmScheduleChange)
    if (body.change.op === 'holiday' || body.change.op === 'remove_holiday')
      throw new AppError(400, 'validation_failed', 'validation_failed')
    return c.json(
      rpcResult(
        SchedulePreview,
        await c.get('db').rpc('apply_schedule_change', {
          p_class_id: uuidParam(c, 'id'),
          p_change: body.change,
          p_token: body.token,
        }),
      ),
    )
  })

export const holidayRoutes = new Hono<AppEnv>()
  .use(requireSession())
  .post('/preview', async (c) => {
    const change = await parseJson(c, ScheduleChange)
    if (change.op !== 'holiday' && change.op !== 'remove_holiday')
      throw new AppError(400, 'validation_failed', 'validation_failed')
    return c.json(
      rpcResult(
        SchedulePreview,
        await c
          .get('db')
          .rpc('preview_schedule_change', { p_class_id: nullable<string>(null), p_change: change }),
      ),
    )
  })
  .post('/', async (c) => {
    const body = await parseJson(c, ConfirmScheduleChange)
    if (body.change.op !== 'holiday' && body.change.op !== 'remove_holiday')
      throw new AppError(400, 'validation_failed', 'validation_failed')
    return c.json(
      rpcResult(
        SchedulePreview,
        await c.get('db').rpc('apply_schedule_change', {
          p_class_id: nullable<string>(null),
          p_change: body.change,
          p_token: body.token,
        }),
      ),
    )
  })

export const attendanceRoutes = new Hono<AppEnv>()
  .use(requireSession())
  .get('/:id/attendance', async (c) =>
    c.json(
      rpcResult(
        Attendance,
        await c.get('db').rpc('get_attendance', { p_session_id: uuidParam(c, 'id') }),
      ),
    ),
  )
  .put('/:id/attendance', async (c) => {
    const body = await parseJson(c, SaveAttendance)
    return c.json(
      rpcResult(
        Attendance,
        await c.get('db').rpc('save_attendance', {
          p_session_id: uuidParam(c, 'id'),
          p_students: body.students,
          p_fingerprint: body.fingerprint,
        }),
      ),
    )
  })
