<script setup lang="ts">
import DateInput from '../../components/DateInput.vue'
import { ClassPage, type ClassDetail } from '@mledu/contracts/classes'
import { ClassStudent, type Participation } from '@mledu/contracts/enrollments'
import { StudentPage } from '@mledu/contracts/students'
import { nameKey } from '@mledu/contracts/normalize'
import { computed, onBeforeUnmount, reactive, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { z } from 'zod'
import { apiRequest } from '../../app/session'
import { describeError, type DescribedError } from '../../app/errors'
import ErrorAlert from '../../components/ErrorAlert.vue'
import FloatingAlert from '../../components/FloatingAlert.vue'
import ModalDialog from '../../components/ModalDialog.vue'
import RowActionMenu, { type RowAction } from '../../components/RowActionMenu.vue'
import { formatIsoDate, formatInstant } from '../../lib/format'

const props = defineProps<{ klass: ClassDetail; canManage: boolean }>()
const { t } = useI18n()
const records = ref<ClassStudent[]>([])
const includeDeleted = ref(false)
const search = ref('')
const error = ref<DescribedError | null>(null)
const notice = ref<string | null>(null)
const loading = ref(false)
let loadSequence = 0
async function load() {
  const sequence = ++loadSequence
  loading.value = true
  error.value = null
  try {
    const rows = await apiRequest(
      `/v1/classes/${props.klass.id}/students?includeDeleted=${includeDeleted.value}`,
      { schema: z.array(ClassStudent) },
    )
    if (sequence === loadSequence) records.value = rows
  } catch (cause) {
    if (sequence === loadSequence) {
      records.value = []
      error.value = describeError(cause)
    }
  } finally {
    if (sequence === loadSequence) loading.value = false
  }
}
watch(() => [props.klass.id, props.klass.rowVersion, includeDeleted.value], load, {
  immediate: true,
})
// Refresh date-derived statuses while the page is visible, including midnight.
const timer = setInterval(() => {
  if (!document.hidden && !dialog.value) void load()
}, 60_000)
onBeforeUnmount(() => {
  clearInterval(timer)
  loadSequence++
})
const rows = computed(() =>
  records.value
    .filter((r) => nameKey(r.student.fullName).includes(nameKey(search.value)))
    .flatMap((record) => record.participations.map((part) => ({ record, part }))),
)
const date = (value: string | null) => formatIsoDate(value) || '—'
const studentDetails = (student: ClassStudent['student']) =>
  [student.parentPhones.join(', '), formatIsoDate(student.birthDate)].filter(Boolean).join(' · ')
const instant = (value: string | null) => formatInstant(value) || '—'
const canEnroll = computed(
  () => props.canManage && !props.klass.deleted && props.klass.adminState === 'open',
)
const badges = {
  active: 'bg-success-subtle text-success-emphasis',
  not_started: 'bg-info-subtle text-info-emphasis',
  ended: 'bg-secondary-subtle text-secondary-emphasis',
  cancelled: 'bg-secondary-subtle text-secondary-emphasis',
}
type Action = 'enroll' | 'reenroll' | 'leave' | 'note' | 'cancel' | 'delete' | 'transfer'
const dialog = ref<{
  action: Action
  record: ClassStudent | undefined
  part: Participation | undefined
} | null>(null)
const form = reactive({
  studentId: '',
  joinDate: '',
  leaveDate: '',
  note: '',
  reason: '',
  targetClassId: '',
})
const busy = ref(false)
const actionError = ref<DescribedError | null>(null)
const lookup = ref('')
const lookupPage = ref(1)
const lookupTotal = ref(0)
const choices = ref<{ id: string; label: string }[]>([])
const lookupBusy = ref(false)
let lookupSequence = 0
async function findChoices() {
  const current = dialog.value
  if (!current) return
  const sequence = ++lookupSequence
  lookupBusy.value = true
  actionError.value = null
  choices.value = []
  form.studentId = current.record?.student.id ?? ''
  form.targetClassId = ''
  try {
    const query = new URLSearchParams({
      search: lookup.value,
      page: String(lookupPage.value),
      pageSize: '20',
    })
    if (current.action === 'transfer') {
      const result = await apiRequest(`/v1/classes?${query}`, { schema: ClassPage })
      if (sequence !== lookupSequence || dialog.value !== current) return
      choices.value = result.items
        .filter((c) => c.id !== props.klass.id && c.adminState === 'open' && !c.deleted)
        .map((c) => ({ id: c.id, label: `${c.name} · ${date(c.startDate)} – ${date(c.endDate)}` }))
      lookupTotal.value = result.total
    } else {
      const result = await apiRequest(`/v1/students?${query}`, { schema: StudentPage })
      if (sequence !== lookupSequence || dialog.value !== current) return
      choices.value = result.items.map((s) => ({
        id: s.id,
        label: [s.fullName, s.parentPhones.join(', '), formatIsoDate(s.birthDate)]
          .filter(Boolean)
          .join(' · '),
      }))
      lookupTotal.value = result.total
    }
  } catch (cause) {
    if (sequence === lookupSequence) actionError.value = describeError(cause)
  } finally {
    if (sequence === lookupSequence) lookupBusy.value = false
  }
}
function searchChoices() {
  lookupPage.value = 1
  void findChoices()
}
function changeLookupPage(delta: number) {
  lookupPage.value += delta
  void findChoices()
}
function open(action: Action, record?: ClassStudent, part?: Participation) {
  const today = new Date(Date.now() + 7 * 3600_000).toISOString().slice(0, 10)
  dialog.value = { action, record, part }
  Object.assign(form, {
    studentId: record?.student.id ?? '',
    joinDate: today < props.klass.startDate ? props.klass.startDate : today,
    leaveDate: action === 'transfer' ? (part?.leaveDate ?? '') : '',
    note: action === 'note' ? (part?.note ?? '') : '',
    reason: '',
    targetClassId: '',
  })
  actionError.value = null
  notice.value = null
  lookup.value = ''
  lookupPage.value = 1
  lookupTotal.value = 0
  choices.value = []
  if (action === 'enroll' || action === 'transfer') void findChoices()
}
function actionsFor(record: ClassStudent, part: Participation): RowAction[] {
  if (props.klass.deleted || record.deleted) return []
  const keys: Action[] = []
  if (record.canEdit) {
    keys.push('note')
    if (!part.endedAt && part.status !== 'cancelled' && !part.leaveDate) keys.push('leave')
  }
  if (props.canManage) {
    if (!part.endedAt && part.status !== 'cancelled' && !record.student.deleted)
      keys.push('transfer')
    if (part.status === 'not_started') keys.push('cancel')
    if (canEnroll.value && !record.student.deleted) keys.push('reenroll')
    keys.push('delete')
  }
  return keys.map((key) => ({
    key,
    label: t(`enrollments.actions.${key}`),
    danger: key === 'cancel' || key === 'delete',
  }))
}
const valid = computed(() => {
  const d = dialog.value
  if (!d) return false
  if (d.action === 'cancel' || d.action === 'delete') return !!form.reason.trim()
  if (d.action === 'note') return true
  if (d.action === 'leave') return !!form.leaveDate && form.leaveDate > d.part!.joinDate
  if (d.action === 'transfer')
    return (
      !!form.targetClassId &&
      !!form.joinDate &&
      !!form.leaveDate &&
      form.leaveDate > d.part!.joinDate
    )
  return !!form.studentId && !!form.joinDate && (!form.leaveDate || form.leaveDate > form.joinDate)
})
async function submit() {
  const d = dialog.value
  if (!d || !valid.value || busy.value) return
  busy.value = true
  actionError.value = null
  let path: string
  let body: unknown
  let method: 'POST' | 'PUT' = 'POST'
  if (d.action === 'enroll' || d.action === 'reenroll') {
    path = `/v1/classes/${props.klass.id}/students`
    body = {
      studentId: form.studentId,
      joinDate: form.joinDate,
      leaveDate: form.leaveDate || null,
      note: form.note || null,
    }
  } else if (d.action === 'delete') {
    path = `/v1/class-students/${d.record!.id}/delete`
    body = { reason: form.reason, expectedVersion: d.record!.rowVersion }
  } else {
    path = `/v1/participations/${d.part!.id}/${d.action}`
    const expectedVersion = d.part!.rowVersion
    if (d.action === 'note') {
      method = 'PUT'
      body = { note: form.note || null, expectedVersion }
    } else if (d.action === 'leave') body = { leaveDate: form.leaveDate, expectedVersion }
    else if (d.action === 'cancel') body = { reason: form.reason, expectedVersion }
    else
      body = {
        targetClassId: form.targetClassId,
        joinDate: form.joinDate,
        leaveDate: form.leaveDate,
        note: form.note || null,
        expectedVersion,
      }
  }
  try {
    await apiRequest(path, { method, body, schema: ClassStudent })
    dialog.value = null
    notice.value = t('enrollments.saved')
    await load()
  } catch (cause) {
    actionError.value = describeError(cause)
  } finally {
    busy.value = false
  }
}
function close() {
  if (!busy.value) {
    dialog.value = null
    lookupSequence++
  }
}
</script>

<template>
  <section>
    <div class="d-flex flex-wrap align-items-center justify-content-between gap-2 p-3">
      <div class="d-flex flex-wrap align-items-center gap-3">
        <input
          v-model="search"
          type="search"
          class="form-control form-control-sm w-auto"
          :placeholder="t('enrollments.filter')"
          :aria-label="t('enrollments.filter')"
        />
        <div class="form-check mb-0">
          <input
            id="enrollment-archived"
            v-model="includeDeleted"
            type="checkbox"
            class="form-check-input"
          /><label for="enrollment-archived" class="form-check-label small">{{
            t('enrollments.showDeleted')
          }}</label>
        </div>
      </div>
      <button
        v-if="canEnroll"
        type="button"
        class="btn btn-primary btn-sm"
        data-testid="enrollment-create"
        @click="open('enroll')"
      >
        <i class="bi bi-person-plus me-1" aria-hidden="true"></i
        >{{ t('enrollments.actions.enroll') }}
      </button>
    </div>
    <p v-if="klass.adminState === 'closed'" class="small text-body-secondary px-3">
      {{ t('enrollments.closedHint') }}
    </p>
    <FloatingAlert :message="notice" /><ErrorAlert :error="error" />
    <div class="table-responsive">
      <table
        class="table table-hover align-middle mb-0 data-table"
        data-testid="enrollments-table"
        :aria-label="t('classes.tabs.students')"
        :aria-busy="loading"
      >
        <thead>
          <tr>
            <th>{{ t('enrollments.student') }}</th>
            <th>{{ t('enrollments.joinDate') }}</th>
            <th>{{ t('enrollments.leaveDate') }}</th>
            <th>{{ t('classes.columns.status') }}</th>
            <th>{{ t('enrollments.note') }}</th>
            <th class="text-end">{{ t('common.actions') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-if="!rows.length">
            <td colspan="6" class="text-center text-body-secondary py-4">
              {{ t(loading ? 'common.loading' : 'enrollments.empty') }}
            </td>
          </tr>
          <tr
            v-for="{ record, part } in rows"
            :key="part.id"
            :data-participation-id="part.id"
            :data-record-id="record.id"
          >
            <td>
              <div class="fw-semibold">{{ record.student.fullName }}</div>
              <div v-if="studentDetails(record.student)" class="small text-body-secondary">
                {{ studentDetails(record.student) }}
              </div>
              <span
                v-if="record.deleted || record.student.deleted"
                class="badge bg-secondary-subtle text-secondary-emphasis"
                >{{
                  t(record.deleted ? 'enrollments.recordDeleted' : 'enrollments.studentDeleted')
                }}</span
              >
            </td>
            <td class="text-nowrap small">{{ date(part.joinDate) }}</td>
            <td class="text-nowrap small">{{ date(part.leaveDate) }}</td>
            <td>
              <span class="badge" :class="badges[part.status]">{{
                t(`enrollments.status.${part.status}`)
              }}</span>
              <div class="small text-body-secondary mt-1">
                {{ t('enrollments.until', { time: instant(part.effectiveUntil) }) }}
              </div>
              <div v-if="part.endKind" class="small mt-1">
                {{ t(`enrollments.endKind.${part.endKind}`) }} · {{ instant(part.endedAt) }}
              </div>
              <div v-if="part.endReason" class="small text-break">{{ part.endReason }}</div>
            </td>
            <td class="small text-preline text-break">{{ part.note || '—' }}</td>
            <td class="text-end">
              <RowActionMenu
                v-if="actionsFor(record, part).length"
                :id="part.id"
                :label="`${t('common.actions')}: ${record.student.fullName}`"
                :items="actionsFor(record, part)"
                @select="(key) => open(key as Action, record, part)"
              />
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <ModalDialog v-if="dialog" :title="t(`enrollments.actions.${dialog.action}`)" @close="close">
      <ErrorAlert :error="actionError" />
      <p v-if="dialog.record" class="fw-semibold">
        {{ dialog.record.student.fullName }}
        <span class="d-block small text-body-secondary fw-normal">{{
          studentDetails(dialog.record.student)
        }}</span>
      </p>
      <p class="small text-body-secondary">{{ t(`enrollments.hint.${dialog.action}`) }}</p>
      <form
        v-if="dialog.action === 'enroll' || dialog.action === 'transfer'"
        class="mb-3"
        @submit.prevent="searchChoices"
      >
        <label for="enrollment-search" class="form-label">{{
          t(dialog.action === 'transfer' ? 'enrollments.searchClass' : 'enrollments.searchStudent')
        }}</label>
        <div class="input-group">
          <input
            id="enrollment-search"
            v-model="lookup"
            type="search"
            class="form-control"
          /><button
            class="btn btn-outline-secondary"
            data-testid="enrollment-search"
            :disabled="lookupBusy"
          >
            {{ t('common.search') }}
          </button>
        </div>
        <div v-if="lookupTotal > 20" class="d-flex align-items-center gap-2 mt-2 small">
          <button
            type="button"
            class="btn btn-sm btn-outline-secondary"
            :disabled="lookupBusy || lookupPage === 1"
            @click="changeLookupPage(-1)"
          >
            {{ t('common.previous') }}</button
          ><span>{{
            t('common.page', { page: lookupPage, pages: Math.ceil(lookupTotal / 20) })
          }}</span
          ><button
            type="button"
            class="btn btn-sm btn-outline-secondary"
            :disabled="lookupBusy || lookupPage * 20 >= lookupTotal"
            @click="changeLookupPage(1)"
          >
            {{ t('common.next') }}
          </button>
        </div>
      </form>
      <form id="enrollment-form" @submit.prevent="submit">
        <div v-if="dialog.action === 'enroll' || dialog.action === 'transfer'" class="mb-3">
          <label for="enrollment-choice" class="form-label">{{
            t(dialog.action === 'transfer' ? 'enrollments.targetClass' : 'enrollments.student')
          }}</label
          ><select
            v-if="dialog.action === 'enroll'"
            id="enrollment-choice"
            v-model="form.studentId"
            class="form-select"
            :disabled="lookupBusy"
          >
            <option value="">{{ t(lookupBusy ? 'common.loading' : 'enrollments.choose') }}</option>
            <option v-for="choice in choices" :key="choice.id" :value="choice.id">
              {{ choice.label }}
            </option></select
          ><select
            v-else
            id="enrollment-choice"
            v-model="form.targetClassId"
            class="form-select"
            :disabled="lookupBusy"
          >
            <option value="">{{ t(lookupBusy ? 'common.loading' : 'enrollments.choose') }}</option>
            <option v-for="choice in choices" :key="choice.id" :value="choice.id">
              {{ choice.label }}
            </option>
          </select>
        </div>
        <div v-if="['enroll', 'reenroll', 'transfer'].includes(dialog.action)" class="mb-3">
          <label for="enrollment-join" class="form-label">{{
            t(dialog.action === 'transfer' ? 'enrollments.targetJoinDate' : 'enrollments.joinDate')
          }}</label
          ><DateInput
            id="enrollment-join"
            v-model="form.joinDate"
            required
            class="form-control"
            :min="dialog.action === 'transfer' ? undefined : klass.startDate"
            :max="dialog.action === 'transfer' ? undefined : klass.endDate"
          />
        </div>
        <div
          v-if="['enroll', 'reenroll', 'leave', 'transfer'].includes(dialog.action)"
          class="mb-3"
        >
          <label for="enrollment-leave" class="form-label">{{ t('enrollments.leaveDate') }}</label
          ><DateInput
            id="enrollment-leave"
            v-model="form.leaveDate"
            class="form-control"
            :readonly="dialog.action === 'transfer' && !!dialog.part?.leaveDate"
            :required="dialog.action === 'leave' || dialog.action === 'transfer'"
          />
          <p class="form-text">{{ t('enrollments.leaveHint') }}</p>
        </div>
        <div v-if="['enroll', 'reenroll', 'note', 'transfer'].includes(dialog.action)" class="mb-3">
          <label for="enrollment-note" class="form-label">{{ t('enrollments.note') }}</label
          ><textarea
            id="enrollment-note"
            v-model="form.note"
            class="form-control"
            rows="3"
            maxlength="1000"
          ></textarea>
        </div>
        <template v-if="dialog.action === 'cancel' || dialog.action === 'delete'">
          <p v-if="dialog.action === 'delete' && dialog.record" class="small">
            {{
              t('enrollments.impact', {
                active: dialog.record.participations.filter((p) => p.status === 'active').length,
                future: dialog.record.participations.filter((p) => p.status === 'not_started')
                  .length,
              })
            }}
          </p>
          <label for="enrollment-reason" class="form-label">{{ t('accounts.reason') }}</label
          ><textarea
            id="enrollment-reason"
            v-model="form.reason"
            class="form-control"
            required
            maxlength="1000"
            rows="3"
          ></textarea>
        </template>
      </form>
      <template #footer
        ><button type="button" class="btn btn-outline-secondary" :disabled="busy" @click="close">
          {{ t('common.cancel') }}</button
        ><button
          type="submit"
          form="enrollment-form"
          class="btn"
          :class="
            dialog.action === 'cancel' || dialog.action === 'delete' ? 'btn-danger' : 'btn-primary'
          "
          :disabled="busy || !valid || lookupBusy"
          data-testid="enrollment-submit"
        >
          {{ t(busy ? 'common.saving' : 'common.confirm') }}
        </button></template
      >
    </ModalDialog>
  </section>
</template>
