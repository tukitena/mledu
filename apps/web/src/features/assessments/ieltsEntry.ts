import {
  IELTS_CRITERIA,
  roundBand,
  type GradingConfig,
  type IeltsSkill,
  type IeltsSkillEntry,
  type TestResult,
} from '@mledu/contracts/assessments'
import { parseNumber } from './gradingForm'

// IELTS entry grid helpers (TEST-01). The UI only previews the computed bands;
// the backend computes and stores them and never takes them from the client.

type IeltsConfig = Extract<GradingConfig, { scaleKind: 'ielts' }>
export type SkillConfig = IeltsConfig['skills'][number]

export interface IeltsSkillFields {
  answers: string
  band: string
  criteria: Record<string, string>
}
export type IeltsFields = Partial<Record<IeltsSkill, IeltsSkillFields>>

/** Criteria typed for W/S in detail; none otherwise. */
export const criteriaOf = (skill: SkillConfig): readonly string[] =>
  skill.inputMode === 'detailed' && (skill.code === 'W' || skill.code === 'S')
    ? IELTS_CRITERIA[skill.code]
    : []

/** L/R in detail type the answers and the band; direct types the band; W/S in detail type criteria. */
export const typesBand = (skill: SkillConfig) => criteriaOf(skill).length === 0
export const typesAnswers = (skill: SkillConfig) =>
  skill.inputMode === 'detailed' && (skill.code === 'L' || skill.code === 'R')

/** null = empty, NaN = invalid (outside 0–9 or not a step of 0.5); never corrected. */
export function bandOf(input: string): number | null {
  if (!input.trim()) return null
  const value = parseNumber(input)
  return Number.isFinite(value) && value >= 0 && value <= 9 && Number.isInteger(value * 2)
    ? value
    : Number.NaN
}

export function answersOf(input: string, max: number | undefined): number | null {
  if (!input.trim()) return null
  const value = parseNumber(input)
  return Number.isInteger(value) && value >= 0 && value <= (max ?? 0) ? value : Number.NaN
}

export function ieltsFields(
  config: GradingConfig,
  result: TestResult | null,
  format: (value: number) => string,
): IeltsFields {
  if (config.scaleKind !== 'ielts') return {}
  const text = (value: number | null | undefined) =>
    value === null || value === undefined ? '' : format(value)
  return Object.fromEntries(
    config.skills.map((skill) => {
      const saved = result?.ielts?.[skill.code]
      return [
        skill.code,
        {
          answers: text(saved?.correctAnswers),
          band: text(saved?.inputBand),
          criteria: Object.fromEntries(
            criteriaOf(skill).map((code) => [code, text(saved?.criteria[code])]),
          ),
        },
      ]
    }),
  )
}

/** Skill inputs to send: null when nothing is typed, undefined when a value is invalid. */
export function ieltsSkillsEntry(
  config: GradingConfig,
  fields: IeltsFields,
): Partial<Record<IeltsSkill, IeltsSkillEntry>> | null | undefined {
  if (config.scaleKind !== 'ielts') return null
  const skills: Partial<Record<IeltsSkill, IeltsSkillEntry>> = {}
  for (const skill of config.skills) {
    const input = fields[skill.code]
    if (!input) continue
    if (criteriaOf(skill).length) {
      const criteria: Record<string, number> = {}
      for (const code of criteriaOf(skill)) {
        const value = bandOf(input.criteria[code] ?? '')
        if (Number.isNaN(value)) return undefined
        if (value !== null) criteria[code] = value
      }
      if (Object.keys(criteria).length) skills[skill.code] = { criteria }
      continue
    }
    const band = bandOf(input.band)
    const answers = typesAnswers(skill) ? answersOf(input.answers, skill.maxQuestions) : null
    if (Number.isNaN(band) || Number.isNaN(answers)) return undefined
    if (band === null && answers === null) continue
    skills[skill.code] = {
      ...(band !== null ? { band } : {}),
      ...(answers !== null ? { correctAnswers: answers } : {}),
    }
  }
  return Object.keys(skills).length ? skills : null
}

const average = (values: number[]) => values.reduce((sum, value) => sum + value, 0) / values.length

/** Preview of Task 1, Task 2 and the skill band as the backend computes them. */
export function skillPreview(skill: SkillConfig, input: IeltsSkillFields | undefined) {
  const empty = { task1: null, task2: null, band: null } as {
    task1: number | null
    task2: number | null
    band: number | null
  }
  if (!input) return empty
  if (typesBand(skill)) {
    const band = bandOf(input.band)
    return { ...empty, band: Number.isNaN(band) ? null : band }
  }
  const values = (prefix: string) =>
    criteriaOf(skill)
      .filter((code) => code.startsWith(prefix))
      .map((code) => bandOf(input.criteria[code] ?? ''))
  const task = (prefix: string) => {
    const list = values(prefix)
    return list.every((value) => value !== null && !Number.isNaN(value))
      ? roundBand(average(list as number[]))
      : null
  }
  if (skill.code === 'S') return { ...empty, band: task('') }
  const task1 = task('t1_')
  const task2 = task('t2_')
  return {
    task1,
    task2,
    band: task1 !== null && task2 !== null ? roundBand((task1 + 2 * task2) / 3) : null,
  }
}

/** Overall only with all four skills and four bands. */
export function overallPreview(config: GradingConfig, fields: IeltsFields): number | null {
  if (config.scaleKind !== 'ielts' || config.skills.length !== 4) return null
  const bands = config.skills.map((skill) => skillPreview(skill, fields[skill.code]).band)
  return bands.every((band) => band !== null) ? roundBand(average(bands as number[])) : null
}
