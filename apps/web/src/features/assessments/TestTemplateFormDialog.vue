<script setup lang="ts">
import { TestTemplate } from '@mledu/contracts/assessments'
import { computed, reactive, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { describeError, type DescribedError } from '../../app/errors'
import { apiRequest } from '../../app/session'
import ErrorAlert from '../../components/ErrorAlert.vue'
import ModalDialog from '../../components/ModalDialog.vue'
import GradingConfigEditor from './GradingConfigEditor.vue'
import { useGradingForm } from './gradingForm'

// Template editor (TEST-01/02/04). Mirrors the Metis "Add New Product" modal:
// modal-lg, `row g-3` grid, plain labels. The grading fields are shared with
// the test editor; the API/DB validate again and normalize.
const props = defineProps<{ template: TestTemplate | null }>()
const emit = defineEmits<{ close: []; saved: [template: TestTemplate] }>()
const { t } = useI18n()

const grading = useGradingForm(props.template?.config)
const form = reactive({
  name: props.template?.name ?? '',
  description: props.template?.description ?? '',
})
const busy = ref(false)
const error = ref<DescribedError | null>(null)
const attempted = ref(false)

const nameValid = computed(() => form.name.trim().length > 0 && form.name.trim().length <= 200)
const valid = computed(() => nameValid.value && grading.parsed.value.success)

async function submit() {
  attempted.value = true
  if (!valid.value) return
  busy.value = true
  error.value = null
  try {
    const body = {
      name: form.name,
      description: form.description,
      config: grading.buildConfig(),
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
        <GradingConfigEditor :grading="grading" :attempted="attempted" />
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
