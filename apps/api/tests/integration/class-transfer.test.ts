import { beforeAll, expect, it } from 'vitest'
import { api, errorCode, json, signIn, signOut, createReadyAccount } from './support'

let manager: string
let admin: string
const day = (n: number) =>
  new Date(Date.now() + 7 * 3600_000 + n * 86_400_000).toISOString().slice(0, 10)
interface Participation {
  id: string
  joinDate: string
  leaveDate: string | null
  status: string
  rowVersion: number
  effectiveFrom: string | null
  effectiveUntil: string | null
}
interface RecordDto {
  id: string
  classId: string
  deleted: boolean
  deletedAt: string | null
  rowVersion: number
  participations: Participation[]
}
const post = (path: string, body: unknown, token = manager) =>
  api(path, { method: 'POST', body, token })
const read = async (classId: string) =>
  json<RecordDto[]>(
    await api(`/v1/classes/${classId}/students?includeDeleted=true`, { token: manager }),
  )
async function fixture() {
  const studentResponse = await post('/v1/students', {
    fullName: `Enrollment ${crypto.randomUUID()}`,
    parentName: null,
    parentPhones: [],
    studentPhones: [],
    birthDate: null,
    school: null,
    generalNote: null,
  })
  expect(studentResponse.status).toBe(201)
  const student = await json<{ id: string }>(studentResponse)
  const classes = []
  for (const name of ['Source', 'Target']) {
    const response = await post('/v1/classes', {
      name: `${name} ${crypto.randomUUID()}`,
      subjectId: '10000000-0000-4000-8000-000000000001',
      gradeId: '10000000-0000-4000-8000-000000000011',
      startDate: day(-10),
      endDate: day(60),
      note: null,
    })
    expect(response.status).toBe(201)
    classes.push(await json<{ id: string; rowVersion: number }>(response))
  }
  return { student, source: classes[0]!, target: classes[1]! }
}
async function enroll(
  classId: string,
  studentId: string,
  joinDate = day(-2),
  leaveDate: string | null = null,
) {
  const response = await post(`/v1/classes/${classId}/students`, {
    studentId,
    joinDate,
    leaveDate,
    note: null,
  })
  expect(response.status).toBe(201)
  return json<RecordDto>(response)
}
beforeAll(async () => {
  ;[manager, admin] = await Promise.all([signIn('receptionist'), signIn('admin')])
})

it('transfers atomically and reuses the old record when the student returns', async () => {
  const { source, target, student } = await fixture()
  const record = await enroll(source.id, student.id)
  const part = record.participations[0]!
  const response = await post(`/v1/participations/${part.id}/transfer`, {
    targetClassId: target.id,
    leaveDate: day(1),
    joinDate: day(1),
    note: 'Transfer',
    expectedVersion: part.rowVersion,
  })
  expect(response.status).toBe(200)
  expect((await json<RecordDto>(response)).classId).toBe(target.id)
  expect((await read(source.id))[0]!.participations[0]!.leaveDate).toBe(day(1))
  const returned = await enroll(source.id, student.id, day(2))
  expect(returned.id).toBe(record.id)
  expect(returned.participations).toHaveLength(2)
})

it('rolls back the source leave date and version if the destination overlaps', async () => {
  const { source, target, student } = await fixture()
  const record = await enroll(source.id, student.id)
  await enroll(target.id, student.id)
  const before = await read(source.id)
  const targetBefore = await read(target.id)
  const response = await post(`/v1/participations/${record.participations[0]!.id}/transfer`, {
    targetClassId: target.id,
    leaveDate: day(1),
    joinDate: day(1),
    note: null,
    expectedVersion: 1,
  })
  expect(response.status).toBe(409)
  expect(await errorCode(response)).toBe('participation_overlap')
  expect(await read(source.id)).toEqual(before)
  expect(await read(target.id)).toEqual(targetBefore)
})

it('serializes opposite transfers of the same student without a deadlock', async () => {
  const { source, target, student } = await fixture()
  const left = await enroll(source.id, student.id, day(-2), day(1))
  const right = await enroll(target.id, student.id, day(-2), day(1))
  const responses = await Promise.all(
    [
      [left, target.id],
      [right, source.id],
    ].map(([record, classId]) => {
      const part = (record as RecordDto).participations[0]!
      return post(`/v1/participations/${part.id}/transfer`, {
        targetClassId: classId,
        leaveDate: part.leaveDate,
        joinDate: day(2),
        note: null,
        expectedVersion: part.rowVersion,
      })
    }),
  )
  expect(responses.map((r) => r.status)).toEqual([200, 200])
  expect((await read(source.id))[0]!.participations).toHaveLength(2)
  expect((await read(target.id))[0]!.participations).toHaveLength(2)
})

it('only one simultaneous enrollment succeeds and leave dates cannot be rewritten', async () => {
  const { source, student } = await fixture()
  const responses = await Promise.all(
    [1, 2].map(() =>
      post(`/v1/classes/${source.id}/students`, {
        studentId: student.id,
        joinDate: day(-1),
        leaveDate: null,
        note: null,
      }),
    ),
  )
  expect(responses.map((r) => r.status).sort()).toEqual([201, 409])
  const [record] = await read(source.id)
  expect(record!.participations).toHaveLength(1)
  const part = record!.participations[0]!
  const path = `/v1/participations/${part.id}/leave`
  expect((await post(path, { leaveDate: day(2), expectedVersion: 1 })).status).toBe(200)
  const stale = await post(path, { leaveDate: day(3), expectedVersion: 1 })
  expect(await errorCode(stale)).toBe('version_conflict')
  const locked = await post(path, { leaveDate: day(3), expectedVersion: 2 })
  expect(await errorCode(locked)).toBe('participation_dates_locked')
  expect(
    (
      await post(path, {
        leaveDate: day(4),
        joinDate: day(-9),
        status: 'active',
        expectedVersion: 2,
      })
    ).status,
  ).toBe(400)
})

it('deleting and adding again creates a separate record whose time begins after deletion', async () => {
  const { source, student } = await fixture()
  const old = await enroll(source.id, student.id)
  expect(
    (
      await post(`/v1/class-students/${old.id}/delete`, {
        reason: 'Correction',
        expectedVersion: old.rowVersion,
      })
    ).status,
  ).toBe(200)
  const added = await enroll(source.id, student.id, day(0))
  expect(added.id).not.toBe(old.id)
  const records = await read(source.id)
  expect(records).toHaveLength(2)
  const archived = records.find((r) => r.id === old.id)!
  expect(archived.deleted).toBe(true)
  expect(Date.parse(added.participations[0]!.effectiveFrom!)).toBeGreaterThanOrEqual(
    Date.parse(archived.deletedAt!),
  )
  expect(archived.participations[0]!.status).toBe('ended')
})

it('cancels future participation, closes enrollment, and restores a deleted class as closed', async () => {
  const { source, student } = await fixture()
  const record = await enroll(source.id, student.id, day(3))
  const cancelled = await post(`/v1/participations/${record.participations[0]!.id}/cancel`, {
    reason: 'Cancelled',
    expectedVersion: 1,
  })
  expect(cancelled.status).toBe(200)
  expect((await json<RecordDto>(cancelled)).participations[0]!.status).toBe('cancelled')
  expect(
    (await post(`/v1/classes/${source.id}/close`, { reason: 'Holiday', expectedVersion: 1 }))
      .status,
  ).toBe(200)
  const rejected = await post(`/v1/classes/${source.id}/students`, {
    studentId: student.id,
    joinDate: day(4),
    leaveDate: null,
    note: null,
  })
  expect(await errorCode(rejected)).toBe('class_closed')
  expect(
    (await post(`/v1/classes/${source.id}/delete`, { reason: 'Archive', expectedVersion: 2 }))
      .status,
  ).toBe(200)
  const restored = await post(`/v1/classes/${source.id}/restore`, { expectedVersion: 3 })
  expect(restored.status).toBe(200)
  expect((await json(restored)).adminState).toBe('closed')
  expect((await read(source.id))[0]!.participations[0]!.status).toBe('cancelled')
})

it('enforces assignment scope on every read, manager-only enrollment, and revoked sessions', async () => {
  const { source, student } = await fixture()
  const user = await createReadyAccount(admin, 'enrollment-reader')
  const token = user.session.accessToken
  await enroll(source.id, student.id)
  const path = `/v1/classes/${source.id}/students`
  expect((await api(path, { token })).status).toBe(404)
  const assignment = await json<{ id: string; rowVersion: number }>(
    await post(`/v1/classes/${source.id}/assignments`, {
      accountId: user.id,
      role: 'assistant',
      startDate: day(-1),
      endDate: day(50),
      subjectNote: null,
    }),
  )
  expect((await api(path, { token })).status).toBe(200)
  expect(
    (
      await post(
        path,
        { studentId: student.id, joinDate: day(10), leaveDate: null, note: null },
        token,
      )
    ).status,
  ).toBe(403)
  expect(
    (
      await post(`/v1/assignments/${assignment.id}/end`, {
        reason: 'End',
        expectedVersion: assignment.rowVersion,
      })
    ).status,
  ).toBe(200)
  expect((await api(path, { token })).status).toBe(404)
  expect(await json(await api(`/v1/students/${student.id}/classes`, { token }))).toEqual([])
  await signOut(token)
  expect((await api(path, { token })).status).toBe(401)
})
