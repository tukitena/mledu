<script setup lang="ts">
import { ClassSummary, type ClassDetail } from '@mledu/contracts/classes'
import { ClassLifecycleImpact } from '@mledu/contracts/enrollments'
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { apiRequest } from '../../app/session'
import { describeError, type DescribedError } from '../../app/errors'
import ModalDialog from '../../components/ModalDialog.vue'
import ErrorAlert from '../../components/ErrorAlert.vue'
import ReopenClassDialog from '../scheduling/ReopenClassDialog.vue'

const props = defineProps<{ klass: ClassDetail }>()
const emit = defineEmits<{ changed: [] }>()
const { t } = useI18n()
type Action = 'close' | 'reopen' | 'delete' | 'restore'
const action = ref<Action | null>(null)
const impact = ref<ClassLifecycleImpact | null>(null)
const reason = ref('')
const error = ref<DescribedError | null>(null)
const busy = ref(false)
const reopening = ref(false)
let sequence = 0
async function open(value: Action) {
  if (value === 'reopen') {
    reopening.value = true
    return
  }
  const current = ++sequence
  action.value = value
  impact.value = null
  error.value = null
  reason.value = ''
  try {
    const result = await apiRequest(`/v1/classes/${props.klass.id}/lifecycle-impact`, {
      schema: ClassLifecycleImpact,
    })
    if (current === sequence) impact.value = result
  } catch (cause) {
    if (current === sequence) error.value = describeError(cause)
  }
}
function close() {
  if (!busy.value) {
    action.value = null
    sequence++
  }
}
async function submit() {
  if (!action.value || !impact.value || busy.value) return
  busy.value = true
  error.value = null
  try {
    await apiRequest(`/v1/classes/${props.klass.id}/${action.value}`, {
      method: 'POST',
      schema: ClassSummary,
      body: {
        expectedVersion: props.klass.rowVersion,
        ...(['close', 'delete'].includes(action.value) ? { reason: reason.value } : {}),
      },
    })
    action.value = null
    emit('changed')
  } catch (cause) {
    error.value = describeError(cause)
  } finally {
    busy.value = false
  }
}
function onReopened() {
  reopening.value = false
  emit('changed')
}
</script>
<template>
  <ReopenClassDialog
    v-if="reopening"
    :class-id="klass.id"
    :expected-version="klass.rowVersion"
    @close="reopening = false"
    @saved="onReopened"
  />
  <div class="d-flex flex-wrap gap-2">
    <template v-if="!klass.deleted">
      <button
        v-if="klass.adminState === 'open'"
        type="button"
        class="btn btn-outline-secondary"
        data-testid="class-close"
        @click="open('close')"
      >
        {{ t('enrollments.lifecycle.close') }}
      </button>
      <button
        v-else
        type="button"
        class="btn btn-outline-primary"
        data-testid="class-reopen"
        @click="open('reopen')"
      >
        {{ t('enrollments.lifecycle.reopen') }}
      </button>
      <button
        type="button"
        class="btn btn-outline-danger"
        data-testid="class-delete"
        @click="open('delete')"
      >
        {{ t('enrollments.lifecycle.delete') }}
      </button>
    </template>
    <button
      v-else
      type="button"
      class="btn btn-outline-primary"
      data-testid="class-restore"
      @click="open('restore')"
    >
      {{ t('enrollments.lifecycle.restore') }}
    </button>
    <ModalDialog v-if="action" :title="t(`enrollments.lifecycle.${action}`)" @close="close">
      <ErrorAlert :error="error" />
      <p class="fw-semibold">{{ klass.name }}</p>
      <p>{{ t(`enrollments.lifecycleHint.${action}`) }}</p>
      <p v-if="impact" class="small">
        {{
          t('enrollments.impact', {
            active: impact.activeParticipations,
            future: impact.futureParticipations,
          })
        }}
        {{ t('enrollments.assignmentImpact', { count: impact.activeAssignments }) }}
      </p>
      <p v-else-if="!error">{{ t('common.loading') }}</p>
      <template v-if="action === 'close' || action === 'delete'"
        ><label for="lifecycle-reason" class="form-label">{{ t('accounts.reason') }}</label
        ><textarea
          id="lifecycle-reason"
          v-model="reason"
          class="form-control"
          maxlength="1000"
          rows="3"
        ></textarea>
      </template>
      <template #footer
        ><button type="button" class="btn btn-outline-secondary" :disabled="busy" @click="close">
          {{ t('common.cancel') }}</button
        ><button
          type="button"
          class="btn"
          :class="action === 'delete' ? 'btn-danger' : 'btn-primary'"
          :disabled="busy || !impact || (['close', 'delete'].includes(action) && !reason.trim())"
          data-testid="lifecycle-submit"
          @click="submit"
        >
          {{ t(busy ? 'common.saving' : 'common.confirm') }}
        </button></template
      >
    </ModalDialog>
  </div>
</template>
