import type { GradingConfig } from '@mledu/contracts/assessments'
import { describe, expect, it } from 'vitest'
import { ieltsSkillsEntry, overallPreview, skillPreview, type IeltsFields } from './ieltsEntry'

const config: GradingConfig = {
  scaleKind: 'ielts',
  showComponents: true,
  formulaVersion: 'mledu-ielts-v1',
  skills: [
    { code: 'L', inputMode: 'detailed', maxQuestions: 40 },
    { code: 'R', inputMode: 'direct' },
    { code: 'W', inputMode: 'detailed' },
    { code: 'S', inputMode: 'detailed' },
  ],
}
const [listening, , writing, speaking] = config.scaleKind === 'ielts' ? config.skills : []

const writingFields = (values: string[]) => ({
  answers: '',
  band: '',
  criteria: Object.fromEntries(
    ['t1_ta', 't1_cc', 't1_lr', 't1_gra', 't2_tr', 't2_cc', 't2_lr', 't2_gra'].map((code, i) => [
      code,
      values[i] ?? '',
    ]),
  ),
})

describe('IELTS entry preview (TEST-01)', () => {
  it('rounds each Task before the 1:2 Writing weight', () => {
    const preview = skillPreview(
      writing!,
      writingFields(['6', '6', '6', '6,5', '6', '6', '6,5', '6,5']),
    )
    expect(preview).toEqual({ task1: 6, task2: 6.5, band: 6.5 })
  })

  it('leaves a band empty while a criterion is missing (never 0)', () => {
    expect(skillPreview(writing!, writingFields(['6', '6', '6', '6'])).band).toBeNull()
  })

  it('sends typed inputs only and refuses off-step bands', () => {
    const fields: IeltsFields = {
      L: { answers: '30', band: '6,5', criteria: {} },
      R: { answers: '', band: '', criteria: {} },
      W: writingFields(['6']),
      S: { answers: '', band: '', criteria: { fc: '', lr: '', gra: '', pronunciation: '' } },
    }
    expect(ieltsSkillsEntry(config, fields)).toEqual({
      L: { band: 6.5, correctAnswers: 30 },
      W: { criteria: { t1_ta: 6 } },
    })
    expect(
      ieltsSkillsEntry(config, { ...fields, R: { ...fields.R!, band: '6,3' } }),
    ).toBeUndefined()
    expect(
      ieltsSkillsEntry(config, { L: { answers: '41', band: '', criteria: {} } }),
    ).toBeUndefined()
    expect(ieltsSkillsEntry(config, {})).toBeNull()
  })

  it('shows Overall only with four bands', () => {
    const fields: IeltsFields = {
      L: { answers: '30', band: '6,5', criteria: {} },
      R: { answers: '', band: '7', criteria: {} },
      W: writingFields(['6', '6', '6', '6,5', '6', '6', '6,5', '6,5']),
      S: {
        answers: '',
        band: '',
        criteria: { fc: '7', lr: '6,5', gra: '6,5', pronunciation: '7' },
      },
    }
    expect(skillPreview(speaking!, fields.S).band).toBe(7)
    expect(skillPreview(listening!, fields.L).band).toBe(6.5)
    expect(overallPreview(config, fields)).toBe(7)
    expect(overallPreview(config, { ...fields, S: { ...fields.S!, criteria: {} } })).toBeNull()
  })
})
