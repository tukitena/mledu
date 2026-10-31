<script setup lang="ts">
import {
  TestResults,
  type ClassTest,
  type ResultEntry,
  type TestResult,
  type TestResultRow,
} from '@mledu/contracts/assessments'
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { describeError, type DescribedError } from '../../app/errors'
import { apiRequest } from '../../app/session'
import ErrorAlert from '../../components/ErrorAlert.vue'
import ModalDialog from '../../components/ModalDialog.vue'
import { formatIsoDate } from '../../lib/format'
import { parseNumber } from './gradingForm'
import { configSummary, formatScore } from './labels'

// Results of one test (TEST-01/04/05), entered on its current configuration,
// in the same table-in-a-wide-dialog layout as attendance. Only changed rows
// are sent; the database computes totals and checks every value again.
const props = defineProps<{ test: ClassTest }>()
const emit = defineEmits<{ close: []; saved: [] }>()
const { t, locale } = useI18n()

interface Fields {
  absent: boolean
  value: string
  level: string
  parts: Record<string, string>
}
interface Row extends Fields {
  student: TestResultRow
}

const data = ref<TestResults | null>(null)
const rows = ref<Row[]>([])
const error = ref<DescribedError | null>(null)
const busy = ref(false)
const attempted = ref(false)
const config = computed(() => data.value?.test.config ?? props.test.config)
const components = computed(() =>
  config.value.scaleKind === 'numeric' || config.value.scaleKind === 'fraction'
    ? config.value.inputMode === 'components'
      ? config.value.components
      : []
    : [],
)
const supported = computed(() => config.value.scaleKind !== 'ielts')
const editable = computed(() => !!data.value?.canEdit && supported.value)

const text = (value: number | null | undefined) =>
  value === null || value === undefined ? '' : formatScore(value, locale.value)

function fieldsOf(result: TestResult | null): Fields {
  return {
    absent: !!result?.absent,
    value: text(result?.score ?? result?.correctAnswers),
    level: result?.level ?? '',
    parts: Object.fromEntries(
      components.value.map((part) => [part.code, text(result?.components[part.code])]),
    ),
  }
}

function update(value: TestResults) {
  data.value = value
  rows.value = value.students.map((student) => ({ student, ...fieldsOf(student.result) }))
}

onMounted(async () => {
  try {
    update(await apiRequest(`/v1/tests/${props.test.id}/results`, { schema: TestResults }))
  } catch (cause) {
    error.value = describeError(cause)
  }
})

/** NaN when the text is not a valid value for that limit (never rounded or clipped). */
function valueOf(input: string, limit: { maxScore?: number; totalQuestions?: number }) {
  if (!input.trim()) return null
  const value = parseNumber(input)
  if (!Number.isFinite(value) || value < 0) return Number.NaN
  if (limit.maxScore !== undefined)
    return /^\d+([.,]\d{1,2})?$/.test(input.trim()) && value <= limit.maxScore ? value : Number.NaN
  return Number.isInteger(value) && value <= (limit.totalQuestions ?? 0) ? value : Number.NaN
}

const directLimit = computed(() =>
  config.value.scaleKind === 'numeric'
    ? { maxScore: config.value.maxScore }
    : config.value.scaleKind === 'fraction'
      ? { totalQuestions: config.value.totalQuestions }
      : {},
)
const partLimit = (code: string) => {
  const part = components.value.find((item) => item.code === code)
  return part && 'maxScore' in part
    ? { maxScore: part.maxScore }
    : { totalQuestions: part && 'totalQuestions' in part ? part.totalQuestions : 0 }
}

/** The entry a row stands for: null = no result, undefined = invalid input. */
function entryOf(row: Fields): ResultEntry | null | undefined {
  if (row.absent) return { absent: true }
  const kind = config.value.scaleKind
  if (kind === 'letter') return row.level ? { absent: false, level: row.level } : null
  if (components.value.length) {
    const values: Record<string, number> = {}
    for (const part of components.value) {
      const value = valueOf(row.parts[part.code] ?? '', partLimit(part.code))
      if (Number.isNaN(value)) return undefined
      if (value !== null) values[part.code] = value
    }
    return Object.keys(values).length ? { absent: false, components: values } : null
  }
  const value = valueOf(row.value, directLimit.value)
  if (Number.isNaN(value)) return undefined
  if (value === null) return null
  return kind === 'numeric'
    ? { absent: false, score: value }
    : { absent: false, correctAnswers: value }
}

const savedEntry = (result: TestResult | null) => (result ? entryOf(fieldsOf(result)) : null)

const key = (entry: ResultEntry | null | undefined) =>
  entry === undefined ? 'invalid' : JSON.stringify(entry)
const changed = (row: Row) => key(entryOf(row)) !== key(savedEntry(row.student.result))
const invalid = (row: Row) => entryOf(row) === undefined
const invalidPart = (row: Row, code: string) =>
  Number.isNaN(valueOf(row.parts[code] ?? '', partLimit(code)))
const invalidValue = (row: Row) => Number.isNaN(valueOf(row.value, directLimit.value))
const dirtyCount = computed(() => rows.value.filter(changed).length)

// Total of the values typed so far; cents avoid binary rounding (1,25 + 2,10 = 3,35).
function total(row: Row) {
  if (row.absent || !components.value.length) return ''
  const entry = entryOf(row)
  if (!entry || !('components' in entry)) return entry === null ? '' : '—'
  const values = Object.values(entry.components).filter((value): value is number => value !== null)
  if (config.value.scaleKind === 'numeric') {
    const cents = values.reduce((sum, value) => sum + Math.round(value * 100), 0)
    return `${formatScore(cents / 100, locale.value)} / ${formatScore(config.value.maxScore, locale.value)}`
  }
  const max = config.value.scaleKind === 'fraction' ? config.value.totalQuestions : 0
  return `${values.reduce((sum, value) => sum + value, 0)}/${max}`
}

type Status = 'published' | 'unsaved' | 'absent' | 'complete' | 'incomplete' | 'empty'
function status(row: Row): Status {
  const result = row.student.result
  if (result?.published) return 'published'
  if (changed(row)) return 'unsaved'
  if (!result) return 'empty'
  if (result.absent) return 'absent'
  return result.complete ? 'complete' : 'incomplete'
}
const statusClass: Record<Status, string> = {
  published: 'bg-primary',
  unsaved: 'bg-warning-subtle text-warning-emphasis',
  absent: 'bg-secondary',
  complete: 'bg-success-subtle text-success-emphasis',
  incomplete: 'bg-info-subtle text-info-emphasis',
  empty: 'text-bg-light border',
}
const locked = (row: Row) => !editable.value || busy.value || !!row.student.result?.published

async function save() {
  attempted.value = true
  error.value = null
  if (!data.value || rows.value.some((row) => changed(row) && invalid(row))) return
  const items = rows.value.filter(changed).map((row) => ({
    studentId: row.student.studentId,
    expectedVersion: row.student.result?.rowVersion ?? null,
    entry: entryOf(row) ?? null,
  }))
  if (!items.length) return
  busy.value = true
  try {
    update(
      await apiRequest(`/v1/tests/${props.test.id}/results`, {
        method: 'PUT',
        schema: TestResults,
        body: { configId: data.value.test.configId, items },
      }),
    )
    attempted.value = false
    emit('saved')
  } catch (cause) {
    error.value = describeError(cause)
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <ModalDialog :title="t('results.title', { name: test.name })" wide @close="emit('close')">
    <ErrorAlert :error="error" />
    <p class="small text-body-secondary mb-2">
      {{ formatIsoDate(test.testOn) }} · {{ t(`testTemplates.scale.${config.scaleKind}`) }} ·
      {{ configSummary(config, t, locale) }}
    </p>
    <div v-if="!supported" class="alert alert-info small" data-testid="results-ielts">
      {{ t('results.ieltsLater') }}
    </div>
    <p v-else class="small text-body-secondary">{{ t('results.hint') }}</p>

    <p v-if="!data && !error" class="text-body-secondary">{{ t('common.loading') }}</p>
    <div v-else-if="data && supported" class="table-responsive results-table-wrap">
      <table class="table align-middle mb-0 results-table" data-testid="results-table">
        <thead>
          <tr>
            <th scope="col">{{ t('results.student') }}</th>
            <th scope="col" class="text-center">{{ t('results.absent') }}</th>
            <th v-for="part in components" :key="part.code" scope="col" class="text-nowrap">
              {{ part.name }}
              <small class="d-block text-body-secondary fw-normal">
                /{{ 'maxScore' in part ? formatScore(part.maxScore, locale) : part.totalQuestions }}
              </small>
            </th>
            <th v-if="components.length" scope="col">{{ t('results.total') }}</th>
            <th v-else scope="col">{{ t('results.result') }}</th>
            <th scope="col">{{ t('results.status') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-if="!rows.length">
            <td :colspan="4 + components.length" class="text-body-secondary">
              {{ t('results.empty') }}
            </td>
          </tr>
          <tr v-for="row in rows" :key="row.student.studentId" :data-student="row.student.fullName">
            <td>
              <div class="fw-medium text-break">{{ row.student.fullName }}</div>
              <small class="text-body-secondary">{{ row.student.code }}</small>
            </td>
            <td class="text-center">
              <input
                v-model="row.absent"
                class="form-check-input"
                type="checkbox"
                :aria-label="`${t('results.absent')}: ${row.student.fullName}`"
                :disabled="locked(row)"
                data-testid="result-absent"
              />
            </td>
            <td v-for="part in components" :key="part.code">
              <input
                v-model="row.parts[part.code]"
                class="form-control form-control-sm result-input"
                :class="{ 'is-invalid': attempted && !row.absent && invalidPart(row, part.code) }"
                inputmode="decimal"
                :aria-label="`${part.name}: ${row.student.fullName}`"
                :disabled="locked(row) || row.absent"
                :data-testid="`result-part-${part.code}`"
              />
            </td>
            <td v-if="components.length" class="text-nowrap small" data-testid="result-total">
              {{ total(row) }}
            </td>
            <td v-else>
              <select
                v-if="config.scaleKind === 'letter'"
                v-model="row.level"
                class="form-select form-select-sm result-select"
                :aria-label="`${t('results.result')}: ${row.student.fullName}`"
                :disabled="locked(row) || row.absent"
                data-testid="result-level"
              >
                <option value="">—</option>
                <option v-for="level in config.levels" :key="level.code" :value="level.code">
                  {{ level.label }}
                </option>
              </select>
              <div v-else class="d-flex align-items-center gap-1">
                <input
                  v-model="row.value"
                  class="form-control form-control-sm result-input"
                  :class="{ 'is-invalid': attempted && !row.absent && invalidValue(row) }"
                  inputmode="decimal"
                  :aria-label="`${t('results.result')}: ${row.student.fullName}`"
                  :disabled="locked(row) || row.absent"
                  data-testid="result-value"
                />
                <span class="small text-body-secondary text-nowrap">
                  /{{
                    config.scaleKind === 'numeric'
                      ? formatScore(config.maxScore, locale)
                      : config.scaleKind === 'fraction'
                        ? config.totalQuestions
                        : ''
                  }}
                </span>
              </div>
            </td>
            <td>
              <span class="badge" :class="statusClass[status(row)]" data-testid="result-status">
                {{ t(`results.statusLabel.${status(row)}`) }}
              </span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <p
      v-if="attempted && rows.some((row) => changed(row) && invalid(row))"
      class="text-danger small mt-2"
    >
      {{ t('results.invalid') }}
    </p>

    <template #footer>
      <span v-if="editable && dirtyCount" class="small text-body-secondary me-auto">
        {{ t('results.unsavedCount', { n: dirtyCount }) }}
      </span>
      <button type="button" class="btn btn-outline-secondary" @click="emit('close')">
        {{ t('common.close') }}
      </button>
      <button
        v-if="editable"
        type="button"
        class="btn btn-primary"
        data-testid="results-save"
        :disabled="busy || !dirtyCount"
        @click="save"
      >
        {{ busy ? t('common.saving') : t('results.save') }}
      </button>
    </template>
  </ModalDialog>
</template>
