import { Assignment, ClassDetail, ClassPage, ClassSummary } from '@mledu/contracts/classes'
import { ErrorResponse } from '@mledu/contracts/common'
import { beforeAll, describe, expect, it } from 'vitest'
import { api, createReadyAccount, errorCode, json, signIn } from './support'

// Classes and assignments over HTTP (CLASS-01/02/03, AUTH-04/07). Rights are
// re-read on every request, so ending an assignment closes the class at once
// for a token that is still valid.
let admin: string
let receptionist: string

const SUBJECT = '10000000-0000-4000-8000-000000000001'
const GRADE = '10000000-0000-4000-8000-000000000011'
const day = (offset: number) => {
  // Business date in Asia/Ho_Chi_Minh, shifted by whole days.
  const now = new Date(Date.now() + 7 * 3600_000 + offset * 86_400_000)
  return now.toISOString().slice(0, 10)
}

async function createClass(name: string, start = -10, end = 90) {
  const response = await api('/v1/classes', {
    token: receptionist,
    method: 'POST',
    body: {
      name,
      subjectId: SUBJECT,
      gradeId: GRADE,
      startDate: day(start),
      endDate: day(end),
      note: null,
    },
  })
  expect(response.status).toBe(201)
  return ClassSummary.parse(await json(response))
}

const assign = (classId: string, accountId: string, role: string, start: number, end: number) =>
  api(`/v1/classes/${classId}/assignments`, {
    token: receptionist,
    method: 'POST',
    body: { accountId, role, startDate: day(start), endDate: day(end), subjectNote: null },
  })

beforeAll(async () => {
  ;[admin, receptionist] = await Promise.all([signIn('admin'), signIn('receptionist')])
})

describe('classes and assignments', () => {
  it('a teacher sees the class only while the assignment is in effect', async () => {
    const teacher = await createReadyAccount(admin, 'teacher')
    const klass = await createClass(`Lớp quyền ${Date.now()}`)

    expect(
      (await api(`/v1/classes/${klass.id}`, { token: teacher.session.accessToken })).status,
    ).toBe(404)
    const created = await assign(klass.id, teacher.id, 'teacher', -1, 30)
    expect(created.status).toBe(201)
    const assignment = Assignment.parse(await json(created))

    const opened = await api(`/v1/classes/${klass.id}`, { token: teacher.session.accessToken })
    expect(ClassDetail.parse(await json(opened)).myRole).toBe('teacher')
    const mine = ClassPage.parse(
      await json(await api('/v1/classes', { token: teacher.session.accessToken })),
    )
    expect(mine.items.map((item) => item.id)).toEqual([klass.id])

    const refused = await api(`/v1/assignments/${assignment.id}/end`, {
      token: teacher.session.accessToken,
      method: 'POST',
      body: { reason: 'Tự kết thúc', expectedVersion: assignment.rowVersion },
    })
    expect(refused.status).toBe(403)

    const ended = await api(`/v1/assignments/${assignment.id}/end`, {
      token: receptionist,
      method: 'POST',
      body: { reason: 'Kết thúc sớm', expectedVersion: assignment.rowVersion },
    })
    expect(Assignment.parse(await json(ended)).status).toBe('ended')
    // Same token, next request: the class is no longer reachable.
    expect(
      (await api(`/v1/classes/${klass.id}`, { token: teacher.session.accessToken })).status,
    ).toBe(404)
  })

  it('two concurrent overlapping assignments of one person: exactly one is stored', async () => {
    const person = await createReadyAccount(admin, 'overlap')
    const klass = await createClass(`Lớp đồng thời ${Date.now()}`)
    const responses = await Promise.all([
      assign(klass.id, person.id, 'teacher', 0, 20),
      assign(klass.id, person.id, 'assistant', 10, 30),
      assign(klass.id, person.id, 'teacher', 5, 15),
    ])
    expect(responses.map((r) => r.status).sort()).toEqual([201, 409, 409])
    for (const response of responses.filter((r) => r.status === 409)) {
      expect(await errorCode(response)).toBe('assignment_overlap')
    }
  })

  it('AUTH-04: refuses deleting an account that teaches now and names the class', async () => {
    const person = await createReadyAccount(admin, 'busy')
    const name = `Lớp bận ${Date.now()}`
    const klass = await createClass(name)
    expect((await assign(klass.id, person.id, 'assistant', 0, 10)).status).toBe(201)

    const refused = await api(`/v1/accounts/${person.id}/delete`, {
      token: admin,
      method: 'POST',
      body: { reason: 'Nghỉ việc', expectedVersion: person.rowVersion },
    })
    expect(refused.status).toBe(409)
    const body = ErrorResponse.parse(await json(refused))
    expect(body.error.code).toBe('assignment_in_effect')
    expect(body.error.details).toEqual([{ path: 'class', message: name }])
  })

  it('CLASS-03: the opening date of a started class is locked', async () => {
    const klass = await createClass(`Lớp khóa ngày ${Date.now()}`)
    const response = await api(`/v1/classes/${klass.id}`, {
      token: receptionist,
      method: 'PUT',
      body: {
        name: klass.name,
        subjectId: SUBJECT,
        gradeId: GRADE,
        startDate: day(-9),
        endDate: klass.endDate,
        note: null,
        expectedVersion: klass.rowVersion,
      },
    })
    expect(response.status).toBe(409)
    expect(await errorCode(response)).toBe('class_dates_locked')
  })
})
