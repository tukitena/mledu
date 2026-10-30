import { beforeAll, expect, it } from 'vitest'
import { api, json, signIn } from './support'
import type { ClassSchedule, SchedulePreview } from '@mledu/contracts/scheduling'

let manager: string
let admin: string
let classId: string
const day = (n: number) =>
  new Date(Date.now() + 7 * 3600_000 + n * 86400_000).toISOString().slice(0, 10)
beforeAll(async () => {
  ;[manager, admin] = await Promise.all([signIn('receptionist'), signIn('admin')])
  const res = await api('/v1/classes', {
    method: 'POST',
    token: manager,
    body: {
      name: `Schedule ${crypto.randomUUID()}`,
      subjectId: '10000000-0000-4000-8000-000000000001',
      gradeId: '10000000-0000-4000-8000-000000000011',
      startDate: day(-1),
      endDate: day(20),
      note: null,
    },
  })
  expect(res.status).toBe(201)
  classId = (await json<{ id: string }>(res)).id
})
it('previews and confirms a schedule through the Worker without persisting the preview', async () => {
  const change = { op: 'makeup', date: day(1), startTime: '09:00', endTime: '10:00', roomId: null }
  const path = `/v1/classes/${classId}/schedule`
  const previewRes = await api(`${path}/preview`, { method: 'POST', token: manager, body: change })
  expect(previewRes.status).toBe(200)
  const preview = await json<SchedulePreview>(previewRes)
  expect(preview.sessions).toHaveLength(1)
  expect((await json<ClassSchedule>(await api(path, { token: manager }))).sessions).toHaveLength(0)
  const body = { change, token: preview.token }
  expect((await api(path, { method: 'POST', token: manager, body })).status).toBe(200)
  expect((await api(path, { method: 'POST', token: manager, body })).status).toBe(409)
  const schedule = await json<ClassSchedule>(await api(path, { token: manager }))
  expect(schedule.sessions).toHaveLength(1)
  const attendance = await api(`/v1/sessions/${schedule.sessions[0]!.id}/attendance`, {
    token: manager,
  })
  expect(attendance.status).toBe(200)
  const data = await json<{ fingerprint: string }>(attendance)
  expect(
    (
      await api(`/v1/sessions/${schedule.sessions[0]!.id}/attendance`, {
        method: 'PUT',
        token: manager,
        body: { fingerprint: data.fingerprint, students: [] },
      })
    ).status,
  ).toBe(409)
})
it('rejects malformed times, unexpected fields, missing confirmation and unprivileged holidays', async () => {
  const path = `/v1/classes/${classId}/schedule`
  expect(
    (
      await api(`${path}/preview`, {
        method: 'POST',
        token: manager,
        body: { op: 'makeup', date: day(1), startTime: '25:00', endTime: '26:00', roomId: null },
      })
    ).status,
  ).toBe(400)
  expect(
    (
      await api(path, {
        method: 'POST',
        token: manager,
        body: { change: { op: 'weekly', appliesOn: day(1), slots: [] } },
      })
    ).status,
  ).toBe(400)
  expect(
    (
      await api('/v1/holidays/preview', {
        method: 'POST',
        token: manager,
        body: { op: 'holiday', date: day(1), name: 'Lễ' },
      })
    ).status,
  ).toBe(403)
  expect(
    (
      await api('/v1/holidays/preview', {
        method: 'POST',
        token: admin,
        body: { op: 'holiday', date: day(2), name: 'Lễ' },
      })
    ).status,
  ).toBe(200)
  expect((await api(path)).status).toBe(401)
})
