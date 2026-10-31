import {
  DEFAULT_LETTER_LEVELS,
  GradingConfigInput,
  IELTS_SKILLS,
  type GradingConfig,
  type IeltsSkill,
  type ScaleKind,
} from '@mledu/contracts/assessments'
import { computed, reactive } from 'vue'
import { useI18n } from 'vue-i18n'

// Form state of a grading configuration (TEST-01/02/04), shared by the template
// editor and the test editor. The contract schema checks the form; the API/DB
// validate again and normalize.

interface SkillState {
  enabled: boolean
  inputMode: 'direct' | 'detailed'
  maxQuestions: string
}

export interface GradingState {
  scaleKind: ScaleKind
  inputMode: 'direct' | 'components'
  maxScore: string
  totalQuestions: string
  showComponents: boolean
  components: { name: string; limit: string }[]
  levels: { label: string }[]
  skills: Record<IeltsSkill, SkillState>
}

/** Accepts 8,25 and 8.25; anything that is not a plain number stays invalid. */
export const parseNumber = (value: string) => {
  const text = value.trim().replace(',', '.')
  return /^-?\d+(\.\d+)?$/.test(text) ? Number(text) : Number.NaN
}

function initialState(config: GradingConfig | undefined, locale: string): GradingState {
  const input = (value: number | undefined) =>
    value === undefined ? '' : String(value).replace('.', locale === 'vi' ? ',' : '.')
  const skills = Object.fromEntries(
    IELTS_SKILLS.map((code) => [
      code,
      {
        enabled: config?.scaleKind !== 'ielts',
        inputMode: 'direct',
        maxQuestions: code === 'L' || code === 'R' ? '40' : '',
      },
    ]),
  ) as Record<IeltsSkill, SkillState>
  const state: GradingState = {
    scaleKind: config?.scaleKind ?? 'numeric',
    inputMode: 'direct',
    maxScore: '10',
    totalQuestions: '',
    showComponents: false,
    components: [{ name: '', limit: '' }],
    levels: DEFAULT_LETTER_LEVELS.map((label) => ({ label })),
    skills,
  }
  if (!config) return state
  if (config.scaleKind === 'numeric' || config.scaleKind === 'fraction') {
    state.inputMode = config.inputMode
    if (config.scaleKind === 'numeric') state.maxScore = input(config.maxScore)
    else state.totalQuestions = String(config.totalQuestions)
    if (config.inputMode === 'components') {
      state.showComponents = config.showComponents
      state.components = config.components.map((item) => ({
        name: item.name,
        limit: 'maxScore' in item ? input(item.maxScore) : String(item.totalQuestions),
      }))
    }
  } else if (config.scaleKind === 'letter') {
    state.levels = config.levels.map((level) => ({ label: level.label }))
  } else {
    state.showComponents = config.showComponents
    for (const skill of config.skills) {
      state.skills[skill.code] = {
        enabled: true,
        inputMode: skill.inputMode,
        maxQuestions: skill.maxQuestions
          ? String(skill.maxQuestions)
          : state.skills[skill.code].maxQuestions,
      }
    }
  }
  return state
}

export function useGradingForm(initial?: GradingConfig) {
  const { locale } = useI18n()
  const form = reactive(initialState(initial, locale.value))

  /** Replaces the whole form, e.g. after choosing a template to copy. */
  function reset(config?: GradingConfig) {
    Object.assign(form, initialState(config, locale.value))
  }

  function buildConfig(): unknown {
    switch (form.scaleKind) {
      case 'numeric':
      case 'fraction': {
        const limitKey = form.scaleKind === 'numeric' ? 'maxScore' : 'totalQuestions'
        if (form.inputMode === 'direct')
          return {
            scaleKind: form.scaleKind,
            inputMode: 'direct',
            [limitKey]: parseNumber(
              form.scaleKind === 'numeric' ? form.maxScore : form.totalQuestions,
            ),
          }
        return {
          scaleKind: form.scaleKind,
          inputMode: 'components',
          showComponents: form.showComponents,
          components: form.components.map((item) => ({
            name: item.name,
            [limitKey]: parseNumber(item.limit),
          })),
        }
      }
      case 'letter':
        return { scaleKind: 'letter', inputMode: 'direct', levels: form.levels }
      case 'ielts': {
        const skills = IELTS_SKILLS.filter((code) => form.skills[code].enabled).map((code) => {
          const skill = form.skills[code]
          const counted = (code === 'L' || code === 'R') && skill.inputMode === 'detailed'
          return counted
            ? { code, inputMode: skill.inputMode, maxQuestions: parseNumber(skill.maxQuestions) }
            : { code, inputMode: skill.inputMode }
        })
        const detailed = skills.some((skill) => skill.inputMode === 'detailed')
        return { scaleKind: 'ielts', showComponents: detailed && form.showComponents, skills }
      }
    }
  }

  const parsed = computed(() => GradingConfigInput.safeParse(buildConfig()))
  /** Field paths with a problem, highlighted after the first save attempt. */
  const problems = computed(
    () =>
      new Set(
        parsed.value.success ? [] : parsed.value.error.issues.map((issue) => issue.path.join('.')),
      ),
  )
  /** The display option has something to show in the current form. */
  const hasDetails = computed(() =>
    form.scaleKind === 'ielts'
      ? IELTS_SKILLS.some(
          (code) => form.skills[code].enabled && form.skills[code].inputMode === 'detailed',
        )
      : (form.scaleKind === 'numeric' || form.scaleKind === 'fraction') &&
        form.inputMode === 'components',
  )

  return { form, reset, buildConfig, parsed, problems, hasDetails }
}

export type GradingForm = ReturnType<typeof useGradingForm>
