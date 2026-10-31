import {
  ClassTest,
  ClassTestDetail,
  ClassTestList,
  TestTemplate,
} from '@mledu/contracts/assessments'
import { beforeAll, describe, expect, it } from 'vitest'
import { api, createReadyAccount, errorCode, json, signIn } from './support'

// Tests of a class over HTTP (TEST-05, TEST-02 use, TEST-04 display option):
// academic rights come from the current assignment, checked by the RPC.
let admin: string
let receptionist: string
const unique = () => `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`
const day = (n: number) =>
  new Date(Date.now() + 7 * 3600_000 + n * 86_400_000).toISOString().slice(0, 10)
const direct = { scaleKind: 'numeric', inputMode: 'direct', maxScore: 10 }
const components = (showComponents: boolean) => ({
  scaleKind: 'numeric',
  inputMode: 'components',
  showComponents,
  components: [
    { name: 'Nghe', maxScore: 4.5 },
    { name: 'Viết', maxScore: 5.5 },
  ],
})

const post = (path: string, body: unknown, token = admin) =>
  api(path, { method: 'POST', token, body })
const put = (path: string, body: unknown, token = admin) =>
  api(path, { method: 'PUT', token, body })

async function createClass() {
  const response = await post('/v1/classes', {
    name: `Học vụ ${unique()}`,
    subjectId: '10000000-0000-4000-8000-000000000001',
    gradeId: '10000000-0000-4000-8000-000000000011',
    startDate: day(-10),
    endDate: day(30),
    note: null,
  })
  expect(response.status).toBe(201)
  return (await json<{ id: string }>(response)).id
}

async function staff(classId: string, role: 'teacher' | 'assistant') {
  const account = await createReadyAccount(admin, `tests-${role}`)
  const assigned = await post(`/v1/classes/${classId}/assignments`, {
    accountId: account.id,
    role,
    startDate: day(-1),
    endDate: day(20),
    subjectNote: null,
  })
  expect(assigned.status).toBe(201)
  return account.session.accessToken
}

beforeAll(async () => {
  ;[admin, receptionist] = await Promise.all([signIn('admin'), signIn('receptionist')])
})

describe('tests of a class (TEST-05)', () => {
  it('refuses receptionists and Users without an assignment', async () => {
    const classId = await createClass()
    const body = {
      name: 'Bài 1',
      testOn: day(0),
      description: null,
      config: direct,
      sourceTemplateVersionId: null,
    }
    const created = await post(`/v1/classes/${classId}/tests`, body, receptionist)
    expect(created.status).toBe(403)
    expect(await errorCode(created)).toBe('forbidden')
    expect((await api(`/v1/classes/${classId}/tests`, { token: receptionist })).status).toBe(403)
    expect(
      (await api(`/v1/classes/${classId}/test-templates`, { token: receptionist })).status,
    ).toBe(403)
    const user = await signIn('user')
    expect((await post(`/v1/classes/${classId}/tests`, body, user)).status).toBe(404)
    expect((await api(`/v1/classes/${classId}/tests`, { method: 'POST', body })).status).toBe(401)
  })

  it('reports missing fields and a date outside the class', async () => {
    const classId = await createClass()
    const missing = await post(`/v1/classes/${classId}/tests`, {
      name: ' ',
      testOn: day(0),
      description: null,
      config: direct,
      sourceTemplateVersionId: null,
    })
    expect(missing.status).toBe(400)
    const details = (await json<{ error: { details: { path: string }[] } }>(missing)).error.details
    expect(details.map((item) => item.path)).toContain('name')
    const outside = await post(`/v1/classes/${classId}/tests`, {
      name: 'Ngoài lớp',
      testOn: day(31),
      description: null,
      config: direct,
      sourceTemplateVersionId: null,
    })
    expect(outside.status).toBe(409)
    expect(await errorCode(outside)).toBe('outside_class_dates')
  })

  it('copies a template version, keeps the copy after template edits and enforces roles', async () => {
    const classId = await createClass()
    const [teacher, assistant] = [
      await staff(classId, 'teacher'),
      await staff(classId, 'assistant'),
    ]
    const template = TestTemplate.parse(
      await json(
        await post('/v1/test-templates', {
          name: `Mẫu ${unique()}`,
          description: null,
          config: components(true),
        }),
      ),
    )

    // The assistant reads the templates of the class and copies one, adjusted.
    const choices = await api(`/v1/classes/${classId}/test-templates`, { token: assistant })
    expect(choices.status).toBe(200)
    expect((await json<{ id: string }[]>(choices)).some((item) => item.id === template.id)).toBe(
      true,
    )
    const created = await post(
      `/v1/classes/${classId}/tests`,
      {
        name: 'Giữa kỳ',
        testOn: day(0),
        description: '',
        config: { ...components(true), components: [{ name: 'Nghe', maxScore: 10 }] },
        sourceTemplateVersionId: template.currentVersionId,
      },
      assistant,
    )
    expect(created.status).toBe(201)
    const test = ClassTest.parse(await json(created))
    expect(test).toMatchObject({
      description: null,
      showComponents: true,
      configRevision: 1,
      source: { templateVersionId: template.currentVersionId, revision: 1 },
    })
    expect(test.config).toMatchObject({ maxScore: 10 })

    // Editing the template changes neither this test nor the old choice.
    const edited = await put(`/v1/test-templates/${template.id}`, {
      name: template.name,
      description: null,
      config: direct,
      expectedVersion: template.rowVersion,
    })
    expect(edited.status).toBe(200)
    const reread = ClassTestDetail.parse(
      await json(await api(`/v1/tests/${test.id}`, { token: teacher })),
    )
    expect(reread.config).toEqual(test.config)
    const stale = await post(`/v1/classes/${classId}/tests`, {
      name: 'Phiên bản cũ',
      testOn: day(0),
      description: null,
      config: direct,
      sourceTemplateVersionId: template.currentVersionId,
    })
    expect(stale.status).toBe(409)
    expect(await errorCode(stale)).toBe('template_unavailable')

    // Display option: teacher yes, assistant no.
    const hide = (token: string, expectedVersion: number) =>
      put(`/v1/tests/${test.id}/show-components`, { showComponents: false, expectedVersion }, token)
    const refused = await hide(assistant, test.rowVersion)
    expect(refused.status).toBe(403)
    const hidden = await hide(teacher, test.rowVersion)
    expect(hidden.status).toBe(200)
    const afterHide = ClassTest.parse(await json(hidden))
    expect(afterHide.showComponents).toBe(false)

    const list = ClassTestList.parse(
      await json(await api(`/v1/classes/${classId}/tests`, { token: assistant })),
    )
    expect(list).toMatchObject({ canEdit: true, canChangeDisplay: false })
    expect(list.items.map((item) => item.id)).toEqual([test.id])

    // Two simultaneous configuration changes: exactly one wins.
    const change = (maxScore: number) =>
      put(
        `/v1/tests/${test.id}/config`,
        {
          config: { ...direct, maxScore },
          sourceTemplateVersionId: null,
          expectedVersion: afterHide.rowVersion,
        },
        assistant,
      )
    const results = await Promise.all([change(20), change(30)])
    expect(results.map((r) => r.status).sort()).toEqual([200, 409])
    const final = ClassTestDetail.parse(
      await json(await api(`/v1/tests/${test.id}`, { token: teacher })),
    )
    expect(final.configRevision).toBe(2)
    expect(final.configVersions.map((item) => item.revision)).toEqual([2, 1])
    expect(final.source).toBeNull()

    // Information edits keep the configuration.
    const renamed = await put(
      `/v1/tests/${test.id}`,
      {
        name: 'Giữa kỳ I',
        testOn: day(-1),
        description: 'Ôn tập',
        expectedVersion: final.rowVersion,
      },
      teacher,
    )
    expect(renamed.status).toBe(200)
    expect(ClassTest.parse(await json(renamed))).toMatchObject({
      name: 'Giữa kỳ I',
      configRevision: 2,
    })
  })
})
