import { describe, expect, it } from 'vitest'
import {
  CreateTestTemplateRequest,
  TestTemplateConfig,
  TestTemplateConfigInput,
  UpdateTestTemplateRequest,
} from './assessments'

const ok = (value: unknown) => TestTemplateConfigInput.safeParse(value).success

describe('template configuration (TEST-01/02/04)', () => {
  it('accepts at most two decimals and refuses instead of rounding', () => {
    for (const maxScore of [10, 8.5, 8.25]) {
      expect(ok({ scaleKind: 'numeric', inputMode: 'direct', maxScore })).toBe(true)
    }
    for (const maxScore of [8.255, 0, -1, 1e-7, '10']) {
      expect(ok({ scaleKind: 'numeric', inputMode: 'direct', maxScore })).toBe(false)
    }
  })

  it('checks components: 1–50, unique names, total equal to the sum', () => {
    const components = (n: number) =>
      Array.from({ length: n }, (_, i) => ({ name: `Phần ${i + 1}`, maxScore: 1 }))
    const base = { scaleKind: 'numeric', inputMode: 'components', showComponents: false }
    expect(ok({ ...base, components: components(50) })).toBe(true)
    expect(ok({ ...base, components: components(51) })).toBe(false)
    expect(ok({ ...base, components: [] })).toBe(false)
    expect(
      ok({
        ...base,
        components: [
          { name: 'Phần 1', maxScore: 1 },
          { name: 'phan  1', maxScore: 2 },
        ],
      }),
    ).toBe(false)
    const parts = [
      { name: 'A', maxScore: 1.25 },
      { name: 'B', maxScore: 2.1 },
    ]
    expect(ok({ ...base, maxScore: 3.35, components: parts })).toBe(true)
    expect(ok({ ...base, maxScore: 3.4, components: parts })).toBe(false)
    expect(ok({ ...base, components: [{ code: 'c2', name: 'A', maxScore: 1 }] })).toBe(false)
  })

  it('checks fractions and letter sets', () => {
    expect(ok({ scaleKind: 'fraction', inputMode: 'direct', totalQuestions: 1.5 })).toBe(false)
    const levels = (n: number) => Array.from({ length: n }, (_, i) => ({ label: `Mức ${i + 1}` }))
    expect(ok({ scaleKind: 'letter', inputMode: 'direct', levels: levels(20) })).toBe(true)
    expect(ok({ scaleKind: 'letter', inputMode: 'direct', levels: levels(21) })).toBe(false)
    expect(ok({ scaleKind: 'letter', inputMode: 'direct', levels: [] })).toBe(false)
    expect(
      ok({
        scaleKind: 'letter',
        inputMode: 'direct',
        levels: [{ label: 'Đạt' }, { label: 'dat' }],
      }),
    ).toBe(false)
    expect(
      ok({ scaleKind: 'letter', inputMode: 'direct', levels: [{ label: 'x'.repeat(101) }] }),
    ).toBe(false)
  })

  it('checks IELTS skills, modes and the fixed formula', () => {
    const ielts = (skills: unknown[], extra: object = {}) =>
      ok({ scaleKind: 'ielts', showComponents: true, skills, ...extra })
    expect(
      ielts([
        { code: 'L', inputMode: 'detailed', maxQuestions: 40 },
        { code: 'R', inputMode: 'direct' },
      ]),
    ).toBe(true)
    expect(ielts([])).toBe(false)
    expect(ielts([{ code: 'L', inputMode: 'detailed' }])).toBe(false)
    expect(ielts([{ code: 'W', inputMode: 'detailed', maxQuestions: 2 }])).toBe(false)
    expect(
      ielts([
        { code: 'S', inputMode: 'direct' },
        { code: 'S', inputMode: 'detailed' },
      ]),
    ).toBe(false)
    expect(ielts([{ code: 'S', inputMode: 'direct' }], { formulaVersion: 'custom' })).toBe(false)
  })

  it('requires codes and totals in stored configurations', () => {
    expect(
      TestTemplateConfig.safeParse({
        scaleKind: 'letter',
        inputMode: 'direct',
        levels: [{ label: 'Đạt' }],
      }).success,
    ).toBe(false)
    expect(
      TestTemplateConfig.safeParse({
        scaleKind: 'letter',
        inputMode: 'direct',
        levels: [{ code: 'l1', label: 'Đạt' }],
      }).success,
    ).toBe(true)
  })
})

describe('template requests', () => {
  const config = { scaleKind: 'numeric', inputMode: 'direct', maxScore: 10 }
  it('turns an empty description into null and refuses extra fields', () => {
    const parsed = CreateTestTemplateRequest.parse({ name: ' Giữa kỳ ', description: ' ', config })
    expect(parsed).toMatchObject({ name: 'Giữa kỳ', description: null })
    expect(
      CreateTestTemplateRequest.safeParse({ name: 'A', description: null, config, classId: 'x' })
        .success,
    ).toBe(false)
    expect(
      UpdateTestTemplateRequest.safeParse({ name: 'A', description: null, config }).success,
    ).toBe(false)
  })
})
