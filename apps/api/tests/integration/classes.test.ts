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

async function createClass(name: string, start = -10, end = 90, schoolYearStart?: number | null) {
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
      ...(schoolYearStart === undefined ? {} : { schoolYearStart }),
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
  it('orders before pagination and combines grade, subject, status and current staff filters', async () => {
    const prefix = `Filters API ${Date.now()}`
    const teacher = await createReadyAccount(admin, 'class-filters')
    const longer = await createClass(`${prefix} 10`, -10, 90, 2026)
    const first = await createClass(`${prefix} 6`, -10, 90, 2026)
    await createClass(`${prefix} 7`, -10, 90, 2026)
    const assignment = Assignment.parse(
      await json(await assign(first.id, teacher.id, 'assistant', -1, 30)),
    )
    await assign(longer.id, teacher.id, 'teacher', 1, 30)
    const list = async (query: string, token = receptionist) => {
      const response = await api(`/v1/classes?search=${encodeURIComponent(prefix)}&${query}`, {
        token,
      })
      expect(response.status).toBe(200)
      return ClassPage.parse(await json(response))
    }
    const ordered = await list('pageSize=1')
    expect(ordered.items[0]!.id).toBe(first.id)
    expect((await list('pageSize=1&page=3')).items[0]!.id).toBe(longer.id)
    const filters = `gradeId=${GRADE}&subjectId=${SUBJECT}&schoolYear=2026&status=running&staffId=${teacher.id}`
    const filtered = await list(filters)
    expect(filtered.total).toBe(1)
    expect(filtered.items.map((item) => item.id)).toEqual([first.id])
    expect((await list('status=ended')).total).toBe(0)
    expect((await list('status=closed')).total).toBe(0)
    expect((await list('status=open')).total).toBe(3)
    expect((await list(`${filters}&page=10`)).total).toBe(1)
    for (const query of ['status=active', 'gradeId=bad', 'subjectId=bad', 'staffId=bad']) {
      expect((await api(`/v1/classes?${query}`, { token: receptionist })).status).toBe(400)
    }
    const mine = await list(filters, teacher.session.accessToken)
    expect(mine.total).toBe(1)
    expect(mine.filterOptions.staff.map((person) => person.id)).toEqual([teacher.id])
    await api(`/v1/assignments/${assignment.id}/end`, {
      token: receptionist,
      method: 'POST',
      body: { reason: 'End filter scope', expectedVersion: 1 },
    })
    const revoked = await list(filters, teacher.session.accessToken)
    expect(revoked.total).toBe(0)
    expect(revoked.filterOptions).toEqual({ grades: [], subjects: [], staff: [] })
  })
  it('creates, filters, changes and clears optional school years over HTTP', async () => {
    const prefix = `Năm học API ${Date.now()}`
    const first = await createClass(`${prefix} A`, -10, 90, 2026)
    const second = await createClass(`${prefix} B`, -10, 90, 2026)
    const independent = await createClass(`${prefix} C`)
    expect(first.schoolYearStart).toBe(2026)
    expect(independent.schoolYearStart).toBeNull()
    const list = async (schoolYear: string, page = 1) =>
      ClassPage.parse(
        await json(
          await api(
            `/v1/classes?search=${encodeURIComponent(prefix)}&schoolYear=${schoolYear}&pageSize=1&page=${page}`,
            { token: receptionist },
          ),
        ),
      )
    const filtered = await list('2026')
    expect(filtered.total).toBe(2)
    expect(filtered.items).toHaveLength(1)
    const next = await list('2026', 2)
    expect(new Set([filtered.items[0]!.id, next.items[0]!.id])).toEqual(
      new Set([first.id, second.id]),
    )
    expect((await list('none')).items.map((item) => item.id)).toEqual([independent.id])
    expect((await list('all')).total).toBe(3)
    expect((await list('none')).schoolYears).toContain(2026)
    for (const value of ['9999', '02026', '2026-2027', 'null']) {
      const response = await api(`/v1/classes?schoolYear=${value}`, { token: receptionist })
      expect(response.status).toBe(400)
      expect(await errorCode(response)).toBe('validation_failed')
    }
    const fields = {
      name: first.name,
      subjectId: SUBJECT,
      gradeId: GRADE,
      startDate: first.startDate,
      endDate: first.endDate,
      note: null,
    }
    const update = (body: object) =>
      api(`/v1/classes/${first.id}`, {
        token: receptionist,
        method: 'PUT',
        body: { ...fields, ...body },
      })
    const changed = await update({ expectedVersion: 1, schoolYearStart: 2027 })
    expect(changed.status).toBe(200)
    expect(ClassSummary.parse(await json(changed)).schoolYearStart).toBe(2027)
    const stale = await update({ expectedVersion: 1, schoolYearStart: null })
    expect(stale.status).toBe(409)
    expect(await errorCode(stale)).toBe('version_conflict')
    const legacy = await update({ expectedVersion: 2, note: 'Older client' })
    expect(legacy.status).toBe(200)
    expect(ClassSummary.parse(await json(legacy)).schoolYearStart).toBe(2027)
    const cleared = await update({ expectedVersion: 3, schoolYearStart: null })
    expect(cleared.status).toBe(200)
    expect(ClassSummary.parse(await json(cleared)).schoolYearStart).toBeNull()
  })

  it('scopes year options and results to the current teacher assignment', async () => {
    const teacher = await createReadyAccount(admin, 'year-scope')
    const mine = await createClass(`Năm học có quyền ${Date.now()}`, -10, 90, 2031)
    await createClass(`Năm học không có quyền ${Date.now()}`, -10, 90, 2032)
    const created = await assign(mine.id, teacher.id, 'teacher', -1, 30)
    const assignment = Assignment.parse(await json(created))
    const read = async () =>
      ClassPage.parse(
        await json(
          await api('/v1/classes?schoolYear=2031', {
            token: teacher.session.accessToken,
          }),
        ),
      )
    expect((await read()).schoolYears).toEqual([2031])
    expect((await read()).items.map((item) => item.id)).toEqual([mine.id])
    expect(
      (
        await api(`/v1/assignments/${assignment.id}/end`, {
          token: receptionist,
          method: 'POST',
          body: { reason: 'Kết thúc quyền đọc', expectedVersion: assignment.rowVersion },
        })
      ).status,
    ).toBe(200)
    expect((await read()).schoolYears).toEqual([])
    expect((await read()).total).toBe(0)
  })

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
