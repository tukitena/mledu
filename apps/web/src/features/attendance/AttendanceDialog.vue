<script setup lang="ts">
import { Attendance } from '@mledu/contracts/attendance'
import { onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { apiRequest } from '../../app/session'
import { describeError, type DescribedError } from '../../app/errors'
import ModalDialog from '../../components/ModalDialog.vue'
import ErrorAlert from '../../components/ErrorAlert.vue'
const props = defineProps<{ sessionId: string; readonly: boolean }>()
const emit = defineEmits<{ close: []; saved: [] }>()
const { t } = useI18n()
const data = ref<Attendance | null>(null)
const rows = ref<
  {
    studentId: string
    code: string
    fullName: string
    present: boolean | null
    absent: boolean
    note: string
  }[]
>([])
const error = ref<DescribedError | null>(null)
const busy = ref(false)
function update(value: Attendance) {
  data.value = value
  rows.value = value.students.map((item) => ({
    ...item,
    absent: item.present === false,
    note: item.note ?? '',
  }))
}
async function load() {
  try {
    update(await apiRequest(`/v1/sessions/${props.sessionId}/attendance`, { schema: Attendance }))
  } catch (cause) {
    error.value = describeError(cause)
  }
}
onMounted(load)
async function save() {
  if (!data.value) return
  busy.value = true
  error.value = null
  try {
    update(
      await apiRequest(`/v1/sessions/${props.sessionId}/attendance`, {
        method: 'PUT',
        schema: Attendance,
        body: {
          fingerprint: data.value.fingerprint,
          students: rows.value.map((item) => ({
            studentId: item.studentId,
            present: !item.absent,
            note: item.note || null,
          })),
        },
      }),
    )
    emit('saved')
  } catch (cause) {
    error.value = describeError(cause)
  } finally {
    busy.value = false
  }
}
</script>
<template>
  <ModalDialog :title="t('attendance.title')" wide @close="emit('close')">
    <ErrorAlert :error="error" />
    <template v-if="data">
      <p>{{ data.session.date }} · {{ data.session.startTime }}–{{ data.session.endTime }}</p>
      <p class="text-body-secondary">{{ t('attendance.hint') }}</p>
      <div class="table-responsive">
        <table class="table align-middle" data-testid="attendance-table">
          <thead>
            <tr>
              <th>{{ t('attendance.student') }}</th>
              <th>{{ t('attendance.result') }}</th>
              <th>{{ t('attendance.absent') }}</th>
              <th>{{ t('attendance.note') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="(item, index) in rows" :key="item.studentId">
              <td>
                {{ item.fullName }}<br /><small class="text-body-secondary">{{ item.code }}</small>
              </td>
              <td>
                <span
                  class="badge"
                  :class="
                    item.present === null
                      ? 'text-bg-light border'
                      : item.present
                        ? 'text-bg-success'
                        : 'text-bg-danger'
                  "
                  >{{
                    t(
                      item.present === null
                        ? 'attendance.unmarked'
                        : item.present
                          ? 'attendance.present'
                          : 'attendance.absent',
                    )
                  }}</span
                >
              </td>
              <td>
                <input
                  :id="`absent-${index}`"
                  v-model="item.absent"
                  class="form-check-input"
                  type="checkbox"
                  :aria-label="t('attendance.absent')"
                  :disabled="readonly || busy"
                />
              </td>
              <td>
                <textarea
                  v-model="item.note"
                  class="form-control"
                  rows="2"
                  maxlength="1000"
                  :aria-label="t('attendance.note')"
                  :disabled="readonly || busy"
                  style="min-width: 12rem"
                ></textarea>
              </td>
            </tr>
          </tbody>
        </table>
        <p v-if="!rows.length" class="text-body-secondary">{{ t('attendance.empty') }}</p>
      </div>
    </template>
    <template #footer>
      <button type="button" class="btn btn-outline-secondary" @click="emit('close')">
        {{ t('common.close') }}
      </button>
      <button
        v-if="data && !readonly"
        type="button"
        class="btn btn-primary"
        data-testid="attendance-save"
        :disabled="busy"
        @click="save"
      >
        {{ t('attendance.save') }}
      </button>
    </template>
  </ModalDialog>
</template>
