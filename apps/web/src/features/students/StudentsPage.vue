<script setup lang="ts">
import { phoneKey } from '@mledu/contracts/normalize'
import { StudentDeleteImpact } from '@mledu/contracts/enrollments'
import StudentClassHistory from './StudentClassHistory.vue'
import {
  Student,
  StudentPage,
  type StudentFields,
  type StudentStatus,
} from '@mledu/contracts/students'
import { computed, reactive, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { describeError, type DescribedError } from '../../app/errors'
import { apiRequest, workspace } from '../../app/session'
import { formatIsoDate } from '../../lib/format'
import ErrorAlert from '../../components/ErrorAlert.vue'
import FloatingAlert from '../../components/FloatingAlert.vue'
import ModalDialog from '../../components/ModalDialog.vue'
import PhoneListField from '../../components/PhoneListField.vue'
import RowActionMenu, { type RowAction } from '../../components/RowActionMenu.vue'

// Student master records (STU-04/01/02). Every workspace searches the whole
// centre; management and assignment-scoped editing are separate capabilities.
const { t, locale } = useI18n()
const PAGE_SIZE = 20

const canManage = computed(() => workspace.value === 'admin' || workspace.value === 'receptionist')
const search = ref('')
const status = ref<StudentStatus>('active')
const page = ref(1)
const result = ref<StudentPage | null>(null)
const loading = ref(false)
const error = ref<DescribedError | null>(null)
const notice = ref<string | null>(null)
const pages = computed(() => Math.max(1, Math.ceil((result.value?.total ?? 0) / PAGE_SIZE)))

async function load() {
  loading.value = true
  error.value = null
  try {
    const query = new URLSearchParams({
      page: String(page.value),
      pageSize: String(PAGE_SIZE),
      status: status.value,
    })
    if (search.value.trim()) query.set('search', search.value.trim())
    result.value = await apiRequest(`/v1/students?${query}`, { schema: StudentPage })
  } catch (cause) {
    error.value = describeError(cause)
  } finally {
    loading.value = false
  }
}
watch(
  status,
  () => {
    page.value = 1
    void load()
  },
  { immediate: true },
)
watch(canManage, (allowed) => {
  if (!allowed && status.value === 'deleted') status.value = 'active'
})

const formatDate = (value: string | null) => formatIsoDate(value, locale.value)

// --- Detail -------------------------------------------------------------------

const viewing = ref<Student | null>(null)

// --- Create / edit / restore --------------------------------------------------

type FormMode = 'create' | 'edit' | 'restore'
const formMode = ref<FormMode | null>(null)
const target = ref<Student | null>(null)
const form = reactive<StudentFields>(emptyFields())
const busy = ref(false)
const actionError = ref<DescribedError | null>(null)

function emptyFields(): StudentFields {
  return {
    fullName: '',
    parentName: null,
    parentPhones: [''],
    studentPhones: [],
    birthDate: null,
    school: null,
    generalNote: null,
  }
}

function openForm(mode: FormMode, student: Student | null) {
  actionError.value = null
  notice.value = null
  target.value = student
  Object.assign(
    form,
    student
      ? {
          fullName: student.fullName,
          parentName: student.parentName,
          parentPhones: [...student.parentPhones],
          studentPhones: [...student.studentPhones],
          birthDate: student.birthDate,
          school: student.school,
          generalNote: student.generalNote,
        }
      : emptyFields(),
  )
  formMode.value = mode
}

const formValid = computed(
  () =>
    form.fullName.trim().length > 0 &&
    [...form.parentPhones, ...form.studentPhones].every(
      (phone) => !phone.trim() || phoneKey(phone) !== null,
    ),
)

const blankToNull = (value: string | null) => (value?.trim() ? value : null)

async function submitForm() {
  if (!formMode.value) return
  busy.value = true
  actionError.value = null
  const body: StudentFields = {
    fullName: form.fullName,
    parentName: blankToNull(form.parentName),
    parentPhones: form.parentPhones.filter((phone) => phone.trim()),
    studentPhones: form.studentPhones.filter((phone) => phone.trim()),
    birthDate: form.birthDate || null,
    school: blankToNull(form.school),
    generalNote: blankToNull(form.generalNote),
  }
  try {
    const current = target.value
    const saved =
      formMode.value === 'create'
        ? await apiRequest('/v1/students', { method: 'POST', body, schema: Student })
        : await apiRequest(
            formMode.value === 'edit'
              ? `/v1/students/${current!.id}`
              : `/v1/students/${current!.id}/restore`,
            {
              method: formMode.value === 'edit' ? 'PUT' : 'POST',
              body: { ...body, expectedVersion: current!.rowVersion },
              schema: Student,
            },
          )
    notice.value = t(`students.done.${formMode.value}`, { name: saved.fullName, code: saved.code })
    formMode.value = null
    await load()
  } catch (cause) {
    actionError.value = describeError(cause)
  } finally {
    busy.value = false
  }
}

// --- Soft delete ----------------------------------------------------------------

const deleting = ref<Student | null>(null)
const reason = ref('')
const deleteImpact = ref<StudentDeleteImpact | null>(null)
let impactSequence = 0

async function confirmDelete() {
  const student = deleting.value
  if (!student) return
  busy.value = true
  actionError.value = null
  try {
    await apiRequest(`/v1/students/${student.id}/delete`, {
      method: 'POST',
      body: { reason: reason.value, expectedVersion: student.rowVersion },
      schema: Student,
    })
    notice.value = t('students.done.delete', { name: student.fullName, code: student.code })
    deleting.value = null
    await load()
  } catch (cause) {
    actionError.value = describeError(cause)
  } finally {
    busy.value = false
  }
}

function actionsFor(student: Student): RowAction[] {
  const view = { key: 'view', label: t('students.actions.view') }
  const actions: RowAction[] = [view]
  if (student.status === 'active' && student.canEdit)
    actions.push({ key: 'edit', label: t('students.actions.edit') })
  if (canManage.value) {
    if (student.status === 'deleted')
      actions.push({ key: 'restore', label: t('students.actions.restore') })
    else actions.push({ key: 'delete', label: t('students.actions.delete'), danger: true })
  }
  return actions
}

async function onAction(student: Student, key: string) {
  notice.value = null
  actionError.value = null
  if (key === 'view') viewing.value = student
  if (key === 'edit' || key === 'restore') openForm(key, student)
  if (key === 'delete') {
    const sequence = ++impactSequence
    reason.value = ''
    deleting.value = student
    deleteImpact.value = null
    try {
      const impact = await apiRequest(`/v1/students/${student.id}/delete-impact`, {
        schema: StudentDeleteImpact,
      })
      if (sequence === impactSequence) deleteImpact.value = impact
    } catch (cause) {
      if (sequence === impactSequence) actionError.value = describeError(cause)
    }
  }
}

const formatPhones = (phones: string[]) => phones.join(', ')
</script>

<template>
  <div class="container-fluid page students-page">
    <div class="page-header">
      <div>
        <h1 class="page-title">{{ t('students.title') }}</h1>
        <p class="text-body-secondary mb-0">{{ t('students.subtitle') }}</p>
      </div>
      <button
        v-if="canManage"
        type="button"
        class="btn btn-primary"
        data-testid="student-create"
        @click="openForm('create', null)"
      >
        <i class="bi bi-person-plus me-1" aria-hidden="true"></i>{{ t('students.create') }}
      </button>
    </div>

    <div class="card data-card">
      <div v-if="canManage" class="card-header data-card-header">
        <div class="btn-group btn-group-sm" role="group" :aria-label="t('students.statusFilter')">
          <template v-for="item in ['active', 'deleted'] as const" :key="item">
            <input
              :id="`student-status-${item}`"
              v-model="status"
              type="radio"
              class="btn-check"
              name="student-status"
              :value="item"
              autocomplete="off"
            />
            <label
              class="btn btn-outline-secondary"
              :for="`student-status-${item}`"
              :data-testid="`student-status-${item}`"
              >{{ t(`students.status.${item}`) }}</label
            >
          </template>
        </div>
      </div>
      <div class="card-body">
        <form class="row g-3 table-controls" role="search" @submit.prevent="((page = 1), load())">
          <div class="col-8 col-md-9">
            <input
              v-model="search"
              type="search"
              class="form-control"
              :placeholder="t('students.searchPlaceholder')"
              :aria-label="t('common.search')"
              data-testid="student-search"
            />
          </div>
          <div class="col-4 col-md-3 d-grid">
            <button type="submit" class="btn btn-outline-secondary">
              {{ t('common.search') }}
            </button>
          </div>
        </form>

        <FloatingAlert :message="notice" />
        <ErrorAlert :error="error" />

        <div class="table-responsive">
          <table
            class="table table-hover align-middle mb-0 data-table students-table"
            data-testid="students-table"
            :aria-busy="loading"
          >
            <thead>
              <tr>
                <th scope="col">{{ t('students.columns.name') }}</th>
                <th scope="col">{{ t('students.columns.code') }}</th>
                <th scope="col">{{ t('students.columns.parentPhones') }}</th>
                <th scope="col">{{ t('students.columns.birthDate') }}</th>
                <th scope="col">{{ t('students.columns.school') }}</th>
                <th scope="col" class="text-end">{{ t('common.actions') }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-if="loading && !result">
                <td colspan="6" class="text-body-secondary">{{ t('common.loading') }}</td>
              </tr>
              <tr v-else-if="result && !result.items.length">
                <td colspan="6" class="text-body-secondary">{{ t('students.empty') }}</td>
              </tr>
              <tr
                v-for="student in result?.items ?? []"
                :key="student.id"
                :data-code="student.code"
              >
                <td>
                  <button
                    type="button"
                    class="btn btn-link p-0 fw-medium text-start text-decoration-none"
                    @click="viewing = student"
                  >
                    {{ student.fullName }}
                  </button>
                  <div v-if="student.parentName" class="small text-body-secondary">
                    {{ t('students.parentOf', { name: student.parentName }) }}
                  </div>
                </td>
                <td class="font-monospace small">{{ student.code }}</td>
                <td class="small">{{ formatPhones(student.parentPhones) }}</td>
                <td class="small">{{ formatDate(student.birthDate) }}</td>
                <td class="small text-break">{{ student.school }}</td>
                <td class="text-end">
                  <RowActionMenu
                    :id="student.id"
                    :label="`${t('common.actions')}: ${student.fullName}`"
                    :items="actionsFor(student)"
                    @select="onAction(student, $event)"
                  />
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div
          v-if="result"
          class="table-pagination d-flex flex-wrap align-items-center justify-content-between gap-2"
        >
          <span class="small text-body-secondary">{{
            t('students.total', { n: result.total })
          }}</span>
          <div class="btn-group btn-group-sm">
            <button
              type="button"
              class="btn btn-outline-secondary"
              :disabled="page <= 1"
              @click="(page--, load())"
            >
              {{ t('common.previous') }}
            </button>
            <span class="btn btn-outline-secondary disabled">
              {{ t('common.page', { page, pages }) }}
            </span>
            <button
              type="button"
              class="btn btn-outline-secondary"
              :disabled="page >= pages"
              @click="(page++, load())"
            >
              {{ t('common.next') }}
            </button>
          </div>
        </div>
      </div>
    </div>

    <ModalDialog v-if="viewing" :title="viewing.fullName" @close="viewing = null">
      <dl class="row mb-0 student-detail" data-testid="student-detail">
        <dt class="col-5">{{ t('students.columns.code') }}</dt>
        <dd class="col-7 font-monospace">{{ viewing.code }}</dd>
        <dt class="col-5">{{ t('students.fields.parentName') }}</dt>
        <dd class="col-7">{{ viewing.parentName || '—' }}</dd>
        <dt class="col-5">{{ t('students.fields.parentPhones') }}</dt>
        <dd class="col-7">{{ formatPhones(viewing.parentPhones) || '—' }}</dd>
        <dt class="col-5">{{ t('students.fields.studentPhones') }}</dt>
        <dd class="col-7">{{ formatPhones(viewing.studentPhones) || '—' }}</dd>
        <dt class="col-5">{{ t('students.fields.birthDate') }}</dt>
        <dd class="col-7">{{ formatDate(viewing.birthDate) || '—' }}</dd>
        <dt class="col-5">{{ t('students.fields.school') }}</dt>
        <dd class="col-7">{{ viewing.school || '—' }}</dd>
        <dt class="col-5">{{ t('students.fields.generalNote') }}</dt>
        <dd class="col-7 text-break text-preline">
          {{ viewing.generalNote || '—' }}
        </dd>
        <template v-if="viewing.status === 'deleted'">
          <dt class="col-5">{{ t('students.deletedReason') }}</dt>
          <dd class="col-7">{{ viewing.deletedReason }}</dd>
        </template>
      </dl>
      <StudentClassHistory :student-id="viewing.id" />
      <template #footer>
        <button type="button" class="btn btn-primary" @click="viewing = null">
          {{ t('common.close') }}
        </button>
      </template>
    </ModalDialog>

    <ModalDialog
      v-if="formMode"
      :title="t(`students.formTitle.${formMode}`, { name: target?.fullName ?? '' })"
      @close="formMode = null"
    >
      <p v-if="formMode === 'restore'" class="small text-body-secondary">
        {{ t('students.restoreHint') }}
      </p>
      <p v-else-if="formMode === 'create'" class="small text-body-secondary">
        {{ t('students.createHint') }}
      </p>
      <p v-else class="small text-body-secondary" data-testid="student-shared-hint">
        {{ t('students.sharedEditHint') }}
      </p>
      <ErrorAlert :error="actionError" />
      <form id="student-form" novalidate @submit.prevent="submitForm">
        <div class="mb-3">
          <label class="form-label" for="student-name">{{ t('students.fields.fullName') }}</label>
          <input
            id="student-name"
            v-model="form.fullName"
            class="form-control"
            maxlength="200"
            required
          />
        </div>
        <div class="mb-3">
          <label class="form-label" for="student-parent">
            {{ t('students.fields.parentName') }}
            <span class="text-body-secondary">({{ t('common.optional') }})</span>
          </label>
          <input
            id="student-parent"
            v-model="form.parentName"
            class="form-control"
            maxlength="200"
          />
        </div>
        <div class="row g-3 mb-3">
          <div class="col-12 col-sm-6">
            <PhoneListField
              id="student-parent-phones"
              v-model="form.parentPhones"
              :label="t('students.fields.parentPhones')"
            />
          </div>
          <div class="col-12 col-sm-6">
            <PhoneListField
              id="student-own-phones"
              v-model="form.studentPhones"
              :label="t('students.fields.studentPhones')"
            />
          </div>
        </div>
        <div class="row g-3 mb-3">
          <div class="col-12 col-sm-6">
            <label class="form-label" for="student-birth">
              {{ t('students.fields.birthDate') }}
              <span class="text-body-secondary">({{ t('common.optional') }})</span>
            </label>
            <input id="student-birth" v-model="form.birthDate" type="date" class="form-control" />
          </div>
          <div class="col-12 col-sm-6">
            <label class="form-label" for="student-school">
              {{ t('students.fields.school') }}
              <span class="text-body-secondary">({{ t('common.optional') }})</span>
            </label>
            <input id="student-school" v-model="form.school" class="form-control" maxlength="200" />
          </div>
        </div>
        <div>
          <label class="form-label" for="student-note">
            {{ t('students.fields.generalNote') }}
            <span class="text-body-secondary">({{ t('common.optional') }})</span>
          </label>
          <textarea
            id="student-note"
            v-model="form.generalNote"
            class="form-control"
            rows="3"
            maxlength="1000"
          ></textarea>
        </div>
      </form>
      <template #footer>
        <button type="button" class="btn btn-outline-secondary" @click="formMode = null">
          {{ t('common.cancel') }}
        </button>
        <button
          type="submit"
          form="student-form"
          class="btn btn-primary"
          :disabled="busy || !formValid"
          data-testid="student-submit"
        >
          {{ formMode === 'restore' ? t('students.actions.restore') : t('common.save') }}
        </button>
      </template>
    </ModalDialog>

    <ModalDialog
      v-if="deleting"
      :title="t('students.deleteTitle', { name: deleting.fullName })"
      @close="deleting = null"
    >
      <ErrorAlert :error="actionError" />
      <p>{{ t('students.deleteHint') }}</p>
      <p v-if="deleteImpact" class="small">
        {{
          t('enrollments.impact', {
            active: deleteImpact.activeParticipations,
            future: deleteImpact.futureParticipations,
          })
        }}
        {{ deleteImpact.classes.join(', ') }}
      </p>
      <p v-else-if="!actionError" class="small">{{ t('common.loading') }}</p>
      <label class="form-label" for="student-reason">{{ t('accounts.reason') }}</label>
      <textarea
        id="student-reason"
        v-model="reason"
        class="form-control"
        rows="3"
        maxlength="1000"
      ></textarea>
      <template #footer>
        <button type="button" class="btn btn-outline-secondary" @click="deleting = null">
          {{ t('common.cancel') }}
        </button>
        <button
          type="button"
          class="btn btn-danger"
          :disabled="busy || !reason.trim() || !deleteImpact"
          data-testid="student-confirm-delete"
          @click="confirmDelete"
        >
          {{ t('students.actions.delete') }}
        </button>
      </template>
    </ModalDialog>
  </div>
</template>
