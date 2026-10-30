<script setup lang="ts">
import DateInput from '../../components/DateInput.vue'
import {
  AssignableAccount,
  Assignment,
  type ClassDetail,
  type ClassRole,
} from '@mledu/contracts/classes'
import { computed, onMounted, reactive, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { z } from 'zod'
import { describeError, type DescribedError } from '../../app/errors'
import { apiRequest } from '../../app/session'
import ErrorAlert from '../../components/ErrorAlert.vue'
import FloatingAlert from '../../components/FloatingAlert.vue'
import ModalDialog from '../../components/ModalDialog.vue'
import RowActionMenu, { type RowAction } from '../../components/RowActionMenu.vue'
import { formatIsoDate } from '../../lib/format'
import { assignmentBadge } from './labels'

// Staff of a class (CLASS-01/02): many teachers and assistants, each with its
// own dates. Managers add, edit and end assignments; the API enforces overlap
// and date rules.
const props = defineProps<{ klass: ClassDetail; canManage: boolean }>()
const emit = defineEmits<{ changed: [] }>()
const { t } = useI18n()

const items = ref<Assignment[]>([])
const loading = ref(false)
const error = ref<DescribedError | null>(null)
const notice = ref<string | null>(null)

async function load() {
  loading.value = true
  error.value = null
  try {
    items.value = await apiRequest(`/v1/classes/${props.klass.id}/assignments`, {
      schema: z.array(Assignment),
    })
  } catch (cause) {
    error.value = describeError(cause)
  } finally {
    loading.value = false
  }
}
onMounted(load)

// --- Add / edit -----------------------------------------------------------------

const accounts = ref<AssignableAccount[]>([])
const editing = ref<{ current: Assignment | null } | null>(null)
const form = reactive({
  accountId: '',
  role: 'teacher' as ClassRole,
  startDate: '',
  endDate: '',
  subjectNote: '',
})
const busy = ref(false)
const actionError = ref<DescribedError | null>(null)

async function openForm(current: Assignment | null) {
  actionError.value = null
  notice.value = null
  Object.assign(form, {
    accountId: current?.accountId ?? '',
    role: current?.role ?? 'teacher',
    startDate: current?.startDate ?? props.klass.startDate,
    endDate: current?.endDate ?? props.klass.endDate,
    subjectNote: current?.subjectNote ?? '',
  })
  editing.value = { current }
  if (!current && !accounts.value.length) {
    try {
      accounts.value = await apiRequest('/v1/assignments/assignable-accounts', {
        schema: z.array(AssignableAccount),
      })
    } catch (cause) {
      actionError.value = describeError(cause)
    }
  }
}

const started = computed(() => editing.value?.current?.status === 'active')
const formValid = computed(
  () =>
    (editing.value?.current || form.accountId) &&
    form.startDate &&
    form.endDate &&
    form.endDate >= form.startDate,
)

async function submit() {
  const current = editing.value?.current ?? null
  busy.value = true
  actionError.value = null
  const fields = {
    role: form.role,
    startDate: form.startDate,
    endDate: form.endDate,
    subjectNote: form.subjectNote.trim() || null,
  }
  try {
    const saved = current
      ? await apiRequest(`/v1/assignments/${current.id}`, {
          method: 'PUT',
          body: { ...fields, expectedVersion: current.rowVersion },
          schema: Assignment,
        })
      : await apiRequest(`/v1/classes/${props.klass.id}/assignments`, {
          method: 'POST',
          body: { ...fields, accountId: form.accountId },
          schema: Assignment,
        })
    notice.value = t('assignments.saved', { name: saved.fullName })
    editing.value = null
    await load()
    emit('changed')
  } catch (cause) {
    actionError.value = describeError(cause)
  } finally {
    busy.value = false
  }
}

// --- End early / cancel -------------------------------------------------------

const ending = ref<Assignment | null>(null)
const reason = ref('')

async function confirmEnd() {
  const current = ending.value
  if (!current) return
  busy.value = true
  actionError.value = null
  try {
    const saved = await apiRequest(`/v1/assignments/${current.id}/end`, {
      method: 'POST',
      body: { reason: reason.value, expectedVersion: current.rowVersion },
      schema: Assignment,
    })
    notice.value = t(`assignments.done.${saved.status === 'cancelled' ? 'cancel' : 'end'}`, {
      name: saved.fullName,
    })
    ending.value = null
    await load()
    emit('changed')
  } catch (cause) {
    actionError.value = describeError(cause)
  } finally {
    busy.value = false
  }
}

function actionsFor(item: Assignment): RowAction[] {
  if (!props.canManage || props.klass.deleted) return []
  if (item.status === 'active')
    return [
      { key: 'edit', label: t('assignments.actions.edit') },
      { key: 'end', label: t('assignments.actions.end'), danger: true },
    ]
  if (item.status === 'not_started')
    return [
      { key: 'edit', label: t('assignments.actions.edit') },
      { key: 'end', label: t('assignments.actions.cancel'), danger: true },
    ]
  return []
}

function onAction(item: Assignment, key: string) {
  if (key === 'edit') void openForm(item)
  if (key === 'end') {
    actionError.value = null
    notice.value = null
    reason.value = ''
    ending.value = item
  }
}

const dates = (item: Assignment) =>
  `${formatIsoDate(item.startDate)} – ${formatIsoDate(item.endDate)}`
</script>

<template>
  <div>
    <div
      v-if="props.canManage && !props.klass.deleted"
      class="table-controls d-flex justify-content-end"
    >
      <button
        type="button"
        class="btn btn-sm btn-primary"
        data-testid="assignment-create"
        @click="openForm(null)"
      >
        <i class="bi bi-person-plus me-1" aria-hidden="true"></i>{{ t('assignments.create') }}
      </button>
    </div>
    <FloatingAlert :message="notice" />
    <ErrorAlert :error="error" />
    <div class="table-responsive">
      <table
        class="table table-hover align-middle mb-0 data-table"
        data-testid="assignments-table"
        :aria-busy="loading"
      >
        <thead>
          <tr>
            <th scope="col">{{ t('assignments.columns.person') }}</th>
            <th scope="col">{{ t('assignments.columns.role') }}</th>
            <th scope="col">{{ t('assignments.columns.dates') }}</th>
            <th scope="col">{{ t('assignments.columns.subjectNote') }}</th>
            <th scope="col">{{ t('assignments.columns.status') }}</th>
            <th scope="col" class="text-end">{{ t('common.actions') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-if="!loading && !items.length">
            <td colspan="6" class="text-body-secondary">{{ t('assignments.empty') }}</td>
          </tr>
          <tr v-for="item in items" :key="item.id" :data-email="item.email">
            <td>
              <div class="fw-medium">{{ item.fullName }}</div>
              <div class="small text-body-secondary text-break">{{ item.email }}</div>
            </td>
            <td>{{ t(`assignments.role.${item.role}`) }}</td>
            <td class="small text-nowrap">{{ dates(item) }}</td>
            <td class="small">{{ item.subjectNote || '—' }}</td>
            <td>
              <span
                class="badge"
                :class="assignmentBadge[item.status]"
                :title="item.endReason ?? undefined"
                data-testid="assignment-status"
                >{{ t(`assignments.status.${item.status}`) }}</span
              >
            </td>
            <td class="text-end">
              <RowActionMenu
                v-if="actionsFor(item).length"
                :id="item.id"
                :label="`${t('common.actions')}: ${item.fullName}`"
                :items="actionsFor(item)"
                @select="onAction(item, $event)"
              />
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <ModalDialog
      v-if="editing"
      :title="
        editing.current
          ? t('assignments.editTitle', { name: editing.current.fullName })
          : t('assignments.create')
      "
      @close="editing = null"
    >
      <p class="small text-body-secondary">
        {{ started ? t('assignments.startedHint') : t('assignments.hint') }}
      </p>
      <ErrorAlert :error="actionError" />
      <form id="assignment-form" novalidate @submit.prevent="submit">
        <div v-if="!editing.current" class="mb-3">
          <label class="form-label" for="assignment-account">{{
            t('assignments.columns.person')
          }}</label>
          <select id="assignment-account" v-model="form.accountId" class="form-select" required>
            <option value="" disabled>{{ t('classes.choose') }}</option>
            <option v-for="account in accounts" :key="account.id" :value="account.id">
              {{ account.fullName }} — {{ account.email }}
            </option>
          </select>
        </div>
        <fieldset class="mb-3">
          <legend class="form-label">{{ t('assignments.columns.role') }}</legend>
          <div class="btn-group btn-group-sm" role="group">
            <template v-for="role in ['teacher', 'assistant'] as const" :key="role">
              <input
                :id="`assignment-role-${role}`"
                v-model="form.role"
                type="radio"
                class="btn-check"
                name="assignment-role"
                :value="role"
                :disabled="started"
              />
              <label class="btn btn-outline-secondary" :for="`assignment-role-${role}`">{{
                t(`assignments.role.${role}`)
              }}</label>
            </template>
          </div>
        </fieldset>
        <div class="row g-3 mb-3">
          <div class="col-12 col-sm-6">
            <label class="form-label" for="assignment-start">{{
              t('assignments.fields.startDate')
            }}</label>
            <DateInput
              id="assignment-start"
              v-model="form.startDate"
              class="form-control"
              :min="props.klass.startDate"
              :max="props.klass.endDate"
              :disabled="started"
              required
            />
          </div>
          <div class="col-12 col-sm-6">
            <label class="form-label" for="assignment-end">{{
              t('assignments.fields.endDate')
            }}</label>
            <DateInput
              id="assignment-end"
              v-model="form.endDate"
              class="form-control"
              :min="form.startDate"
              :max="props.klass.endDate"
              required
            />
          </div>
        </div>
        <div>
          <label class="form-label" for="assignment-note">
            {{ t('assignments.columns.subjectNote') }}
            <span class="text-body-secondary">({{ t('common.optional') }})</span>
          </label>
          <input
            id="assignment-note"
            v-model="form.subjectNote"
            class="form-control"
            maxlength="200"
          />
        </div>
      </form>
      <template #footer>
        <button type="button" class="btn btn-outline-secondary" @click="editing = null">
          {{ t('common.cancel') }}
        </button>
        <button
          type="submit"
          form="assignment-form"
          class="btn btn-primary"
          :disabled="busy || !formValid"
          data-testid="assignment-submit"
        >
          {{ t('common.save') }}
        </button>
      </template>
    </ModalDialog>

    <ModalDialog
      v-if="ending"
      :title="
        t(ending.status === 'active' ? 'assignments.actions.end' : 'assignments.actions.cancel')
      "
      @close="ending = null"
    >
      <ErrorAlert :error="actionError" />
      <p>
        {{
          t(ending.status === 'active' ? 'assignments.endHint' : 'assignments.cancelHint', {
            name: ending.fullName,
          })
        }}
      </p>
      <label class="form-label" for="assignment-reason">{{ t('accounts.reason') }}</label>
      <textarea
        id="assignment-reason"
        v-model="reason"
        class="form-control"
        rows="3"
        maxlength="1000"
      ></textarea>
      <template #footer>
        <button type="button" class="btn btn-outline-secondary" @click="ending = null">
          {{ t('common.cancel') }}
        </button>
        <button
          type="button"
          class="btn btn-danger"
          :disabled="busy || !reason.trim()"
          data-testid="assignment-confirm-end"
          @click="confirmEnd"
        >
          {{ t('common.confirm') }}
        </button>
      </template>
    </ModalDialog>
  </div>
</template>
