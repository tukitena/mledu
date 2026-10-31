<script setup lang="ts">
import {
  DEFAULT_LETTER_LEVELS,
  IELTS_SKILLS,
  MAX_COMPONENTS,
  MAX_LETTER_LEVELS,
  TestTemplate,
  TestTemplateConfigInput,
  type IeltsSkill,
  type ScaleKind,
  type TestTemplateConfig,
} from '@mledu/contracts/assessments'
import { computed, reactive, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { describeError, type DescribedError } from '../../app/errors'
import { apiRequest } from '../../app/session'
import ErrorAlert from '../../components/ErrorAlert.vue'
import ModalDialog from '../../components/ModalDialog.vue'
import { formatScore } from './labels'

// Template editor (TEST-01/02/04). Mirrors the Metis "Add New Product" modal:
// modal-lg, `row g-3` grid, plain labels; repeated rows use input groups. The
// contract schema checks the form; the API/DB validate again and normalize.
const props = defineProps<{ template: TestTemplate | null }>()
const emit = defineEmits<{ close: []; saved: [template: TestTemplate] }>()
const { t, locale } = useI18n()

interface SkillState {
  enabled: boolean
  inputMode: 'direct' | 'detailed'
  maxQuestions: string
}

const SCALES: ScaleKind[] = ['numeric', 'fraction', 'letter', 'ielts']
const input = (value: number | undefined) =>
  value === undefined ? '' : String(value).replace('.', locale.value === 'vi' ? ',' : '.')
/** Accepts 8,25 and 8.25; anything that is not a plain number stays invalid. */
const parseNumber = (value: string) => {
  const text = value.trim().replace(',', '.')
  return /^-?\d+(\.\d+)?$/.test(text) ? Number(text) : Number.NaN
}

function initialState(config: TestTemplateConfig | undefined) {
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
  const state = {
    scaleKind: (config?.scaleKind ?? 'numeric') as ScaleKind,
    inputMode: 'direct' as 'direct' | 'components',
    maxScore: '10',
    totalQuestions: '',
    showComponents: false,
    components: [{ name: '', limit: '' }],
    levels: DEFAULT_LETTER_LEVELS.map((label): { label: string } => ({ label })),
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

const form = reactive({
  name: props.template?.name ?? '',
  description: props.template?.description ?? '',
  ...initialState(props.template?.config),
})
const busy = ref(false)
const error = ref<DescribedError | null>(null)
const attempted = ref(false)

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

const parsed = computed(() => TestTemplateConfigInput.safeParse(buildConfig()))
/** Field paths with a problem, highlighted after the first save attempt. */
const problems = computed(
  () =>
    new Set(
      parsed.value.success ? [] : parsed.value.error.issues.map((issue) => issue.path.join('.')),
    ),
)
const problem = (path: string) => attempted.value && problems.value.has(path)
const nameValid = computed(() => form.name.trim().length > 0 && form.name.trim().length <= 200)
const valid = computed(() => nameValid.value && parsed.value.success)

const componentTotal = computed(() => {
  const values = form.components.map((item) => parseNumber(item.limit))
  if (values.some((value) => !Number.isFinite(value))) return null
  return form.scaleKind === 'numeric'
    ? values.reduce((sum, value) => sum + Math.round(value * 100), 0) / 100
    : values.reduce((sum, value) => sum + value, 0)
})
const ieltsDetailed = computed(() =>
  IELTS_SKILLS.some(
    (code) => form.skills[code].enabled && form.skills[code].inputMode === 'detailed',
  ),
)

function move<T>(list: T[], index: number, offset: number) {
  const [item] = list.splice(index, 1)
  list.splice(index + offset, 0, item!)
}

async function submit() {
  attempted.value = true
  if (!valid.value) return
  busy.value = true
  error.value = null
  try {
    const body = {
      name: form.name,
      description: form.description,
      config: buildConfig(),
    }
    const saved = props.template
      ? await apiRequest(`/v1/test-templates/${props.template.id}`, {
          method: 'PUT',
          body: { ...body, expectedVersion: props.template.rowVersion },
          schema: TestTemplate,
        })
      : await apiRequest('/v1/test-templates', { method: 'POST', body, schema: TestTemplate })
    emit('saved', saved)
  } catch (cause) {
    error.value = describeError(cause)
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <ModalDialog
    wide
    :title="
      template ? t('testTemplates.editTitle', { name: template.name }) : t('testTemplates.create')
    "
    @close="emit('close')"
  >
    <ErrorAlert :error="error" />
    <p v-if="template" class="small text-body-secondary">{{ t('testTemplates.versionHint') }}</p>
    <form id="test-template-form" novalidate @submit.prevent="submit">
      <div class="row g-3">
        <div class="col-12">
          <label class="form-label" for="tt-name">{{ t('testTemplates.name') }}</label>
          <input
            id="tt-name"
            v-model="form.name"
            class="form-control"
            :class="{ 'is-invalid': attempted && !nameValid }"
            maxlength="200"
            required
          />
        </div>
        <div class="col-12">
          <label class="form-label" for="tt-description">
            {{ t('testTemplates.description') }}
            <span class="text-body-secondary small">({{ t('common.optional') }})</span>
          </label>
          <textarea
            id="tt-description"
            v-model="form.description"
            class="form-control"
            rows="2"
            maxlength="5000"
          ></textarea>
        </div>
        <div class="col-md-6">
          <label class="form-label" for="tt-scale">{{ t('testTemplates.scaleKind') }}</label>
          <select id="tt-scale" v-model="form.scaleKind" class="form-select" data-testid="tt-scale">
            <option v-for="scale in SCALES" :key="scale" :value="scale">
              {{ t(`testTemplates.scale.${scale}`) }}
            </option>
          </select>
        </div>

        <!-- Numeric / fraction (TEST-01/04) -->
        <template v-if="form.scaleKind === 'numeric' || form.scaleKind === 'fraction'">
          <div class="col-md-6">
            <label class="form-label" for="tt-mode">{{ t('testTemplates.inputMode') }}</label>
            <select id="tt-mode" v-model="form.inputMode" class="form-select" data-testid="tt-mode">
              <option value="direct">{{ t('testTemplates.mode.direct') }}</option>
              <option value="components">{{ t('testTemplates.mode.components') }}</option>
            </select>
          </div>
          <div v-if="form.inputMode === 'direct'" class="col-md-6">
            <template v-if="form.scaleKind === 'numeric'">
              <label class="form-label" for="tt-max">{{ t('testTemplates.maxScore') }}</label>
              <input
                id="tt-max"
                v-model="form.maxScore"
                class="form-control"
                inputmode="decimal"
                :class="{ 'is-invalid': problem('maxScore') }"
                data-testid="tt-max-score"
              />
              <div class="invalid-feedback">{{ t('testTemplates.scoreHint') }}</div>
            </template>
            <template v-else>
              <label class="form-label" for="tt-questions">
                {{ t('testTemplates.totalQuestions') }}
              </label>
              <input
                id="tt-questions"
                v-model="form.totalQuestions"
                class="form-control"
                inputmode="numeric"
                :class="{ 'is-invalid': problem('totalQuestions') }"
                data-testid="tt-total-questions"
              />
              <div class="invalid-feedback">{{ t('testTemplates.countHint') }}</div>
            </template>
          </div>
          <div v-else class="col-12">
            <div class="d-flex align-items-center justify-content-between mb-2">
              <span class="form-label mb-0">
                {{
                  t('testTemplates.components', { n: form.components.length, max: MAX_COMPONENTS })
                }}
              </span>
              <span class="small text-body-secondary" data-testid="tt-component-total">
                {{
                  componentTotal === null
                    ? ''
                    : t(
                        form.scaleKind === 'numeric'
                          ? 'testTemplates.totalScore'
                          : 'testTemplates.totalCount',
                        { n: formatScore(componentTotal, locale) },
                      )
                }}
              </span>
            </div>
            <div
              v-for="(item, index) in form.components"
              :key="index"
              class="input-group mb-2"
              data-testid="tt-component"
            >
              <span class="input-group-text">{{ index + 1 }}</span>
              <input
                v-model="item.name"
                class="form-control w-50"
                maxlength="200"
                :placeholder="t('testTemplates.componentName')"
                :aria-label="`${t('testTemplates.componentName')} ${index + 1}`"
                :class="{ 'is-invalid': problem(`components.${index}.name`) }"
              />
              <input
                v-model="item.limit"
                class="form-control"
                :inputmode="form.scaleKind === 'numeric' ? 'decimal' : 'numeric'"
                :placeholder="
                  t(
                    form.scaleKind === 'numeric'
                      ? 'testTemplates.maxScore'
                      : 'testTemplates.questions',
                  )
                "
                :aria-label="`${t(form.scaleKind === 'numeric' ? 'testTemplates.maxScore' : 'testTemplates.questions')} ${index + 1}`"
                :class="{
                  'is-invalid': problem(
                    `components.${index}.${form.scaleKind === 'numeric' ? 'maxScore' : 'totalQuestions'}`,
                  ),
                }"
              />
              <button
                type="button"
                class="btn btn-outline-secondary"
                :disabled="form.components.length === 1"
                :aria-label="t('testTemplates.remove')"
                @click="form.components.splice(index, 1)"
              >
                <i class="bi bi-x-lg" aria-hidden="true"></i>
              </button>
            </div>
            <div v-if="attempted && !parsed.success" class="small text-danger mb-2">
              {{ t('testTemplates.componentsHint') }}
            </div>
            <button
              type="button"
              class="btn btn-sm btn-outline-primary"
              :disabled="form.components.length >= MAX_COMPONENTS"
              data-testid="tt-add-component"
              @click="form.components.push({ name: '', limit: '' })"
            >
              <i class="bi bi-plus-lg me-1" aria-hidden="true"></i
              >{{ t('testTemplates.addComponent') }}
            </button>
          </div>
          <div v-if="form.inputMode === 'components'" class="col-12">
            <div class="form-check form-switch">
              <input
                id="tt-show-components"
                v-model="form.showComponents"
                class="form-check-input"
                type="checkbox"
                role="switch"
              />
              <label class="form-check-label" for="tt-show-components">
                <strong>{{ t('testTemplates.showComponents') }}</strong>
                <small class="d-block text-body-secondary">
                  {{ t('testTemplates.showComponentsHint') }}
                </small>
              </label>
            </div>
          </div>
        </template>

        <!-- Letter levels (TEST-02) -->
        <div v-else-if="form.scaleKind === 'letter'" class="col-12">
          <span class="form-label d-block">
            {{ t('testTemplates.levels', { n: form.levels.length, max: MAX_LETTER_LEVELS }) }}
          </span>
          <div
            v-for="(level, index) in form.levels"
            :key="index"
            class="input-group mb-2"
            data-testid="tt-level"
          >
            <span class="input-group-text">{{ index + 1 }}</span>
            <input
              v-model="level.label"
              class="form-control"
              maxlength="100"
              :aria-label="`${t('testTemplates.levelLabel')} ${index + 1}`"
              :class="{
                'is-invalid': problem(`levels.${index}.name`) || problem(`levels.${index}.label`),
              }"
            />
            <button
              type="button"
              class="btn btn-outline-secondary"
              :disabled="index === 0"
              :aria-label="t('testTemplates.moveUp')"
              @click="move(form.levels, index, -1)"
            >
              <i class="bi bi-arrow-up" aria-hidden="true"></i>
            </button>
            <button
              type="button"
              class="btn btn-outline-secondary"
              :disabled="index === form.levels.length - 1"
              :aria-label="t('testTemplates.moveDown')"
              @click="move(form.levels, index, 1)"
            >
              <i class="bi bi-arrow-down" aria-hidden="true"></i>
            </button>
            <button
              type="button"
              class="btn btn-outline-secondary"
              :disabled="form.levels.length === 1"
              :aria-label="t('testTemplates.remove')"
              @click="form.levels.splice(index, 1)"
            >
              <i class="bi bi-x-lg" aria-hidden="true"></i>
            </button>
          </div>
          <div v-if="attempted && !parsed.success" class="small text-danger mb-2">
            {{ t('testTemplates.levelsHint') }}
          </div>
          <button
            type="button"
            class="btn btn-sm btn-outline-primary"
            :disabled="form.levels.length >= MAX_LETTER_LEVELS"
            data-testid="tt-add-level"
            @click="form.levels.push({ label: '' })"
          >
            <i class="bi bi-plus-lg me-1" aria-hidden="true"></i>{{ t('testTemplates.addLevel') }}
          </button>
        </div>

        <!-- IELTS (TEST-01): skills and per-skill mode; the formula is fixed. -->
        <div v-else class="col-12">
          <span class="form-label d-block">{{ t('testTemplates.skills') }}</span>
          <div class="table-responsive">
            <table class="table align-middle mb-2 ielts-skills">
              <thead>
                <tr>
                  <th scope="col">{{ t('testTemplates.skill') }}</th>
                  <th scope="col">{{ t('testTemplates.inputMode') }}</th>
                  <th scope="col">{{ t('testTemplates.maxQuestions') }}</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="code in IELTS_SKILLS" :key="code" :data-testid="`tt-skill-${code}`">
                  <td>
                    <div class="form-check mb-0">
                      <input
                        :id="`tt-skill-${code}`"
                        v-model="form.skills[code].enabled"
                        class="form-check-input"
                        type="checkbox"
                      />
                      <label class="form-check-label" :for="`tt-skill-${code}`">
                        {{ t(`testTemplates.skillName.${code}`) }}
                      </label>
                    </div>
                  </td>
                  <td>
                    <select
                      v-model="form.skills[code].inputMode"
                      class="form-select form-select-sm"
                      :disabled="!form.skills[code].enabled"
                      :aria-label="`${t('testTemplates.inputMode')} ${code}`"
                    >
                      <option value="direct">{{ t('testTemplates.skillMode.direct') }}</option>
                      <option value="detailed">
                        {{
                          t(
                            `testTemplates.skillMode.detailed${code === 'L' || code === 'R' ? 'Count' : 'Criteria'}`,
                          )
                        }}
                      </option>
                    </select>
                  </td>
                  <td>
                    <input
                      v-if="
                        (code === 'L' || code === 'R') && form.skills[code].inputMode === 'detailed'
                      "
                      v-model="form.skills[code].maxQuestions"
                      class="form-control form-control-sm"
                      inputmode="numeric"
                      :disabled="!form.skills[code].enabled"
                      :aria-label="`${t('testTemplates.maxQuestions')} ${code}`"
                    />
                    <span v-else class="small text-body-secondary">—</span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <div v-if="attempted && !parsed.success" class="small text-danger mb-2">
            {{ t('testTemplates.skillsHint') }}
          </div>
          <div class="form-check form-switch">
            <input
              id="tt-ielts-show"
              v-model="form.showComponents"
              class="form-check-input"
              type="checkbox"
              role="switch"
              :disabled="!ieltsDetailed"
            />
            <label class="form-check-label" for="tt-ielts-show">
              <strong>{{ t('testTemplates.showComponents') }}</strong>
              <small class="d-block text-body-secondary">{{
                t('testTemplates.ieltsShowHint')
              }}</small>
            </label>
          </div>
          <p class="small text-body-secondary mt-2 mb-0">{{ t('testTemplates.ieltsFormula') }}</p>
        </div>
      </div>
    </form>
    <template #footer>
      <button type="button" class="btn btn-outline-secondary" @click="emit('close')">
        {{ t('common.cancel') }}
      </button>
      <button
        type="submit"
        form="test-template-form"
        class="btn btn-primary"
        :disabled="busy"
        data-testid="tt-submit"
      >
        {{ busy ? t('common.saving') : t('common.save') }}
      </button>
    </template>
  </ModalDialog>
</template>
