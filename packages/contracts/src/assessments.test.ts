import { describe, expect, it } from 'vitest'
import {
  CreateTestRequest,
  CreateTestTemplateRequest,
  hasDetails,
  roundBand,
  SaveTestResultsRequest,
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

describe('test requests (TEST-05)', () => {
  const config = { scaleKind: 'numeric', inputMode: 'direct', maxScore: 10 }
  const base = { name: 'Giữa kỳ', testOn: '2026-10-31', description: null, config }
  it('requires name, date and configuration; the template is optional', () => {
    expect(CreateTestRequest.safeParse({ ...base, sourceTemplateVersionId: null }).success).toBe(
      true,
    )
    for (const missing of ['name', 'testOn', 'config'] as const) {
      const body: Record<string, unknown> = { ...base, sourceTemplateVersionId: null }
      delete body[missing]
      expect(CreateTestRequest.safeParse(body).success).toBe(false)
    }
    expect(
      CreateTestRequest.safeParse({ ...base, name: '  ', sourceTemplateVersionId: null }).success,
    ).toBe(false)
    expect(
      CreateTestRequest.safeParse({ ...base, testOn: '31/10/2026', sourceTemplateVersionId: null })
        .success,
    ).toBe(false)
  })

  it('validates the configuration like a template and refuses extra fields', () => {
    expect(
      CreateTestRequest.safeParse({
        ...base,
        config: { ...config, maxScore: 8.255 },
        sourceTemplateVersionId: null,
      }).success,
    ).toBe(false)
  })

  it('knows when the display option has something to show', () => {
    expect(hasDetails({ scaleKind: 'numeric', inputMode: 'direct', maxScore: 10 })).toBe(false)
    expect(
      hasDetails({
        scaleKind: 'fraction',
        inputMode: 'components',
        showComponents: false,
        components: [{ name: 'A', totalQuestions: 1 }],
      }),
    ).toBe(true)
    expect(
      hasDetails({
        scaleKind: 'ielts',
        showComponents: false,
        skills: [{ code: 'S', inputMode: 'direct' }],
      }),
    ).toBe(false)
    expect(
      hasDetails({
        scaleKind: 'ielts',
        showComponents: false,
        skills: [{ code: 'W', inputMode: 'detailed' }],
      }),
    ).toBe(true)
  })
})

describe('test results (TEST-01/04)', () => {
  const save = (entry: unknown) =>
    SaveTestResultsRequest.safeParse({
      configId: '00000000-0000-4000-8000-000000000001',
      items: [{ studentId: '00000000-0000-4000-8000-000000000002', expectedVersion: null, entry }],
    }).success

  it('accepts one kind of value per entry', () => {
    expect(save({ absent: true })).toBe(true)
    expect(save({ absent: false, score: 8.25 })).toBe(true)
    expect(save({ absent: false, score: 0 })).toBe(true)
    expect(save({ absent: false, correctAnswers: 30 })).toBe(true)
    expect(save({ absent: false, level: 'l2' })).toBe(true)
    expect(save({ absent: false, components: { c1: 1.25, c2: null } })).toBe(true)
    expect(save(null)).toBe(true)
  })

  it('refuses rounding, negatives, Absent with values and mixed entries', () => {
    expect(save({ absent: false, score: 8.255 })).toBe(false)
    expect(save({ absent: false, score: -1 })).toBe(false)
    expect(save({ absent: false, correctAnswers: 1.5 })).toBe(false)
    expect(save({ absent: true, score: 0 })).toBe(false)
    expect(save({ absent: false, score: 5, components: { c1: 5 } })).toBe(false)
    expect(save({ absent: false, components: { total: 5 } })).toBe(false)
  })
})

describe('IELTS results (TEST-01)', () => {
  const save = (skills: unknown) =>
    SaveTestResultsRequest.safeParse({
      configId: '00000000-0000-4000-8000-000000000001',
      items: [
        {
          studentId: '00000000-0000-4000-8000-000000000002',
          expectedVersion: null,
          entry: { absent: false, skills },
        },
      ],
    }).success

  it('rounds bands with the 0.25 and 0.75 limits', () => {
    expect(roundBand(6.125)).toBe(6)
    expect(roundBand(6.25)).toBe(6.5)
    expect(roundBand(6.75)).toBe(7)
  })

  it('accepts typed inputs by mode and refuses off-step bands or computed values', () => {
    expect(save({ L: { correctAnswers: 30, band: 6.5 }, R: { band: 7 } })).toBe(true)
    expect(save({ W: { criteria: { t1_ta: 6, t2_tr: null } }, S: null })).toBe(true)
    expect(save({ R: { band: 6.3 } })).toBe(false)
    expect(save({ R: { band: 9.5 } })).toBe(false)
    expect(save({ X: { band: 6 } })).toBe(false)
    expect(save({ W: { criteria: { t1_ta: 6 }, band: 6 } })).toBe(false)
    expect(save({ L: { band: 6, overall: 6 } })).toBe(false)
  })
})
