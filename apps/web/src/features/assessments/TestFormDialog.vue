<script setup lang="ts">
import { ClassTest, TestTemplate } from '@mledu/contracts/assessments'
import type { ClassDetail } from '@mledu/contracts/classes'
import { computed, reactive, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { z } from 'zod'
import { describeError, type DescribedError } from '../../app/errors'
import { apiRequest } from '../../app/session'
import DateInput from '../../components/DateInput.vue'
import ErrorAlert from '../../components/ErrorAlert.vue'
import ModalDialog from '../../components/ModalDialog.vue'
import GradingConfigEditor from './GradingConfigEditor.vue'
import { useGradingForm } from './gradingForm'
import { configSummary } from './labels'

// Test editor (TEST-05). Same Metis modal as the template editor. Three modes:
// create (information + configuration from scratch or copied from a template),
// info (name/date/description only) and config (a new snapshot). Choosing a
// template copies its current version into the form; the copy may be adjusted
// and never writes back to the library (TEST-02).
const props = defineProps<{
  klass: ClassDetail
  mode: 'create' | 'info' | 'config'
  test: ClassTest | null
  canChangeDisplay: boolean
}>()
const emit = defineEmits<{ close: []; saved: [test: ClassTest] }>()
const { t, locale } = useI18n()

const KEEP = 'keep'
const today = () => new Date(Date.now() + 7 * 3600_000).toISOString().slice(0, 10)
const defaultDate = () => {
  const day = today()
  return day < props.klass.startDate
    ? props.klass.startDate
    : day > props.klass.endDate
      ? props.klass.endDate
      : day
}

const grading = useGradingForm(props.test?.config)
const form = reactive({
  name: props.test?.name ?? '',
  testOn: (props.test?.testOn ?? defaultDate()) as string | null,
  description: props.test?.description ?? '',
})
/** '' = own configuration, KEEP = current source of the test, else a template id. */
const templateChoice = ref(props.test?.source ? KEEP : '')
const templates = ref<TestTemplate[] | null>(null)
const busy = ref(false)
const error = ref<DescribedError | null>(null)
const attempted = ref(false)
const showLocked = computed(() => props.mode === 'config' && !props.canChangeDisplay)

if (props.mode !== 'info') {
  apiRequest(`/v1/classes/${props.klass.id}/test-templates`, { schema: z.array(TestTemplate) })
    .then((rows) => (templates.value = rows))
    .catch((cause: unknown) => (error.value = describeError(cause)))
}

const chosenTemplate = computed(
  () => templates.value?.find((item) => item.id === templateChoice.value) ?? null,
)

function onTemplateChange() {
  const template = chosenTemplate.value
  if (!template) return
  grading.reset(template.config)
  // Picking a template never changes the display option for people without that right.
  if (showLocked.value && props.test) grading.form.showComponents = props.test.showComponents
}

const sourceVersionId = computed(() =>
  templateChoice.value === KEEP
    ? (props.test?.source?.templateVersionId ?? null)
    : (chosenTemplate.value?.currentVersionId ?? null),
)

const nameValid = computed(() => form.name.trim().length > 0 && form.name.trim().length <= 200)
const dateValid = computed(
  () => !!form.testOn && form.testOn >= props.klass.startDate && form.testOn <= props.klass.endDate,
)
const valid = computed(() => {
  if (props.mode === 'config') return grading.parsed.value.success
  const info = nameValid.value && dateValid.value
  return props.mode === 'info' ? info : info && grading.parsed.value.success
})

const title = computed(() =>
  props.mode === 'create'
    ? t('tests.create')
    : t(props.mode === 'info' ? 'tests.editInfoTitle' : 'tests.configTitle', {
        name: props.test?.name,
      }),
)

async function submit() {
  attempted.value = true
  if (!valid.value) return
  busy.value = true
  error.value = null
  const info = { name: form.name, testOn: form.testOn, description: form.description }
  try {
    const saved =
      props.mode === 'create'
        ? await apiRequest(`/v1/classes/${props.klass.id}/tests`, {
            method: 'POST',
            body: {
              ...info,
              config: grading.buildConfig(),
              sourceTemplateVersionId: sourceVersionId.value,
            },
            schema: ClassTest,
          })
        : props.mode === 'info'
          ? await apiRequest(`/v1/tests/${props.test!.id}`, {
              method: 'PUT',
              body: { ...info, expectedVersion: props.test!.rowVersion },
              schema: ClassTest,
            })
          : await apiRequest(`/v1/tests/${props.test!.id}/config`, {
              method: 'PUT',
              body: {
                config: grading.buildConfig(),
                sourceTemplateVersionId: sourceVersionId.value,
                expectedVersion: props.test!.rowVersion,
              },
              schema: ClassTest,
            })
    emit('saved', saved)
  } catch (cause) {
    error.value = describeError(cause)
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <ModalDialog :wide="mode !== 'info'" :title="title" @close="emit('close')">
    <ErrorAlert :error="error" />
    <p v-if="mode === 'config'" class="small text-body-secondary">{{ t('tests.configHint') }}</p>
    <div
      v-if="mode === 'config' && test && test.resultCount > 0"
      class="alert alert-warning small"
      data-testid="test-config-reentry"
    >
      {{ t('tests.reentryWarning', { n: test.resultCount }) }}
    </div>
    <form id="test-form" novalidate @submit.prevent="submit">
      <div class="row g-3">
        <template v-if="mode !== 'config'">
          <div class="col-md-8">
            <label class="form-label" for="test-name">{{ t('tests.name') }}</label>
            <input
              id="test-name"
              v-model="form.name"
              class="form-control"
              :class="{ 'is-invalid': attempted && !nameValid }"
              maxlength="200"
              required
              data-testid="test-name"
            />
            <div class="invalid-feedback">{{ t('tests.nameRequired') }}</div>
          </div>
          <div class="col-md-4">
            <label class="form-label" for="test-date">{{ t('tests.testOn') }}</label>
            <DateInput
              id="test-date"
              v-model="form.testOn"
              class="form-control"
              :class="{ 'is-invalid': attempted && !dateValid }"
              :min="klass.startDate"
              :max="klass.endDate"
              required
              data-testid="test-date"
            />
            <div class="invalid-feedback">{{ t('tests.dateHint') }}</div>
          </div>
          <div class="col-12">
            <label class="form-label" for="test-description">
              {{ t('tests.description') }}
              <span class="text-body-secondary small">({{ t('common.optional') }})</span>
            </label>
            <textarea
              id="test-description"
              v-model="form.description"
              class="form-control"
              rows="2"
              maxlength="5000"
            ></textarea>
          </div>
        </template>

        <template v-if="mode !== 'info'">
          <div class="col-12">
            <label class="form-label" for="test-template">{{ t('tests.template') }}</label>
            <select
              id="test-template"
              v-model="templateChoice"
              class="form-select"
              data-testid="test-template"
              @change="onTemplateChange"
            >
              <option value="">{{ t('tests.ownConfig') }}</option>
              <option v-if="test?.source" :value="KEEP">
                {{
                  t('tests.keepSource', {
                    name: test.source.name,
                    revision: test.source.revision,
                  })
                }}
              </option>
              <option v-for="item in templates ?? []" :key="item.id" :value="item.id">
                {{ item.name }} · v{{ item.revision }} ·
                {{ t(`testTemplates.scale.${item.config.scaleKind}`) }}
              </option>
            </select>
            <div class="form-text">
              {{
                chosenTemplate
                  ? t('tests.templateCopied', {
                      summary: configSummary(chosenTemplate.config, t, locale),
                    })
                  : t('tests.templateHint')
              }}
            </div>
          </div>
          <GradingConfigEditor
            :grading="grading"
            :attempted="attempted"
            :show-locked="showLocked"
            :show-hint="showLocked ? t('tests.showLocked') : t('tests.showHint')"
          />
        </template>
      </div>
    </form>
    <template #footer>
      <button type="button" class="btn btn-outline-secondary" @click="emit('close')">
        {{ t('common.cancel') }}
      </button>
      <button
        type="submit"
        form="test-form"
        class="btn btn-primary"
        :disabled="busy"
        data-testid="test-submit"
      >
        {{ busy ? t('common.saving') : t('common.save') }}
      </button>
    </template>
  </ModalDialog>
</template>
