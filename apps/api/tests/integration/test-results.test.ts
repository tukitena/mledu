import { ClassTest, TestResults } from '@mledu/contracts/assessments'
import { beforeAll, describe, expect, it } from 'vitest'
import { api, createReadyAccount, errorCode, json, signIn } from './support'

// Results of a test over HTTP (TEST-01/04/05) and the TEST-03 re-entry: the
// request contract, the computed totals and the rights of the current role.
let admin: string
let receptionist: string
const unique = () => `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`
const day = (n: number) =>
  new Date(Date.now() + 7 * 3600_000 + n * 86_400_000).toISOString().slice(0, 10)

const post = (path: string, body: unknown, token = admin) =>
  api(path, { method: 'POST', token, body })
const put = (path: string, body: unknown, token = admin) =>
  api(path, { method: 'PUT', token, body })

async function fixture(config: unknown) {
  const klass = await post('/v1/classes', {
    name: `Kết quả ${unique()}`,
    subjectId: '10000000-0000-4000-8000-000000000001',
    gradeId: '10000000-0000-4000-8000-000000000011',
    startDate: day(-10),
    endDate: day(30),
    note: null,
  })
  expect(klass.status).toBe(201)
  const classId = (await json<{ id: string }>(klass)).id
  const students: string[] = []
  for (const name of ['An', 'Bình']) {
    const created = await post('/v1/students', {
      fullName: `${name} ${unique()}`,
      parentName: null,
      parentPhones: [],
      studentPhones: [],
      birthDate: null,
      school: null,
      generalNote: null,
    })
    expect(created.status).toBe(201)
    const id = (await json<{ id: string }>(created)).id
    const enrolled = await post(`/v1/classes/${classId}/students`, {
      studentId: id,
      joinDate: day(-5),
      leaveDate: null,
      note: null,
    })
    expect(enrolled.status).toBe(201)
    students.push(id)
  }
  const test = await post(`/v1/classes/${classId}/tests`, {
    name: 'Giữa kỳ',
    testOn: day(0),
    description: null,
    config,
    sourceTemplateVersionId: null,
  })
  expect(test.status).toBe(201)
  return { classId, students, test: ClassTest.parse(await json(test)) }
}

const components = {
  scaleKind: 'numeric',
  inputMode: 'components',
  showComponents: false,
  components: [
    { name: 'Nghe', maxScore: 3 },
    { name: 'Viết', maxScore: 4 },
  ],
}

beforeAll(async () => {
  ;[admin, receptionist] = await Promise.all([signIn('admin'), signIn('receptionist')])
})

describe('test results (TEST-01/04/05)', () => {
  it('computes totals, keeps Absent and checks versions', async () => {
    const { students, test } = await fixture(components)
    const [an, binh] = students as [string, string]
    const empty = TestResults.parse(
      await json(await api(`/v1/tests/${test.id}/results`, { token: admin })),
    )
    expect(empty.students.map((row) => row.result)).toEqual([null, null])
    expect(empty.canEdit).toBe(true)

    const saved = await put(`/v1/tests/${test.id}/results`, {
      configId: test.configId,
      items: [
        {
          studentId: an,
          expectedVersion: null,
          entry: { absent: false, components: { c1: 1.25 } },
        },
        { studentId: binh, expectedVersion: null, entry: { absent: true } },
      ],
    })
    expect(saved.status).toBe(200)
    const after = TestResults.parse(await json(saved))
    const anRow = after.students.find((row) => row.studentId === an)!
    expect(anRow.result).toMatchObject({ score: 1.25, complete: false, rowVersion: 1 })
    expect(after.students.find((row) => row.studentId === binh)!.result).toMatchObject({
      absent: true,
      score: null,
      complete: true,
    })

    const completed = TestResults.parse(
      await json(
        await put(`/v1/tests/${test.id}/results`, {
          configId: test.configId,
          items: [
            {
              studentId: an,
              expectedVersion: 1,
              entry: { absent: false, components: { c1: 1.25, c2: 2.1 } },
            },
          ],
        }),
      ),
    )
    expect(completed.students.find((row) => row.studentId === an)!.result).toMatchObject({
      score: 3.35,
      complete: true,
      rowVersion: 2,
    })

    // A stale version, three decimals and a total over components are refused.
    const stale = await put(`/v1/tests/${test.id}/results`, {
      configId: test.configId,
      items: [{ studentId: an, expectedVersion: 1, entry: { absent: true } }],
    })
    expect(stale.status).toBe(409)
    expect(await errorCode(stale)).toBe('version_conflict')
    for (const entry of [
      { absent: false, components: { c1: 1.255 } },
      { absent: false, score: 3 },
      { absent: true, score: 0 },
    ]) {
      const refused = await put(`/v1/tests/${test.id}/results`, {
        configId: test.configId,
        items: [{ studentId: an, expectedVersion: 2, entry }],
      })
      expect(refused.status).toBe(400)
    }
    const above = await put(`/v1/tests/${test.id}/results`, {
      configId: test.configId,
      items: [
        { studentId: an, expectedVersion: 2, entry: { absent: false, components: { c1: 3.5 } } },
      ],
    })
    expect(above.status).toBe(400)
    expect(await errorCode(above)).toBe('validation_failed')
  })

  it('re-enters scores after a configuration change and guards the test date', async () => {
    const { students, test } = await fixture({
      scaleKind: 'numeric',
      inputMode: 'direct',
      maxScore: 10,
    })
    const [an, binh] = students as [string, string]
    expect(
      (
        await put(`/v1/tests/${test.id}/results`, {
          configId: test.configId,
          items: [
            { studentId: an, expectedVersion: null, entry: { absent: false, score: 8.25 } },
            { studentId: binh, expectedVersion: null, entry: { absent: true } },
          ],
        })
      ).status,
    ).toBe(200)

    const changed = await put(`/v1/tests/${test.id}/config`, {
      config: { scaleKind: 'fraction', inputMode: 'direct', totalQuestions: 40 },
      sourceTemplateVersionId: null,
      expectedVersion: test.rowVersion,
    })
    expect(changed.status).toBe(200)
    const next = ClassTest.parse(await json(changed))
    expect(next.resultCount).toBe(1)
    const reread = TestResults.parse(
      await json(await api(`/v1/tests/${test.id}/results`, { token: admin })),
    )
    expect(reread.students.find((row) => row.studentId === an)!.result).toBeNull()
    expect(reread.students.find((row) => row.studentId === binh)!.result?.absent).toBe(true)

    // Entries made on the old snapshot are refused.
    const old = await put(`/v1/tests/${test.id}/results`, {
      configId: test.configId,
      items: [{ studentId: an, expectedVersion: 2, entry: { absent: false, correctAnswers: 30 } }],
    })
    expect(old.status).toBe(409)
    expect(await errorCode(old)).toBe('version_conflict')

    // Both students joined five days ago: a date before that leaves Bình out.
    const moved = await put(`/v1/tests/${test.id}`, {
      name: next.name,
      testOn: day(-8),
      description: null,
      expectedVersion: next.rowVersion,
    })
    expect(moved.status).toBe(409)
    expect(await errorCode(moved)).toBe('test_date_excludes_results')
  })

  it('follows the current academic role', async () => {
    const { classId, students, test } = await fixture({
      scaleKind: 'letter',
      inputMode: 'direct',
      levels: [{ label: 'Chưa đạt' }, { label: 'Đạt' }],
    })
    const body = {
      configId: test.configId,
      items: [
        { studentId: students[0], expectedVersion: null, entry: { absent: false, level: 'l2' } },
      ],
    }
    const refused = await put(`/v1/tests/${test.id}/results`, body, receptionist)
    expect(refused.status).toBe(403)
    expect((await api(`/v1/tests/${test.id}/results`, { token: receptionist })).status).toBe(403)

    const account = await createReadyAccount(admin, 'results-assistant')
    const outsider = await put(`/v1/tests/${test.id}/results`, body, account.session.accessToken)
    expect(outsider.status).toBe(404)
    expect(
      (
        await post(`/v1/classes/${classId}/assignments`, {
          accountId: account.id,
          role: 'assistant',
          startDate: day(-1),
          endDate: day(20),
          subjectNote: null,
        })
      ).status,
    ).toBe(201)
    const entered = await put(`/v1/tests/${test.id}/results`, body, account.session.accessToken)
    expect(entered.status).toBe(200)
    const results = TestResults.parse(await json(entered))
    expect(results.students.find((row) => row.studentId === students[0])!.result?.level).toBe('l2')
    expect(
      (await put(`/v1/tests/${test.id}/results`, { configId: test.configId, items: [] })).status,
    ).toBe(400)
  })
})
