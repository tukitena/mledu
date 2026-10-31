<script setup lang="ts">
import {
  IELTS_SKILLS,
  MAX_COMPONENTS,
  MAX_LETTER_LEVELS,
  type ScaleKind,
} from '@mledu/contracts/assessments'
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { parseNumber, type GradingForm } from './gradingForm'
import { formatScore } from './labels'

// Grading configuration fields (TEST-01/02/04), used inside the `row g-3` grid
// of the template and test dialogs (Metis "Add New Product" modal: plain labels,
// repeated rows as input groups). showLocked keeps the display option read-only
// for people who may not change it (assistants, TEST-04).
const props = defineProps<{
  grading: GradingForm
  attempted: boolean
  showLocked?: boolean
  showHint?: string
}>()
const { t, locale } = useI18n()
const { form, parsed, problems, hasDetails } = props.grading

const SCALES: ScaleKind[] = ['numeric', 'fraction', 'letter', 'ielts']
const problem = (path: string) => props.attempted && problems.value.has(path)

const componentTotal = computed(() => {
  const values = form.components.map((item) => parseNumber(item.limit))
  if (values.some((value) => !Number.isFinite(value))) return null
  return form.scaleKind === 'numeric'
    ? values.reduce((sum, value) => sum + Math.round(value * 100), 0) / 100
    : values.reduce((sum, value) => sum + value, 0)
})

function move<T>(list: T[], index: number, offset: number) {
  const [item] = list.splice(index, 1)
  list.splice(index + offset, 0, item!)
}
</script>

<template>
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
          {{ t('testTemplates.components', { n: form.components.length, max: MAX_COMPONENTS }) }}
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
            t(form.scaleKind === 'numeric' ? 'testTemplates.maxScore' : 'testTemplates.questions')
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
        <i class="bi bi-plus-lg me-1" aria-hidden="true"></i>{{ t('testTemplates.addComponent') }}
      </button>
    </div>
    <div v-if="form.inputMode === 'components'" class="col-12">
      <div class="form-check form-switch">
        <input
          id="tt-show-components"
          v-model="form.showComponents"
          :disabled="showLocked"
          class="form-check-input"
          type="checkbox"
          role="switch"
        />
        <label class="form-check-label" for="tt-show-components">
          <strong>{{ t('testTemplates.showComponents') }}</strong>
          <small class="d-block text-body-secondary">
            {{ showHint ?? t('testTemplates.showComponentsHint') }}
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
                v-if="(code === 'L' || code === 'R') && form.skills[code].inputMode === 'detailed'"
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
        :disabled="!hasDetails || showLocked"
      />
      <label class="form-check-label" for="tt-ielts-show">
        <strong>{{ t('testTemplates.showComponents') }}</strong>
        <small class="d-block text-body-secondary">{{ t('testTemplates.ieltsShowHint') }}</small>
      </label>
    </div>
    <p class="small text-body-secondary mt-2 mb-0">{{ t('testTemplates.ieltsFormula') }}</p>
  </div>
</template>
