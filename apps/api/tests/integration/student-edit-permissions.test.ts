import { beforeAll, expect, it } from 'vitest'
import { Student } from '@mledu/contracts/students'
import { ClassStudent } from '@mledu/contracts/enrollments'
import { api, createReadyAccount, errorCode, json, signIn, signOut } from './support'

let manager: string
const day = (n: number) =>
  new Date(Date.now() + 7 * 3600_000 + n * 86_400_000).toISOString().slice(0, 10)
const fields = () => ({
  fullName: `Shared ${crypto.randomUUID()}`,
  parentName: null,
  parentPhones: [],
  studentPhones: [],
  birthDate: null,
  school: null,
  generalNote: null,
})
beforeAll(async () => {
  manager = await signIn('admin')
})

for (const role of ['teacher', 'assistant'] as const) {
  it(`${role} edits shared profile and own participation only; old tokens lose revoked rights`, async () => {
    const account = await createReadyAccount(manager, `student-editor-${role}`)
    const token = account.session.accessToken
    const post = (path: string, body: unknown, auth = manager) =>
      api(path, { method: 'POST', token: auth, body })
    const original = fields()
    const student = Student.parse(await json(await post('/v1/students', original)))
    const classes: { id: string }[] = []
    const records: ClassStudent[] = []
    for (const label of ['assigned', 'outside']) {
      const klass = await json<{ id: string }>(
        await post('/v1/classes', {
          name: `${label} ${crypto.randomUUID()}`,
          subjectId: '10000000-0000-4000-8000-000000000001',
          gradeId: '10000000-0000-4000-8000-000000000011',
          startDate: day(-10),
          endDate: day(30),
          note: null,
        }),
      )
      classes.push(klass)
      records.push(
        ClassStudent.parse(
          await json(
            await post(`/v1/classes/${klass.id}/students`, {
              studentId: student.id,
              joinDate: day(-2),
              leaveDate: null,
              note: null,
            }),
          ),
        ),
      )
    }
    const assignment = await json<{ id: string }>(
      await post(`/v1/classes/${classes[0]!.id}/assignments`, {
        accountId: account.id,
        role,
        startDate: day(-1),
        endDate: day(20),
        subjectNote: null,
      }),
    )
    const path = `/v1/students/${student.id}`
    expect(Student.parse(await json(await api(path, { token }))).canEdit).toBe(true)
    const edit = (school: string, expectedVersion = 1) =>
      api(path, { token, method: 'PUT', body: { ...original, school, expectedVersion } })
    const concurrent = await Promise.all([edit('School A'), edit('School B')])
    expect(concurrent.map((r) => r.status).sort()).toEqual([200, 409])
    expect(await errorCode(concurrent.find((r) => r.status === 409)!)).toBe('version_conflict')
    const saved = Student.parse(await json(concurrent.find((r) => r.status === 200)!))
    expect(Student.parse(await json(await api(path, { token: manager }))).school).toBe(saved.school)
    expect(saved.code).toBe(student.code)
    // Identity/status and saved join dates are not writable through these endpoints.
    for (const extra of [{ code: 'changed' }, { status: 'deleted' }, { id: crypto.randomUUID() }]) {
      expect(
        (
          await api(path, {
            token,
            method: 'PUT',
            body: { ...original, expectedVersion: 2, ...extra },
          })
        ).status,
      ).toBe(400)
    }
    const part = records[0]!.participations[0]!
    const outside = records[1]!.participations[0]!
    const note = (id: string, expectedVersion: number, value = 'Teacher note') =>
      api(`/v1/participations/${id}/note`, {
        token,
        method: 'PUT',
        body: { note: value, expectedVersion },
      })
    expect((await note(part.id, 1)).status).toBe(200)
    expect((await note(outside.id, 1)).status).toBe(403)
    const leave = (id: string, expectedVersion: number, leaveDate: string | null) =>
      post(`/v1/participations/${id}/leave`, { leaveDate, expectedVersion }, token)
    expect((await leave(outside.id, 1, day(1))).status).toBe(403)
    expect((await leave(part.id, 2, day(1))).status).toBe(200)
    expect(await errorCode(await leave(part.id, 3, day(2)))).toBe('participation_dates_locked')
    expect((await leave(part.id, 3, null)).status).toBe(400)
    expect(
      (
        await api(`/v1/participations/${part.id}/note`, {
          token,
          method: 'PUT',
          body: { note: 'No date change', joinDate: day(-1), expectedVersion: 3 },
        })
      ).status,
    ).toBe(400)
    for (const [route, body] of [
      ['/v1/students', fields()],
      [`${path}/delete`, { reason: 'No', expectedVersion: 2 }],
      [`${path}/restore`, { ...original, expectedVersion: 2 }],
      [
        `/v1/classes/${classes[0]!.id}/students`,
        { studentId: student.id, joinDate: day(2), leaveDate: null, note: null },
      ],
      [`/v1/class-students/${records[0]!.id}/delete`, { reason: 'No', expectedVersion: 1 }],
      [`/v1/participations/${part.id}/cancel`, { reason: 'No', expectedVersion: 3 }],
      [
        `/v1/participations/${part.id}/transfer`,
        {
          targetClassId: classes[1]!.id,
          leaveDate: day(1),
          joinDate: day(1),
          note: null,
          expectedVersion: 3,
        },
      ],
    ] as const)
      expect((await post(route, body, token)).status).toBe(403)

    expect(
      (
        await post(`/v1/assignments/${assignment.id}/end`, {
          reason: 'Revoked',
          expectedVersion: 1,
        })
      ).status,
    ).toBe(200)
    expect(Student.parse(await json(await api(path, { token }))).canEdit).toBe(false)
    expect((await edit('Old token', 2)).status).toBe(403)
    expect((await note(part.id, 3)).status).toBe(403)
    expect((await leave(part.id, 3, day(3))).status).toBe(403)
    await signOut(token)
    expect((await edit('Revoked session', 2)).status).toBe(401)
  })
}
