import { TestTemplate, TestTemplateVersion } from '@mledu/contracts/assessments'
import { beforeAll, describe, expect, it } from 'vitest'
import { api, errorCode, json, signIn } from './support'

// Shared test template library over HTTP (TEST-02): Admin-only management is
// enforced by the API/RPC even for direct requests; edits add versions.
let admin: string
let receptionist: string
let user: string
const unique = () => `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`
const letter = {
  scaleKind: 'letter',
  inputMode: 'direct',
  levels: [{ label: 'Chưa đạt' }, { label: 'Đạt' }, { label: 'Tốt' }, { label: 'Xuất sắc' }],
}

beforeAll(async () => {
  ;[admin, receptionist, user] = await Promise.all([
    signIn('admin'),
    signIn('receptionist'),
    signIn('user'),
  ])
})

async function create(body: unknown) {
  const response = await api('/v1/test-templates', { token: admin, method: 'POST', body })
  expect(response.status).toBe(201)
  return TestTemplate.parse(await json(response))
}

describe('test template library (TEST-02)', () => {
  it('refuses every non-Admin account on reads and writes', async () => {
    const body = { name: `Mẫu ${unique()}`, description: null, config: letter }
    for (const token of [receptionist, user]) {
      const created = await api('/v1/test-templates', { token, method: 'POST', body })
      expect(created.status).toBe(403)
      expect(await errorCode(created)).toBe('forbidden')
      expect((await api('/v1/test-templates', { token })).status).toBe(403)
    }
    expect((await api('/v1/test-templates', { method: 'POST', body })).status).toBe(401)
  })

  it('creates, versions, archives and restores a template', async () => {
    const template = await create({
      name: `Giữa kỳ ${unique()}`,
      description: '',
      config: letter,
    })
    expect(template).toMatchObject({ revision: 1, description: null, archived: false })
    expect(template.config.scaleKind === 'letter' && template.config.levels[0]).toEqual({
      code: 'l1',
      label: 'Chưa đạt',
    })

    const edited = await api(`/v1/test-templates/${template.id}`, {
      token: admin,
      method: 'PUT',
      body: {
        name: template.name,
        description: 'Hai phần',
        config: {
          scaleKind: 'numeric',
          inputMode: 'components',
          showComponents: true,
          components: [
            { name: 'Nghe', maxScore: 1.25 },
            { name: 'Viết', maxScore: 2.1 },
          ],
        },
        expectedVersion: template.rowVersion,
      },
    })
    expect(edited.status).toBe(200)
    const v2 = TestTemplate.parse(await json(edited))
    expect(v2.revision).toBe(2)
    expect(v2.config).toMatchObject({ maxScore: 3.35 })

    const stale = await api(`/v1/test-templates/${template.id}`, {
      token: admin,
      method: 'PUT',
      body: { name: 'Cũ', description: null, config: letter, expectedVersion: template.rowVersion },
    })
    expect(stale.status).toBe(409)
    expect(await errorCode(stale)).toBe('version_conflict')

    const versions = (
      await json<unknown[]>(
        await api(`/v1/test-templates/${template.id}/versions`, { token: admin }),
      )
    ).map((item) => TestTemplateVersion.parse(item))
    expect(versions.map((item) => item.revision)).toEqual([2, 1])
    expect(versions[1]!.config.scaleKind).toBe('letter')

    const archived = await api(`/v1/test-templates/${template.id}/archive`, {
      token: admin,
      method: 'POST',
      body: { reason: 'Ngừng dùng', expectedVersion: v2.rowVersion },
    })
    const archivedTemplate = TestTemplate.parse(await json(archived))
    expect(archivedTemplate.archived).toBe(true)
    const active = await json<TestTemplate[]>(await api('/v1/test-templates', { token: admin }))
    expect(active.map((item) => item.id)).not.toContain(template.id)

    const restored = await api(`/v1/test-templates/${template.id}/restore`, {
      token: admin,
      method: 'POST',
      body: { expectedVersion: archivedTemplate.rowVersion },
    })
    expect(TestTemplate.parse(await json(restored))).toMatchObject({
      id: template.id,
      revision: 2,
      archived: false,
    })
  })

  it('validates configurations before the database and reports the field', async () => {
    const tooPrecise = await api('/v1/test-templates', {
      token: admin,
      method: 'POST',
      body: {
        name: 'Sai số lẻ',
        description: null,
        config: { scaleKind: 'numeric', inputMode: 'direct', maxScore: 8.255 },
      },
    })
    expect(tooPrecise.status).toBe(400)
    const body = await json<{ error: { code: string; details: { path: string }[] } }>(tooPrecise)
    expect(body.error.code).toBe('validation_failed')
    expect(body.error.details.map((detail) => detail.path)).toContain('config.maxScore')

    const custom = await api('/v1/test-templates', {
      token: admin,
      method: 'POST',
      body: {
        name: 'Công thức riêng',
        description: null,
        config: {
          scaleKind: 'ielts',
          showComponents: false,
          formulaVersion: 'custom',
          skills: [{ code: 'S', inputMode: 'direct' }],
        },
      },
    })
    expect(custom.status).toBe(400)
  })

  it('stores IELTS templates in L/R/W/S order with the fixed formula', async () => {
    const template = await create({
      name: `IELTS ${unique()}`,
      description: null,
      config: {
        scaleKind: 'ielts',
        showComponents: true,
        skills: [
          { code: 'W', inputMode: 'detailed' },
          { code: 'L', inputMode: 'detailed', maxQuestions: 40 },
        ],
      },
    })
    expect(template.config).toEqual({
      scaleKind: 'ielts',
      formulaVersion: 'mledu-ielts-v1',
      showComponents: true,
      skills: [
        { code: 'L', inputMode: 'detailed', maxQuestions: 40 },
        { code: 'W', inputMode: 'detailed' },
      ],
    })
  })

  it('lets only one of two concurrent edits of the same version win', async () => {
    const template = await create({
      name: `Đồng thời ${unique()}`,
      description: null,
      config: letter,
    })
    const responses = await Promise.all(
      ['A', 'B'].map((suffix) =>
        api(`/v1/test-templates/${template.id}`, {
          token: admin,
          method: 'PUT',
          body: {
            name: `${template.name} ${suffix}`,
            description: null,
            config: letter,
            expectedVersion: template.rowVersion,
          },
        }),
      ),
    )
    expect(responses.map((response) => response.status).sort()).toEqual([200, 409])
    const versions = await json<unknown[]>(
      await api(`/v1/test-templates/${template.id}/versions`, { token: admin }),
    )
    expect(versions).toHaveLength(2)
  })
})
