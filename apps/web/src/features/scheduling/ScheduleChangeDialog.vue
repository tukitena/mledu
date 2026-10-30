<script setup lang="ts">
import { ScheduleChange, SchedulePreview, type ClassSchedule } from '@mledu/contracts/scheduling'
import type { Room } from '@mledu/contracts/catalogs'
import { computed, ref, toRaw } from 'vue'
import { useI18n } from 'vue-i18n'
import { apiRequest } from '../../app/session'
import { describeError, type DescribedError } from '../../app/errors'
import ModalDialog from '../../components/ModalDialog.vue'
import ErrorAlert from '../../components/ErrorAlert.vue'
import StaffWarnings from './StaffWarnings.vue'
const props = defineProps<{
  classId: string
  initial: ScheduleChange
  rooms: Room[]
  weekly: ClassSchedule['weekly']
}>()
const emit = defineEmits<{ close: []; saved: [] }>()
const { t } = useI18n()
const form = ref<ScheduleChange>(structuredClone(toRaw(props.initial)))
const preview = ref<SchedulePreview | null>(null)
const reviewed = ref<ScheduleChange | null>(null)
const error = ref<DescribedError | null>(null)
const busy = ref(false)
const weeklyForm = computed(() =>
  form.value.op === 'weekly' ? form.value : form.value.op === 'reopen' ? form.value.weekly : null,
)
function toggleReopenWeekly(event: Event) {
  if (form.value.op !== 'reopen') return
  form.value.weekly = (event.target as HTMLInputElement).checked
    ? { appliesOn: new Date(Date.now() + 7 * 3600_000).toISOString().slice(0, 10), slots: [] }
    : null
  copyWeekly()
}
const path = () =>
  form.value.op === 'holiday' || form.value.op === 'remove_holiday'
    ? '/v1/holidays'
    : `/v1/classes/${props.classId}/schedule`
function copyWeekly() {
  const value = weeklyForm.value
  if (!value) return
  const revision = [...props.weekly].reverse().find((item) => item.appliesOn <= value.appliesOn)
  value.slots = structuredClone(toRaw(revision?.slots ?? []))
}
function addSlot() {
  weeklyForm.value?.slots.push({ weekday: 1, startTime: '09:00', endTime: '10:00', roomId: null })
}
async function inspect() {
  busy.value = true
  error.value = null
  try {
    const change = ScheduleChange.parse(form.value)
    preview.value = await apiRequest(`${path()}/preview`, {
      method: 'POST',
      body: change,
      schema: SchedulePreview,
    })
    reviewed.value = structuredClone(change)
  } catch (cause) {
    error.value = describeError(cause)
  } finally {
    busy.value = false
  }
}
async function confirm() {
  if (!preview.value || !reviewed.value) return
  busy.value = true
  error.value = null
  try {
    await apiRequest(path(), {
      method: 'POST',
      body: { change: reviewed.value, token: preview.value.token },
      schema: SchedulePreview,
    })
    emit('saved')
  } catch (cause) {
    error.value = describeError(cause)
    preview.value = null
  } finally {
    busy.value = false
  }
}
</script>
<template>
  <ModalDialog :title="t(`scheduling.op.${form.op}`)" wide @close="emit('close')">
    <ErrorAlert :error="error" />
    <template v-if="preview">
      <p>{{ t('scheduling.confirmHint') }}</p>
      <StaffWarnings :warnings="preview.warnings" />
      <div class="table-responsive" data-testid="schedule-impact">
        <table class="table table-hover align-middle">
          <thead>
            <tr>
              <th>{{ t('scheduling.date') }}</th>
              <th>{{ t('scheduling.time') }}</th>
              <th>{{ t('scheduling.room') }}</th>
              <th>{{ t('scheduling.status') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="item in preview.sessions" :key="item.id">
              <td>{{ item.className }}<br />{{ item.date }}</td>
              <td>{{ item.startTime }}–{{ item.endTime }}</td>
              <td>{{ item.roomName ?? t('scheduling.noRoom') }}<br />{{ item.siteName }}</td>
              <td>{{ t(`scheduling.state.${item.status}`) }}</td>
            </tr>
          </tbody>
        </table>
        <p v-if="!preview.sessions.length" class="text-body-secondary">
          {{ t('scheduling.noImpact') }}
        </p>
      </div>
    </template>
    <form v-else id="schedule-change-form" @submit.prevent="inspect">
      <p class="text-body-secondary">{{ t('scheduling.editHint') }}</p>
      <template v-if="form.op === 'reopen'">
        <p>{{ t('scheduling.reopenHint') }}</p>
        <label class="form-check-label mb-3"
          ><input
            type="checkbox"
            class="form-check-input me-2"
            :checked="!!form.weekly"
            @change="toggleReopenWeekly"
          />{{ t('scheduling.reopenWeekly') }}</label
        >
        <div
          v-for="(slot, index) in form.adjustments"
          :key="slot.sessionId"
          class="border rounded p-3 mb-3"
        >
          <div class="row g-3">
            <div class="col-sm-4">
              <label class="form-label" :for="`reopen-date-${index}`">{{
                t('scheduling.date')
              }}</label
              ><input
                :id="`reopen-date-${index}`"
                v-model="slot.date"
                class="form-control"
                type="date"
                required
              />
            </div>
            <div class="col-sm-4">
              <label class="form-label" :for="`reopen-start-${index}`">{{
                t('scheduling.start')
              }}</label
              ><input
                :id="`reopen-start-${index}`"
                v-model="slot.startTime"
                class="form-control"
                type="time"
                required
              />
            </div>
            <div class="col-sm-4">
              <label class="form-label" :for="`reopen-end-${index}`">{{
                t('scheduling.end')
              }}</label
              ><input
                :id="`reopen-end-${index}`"
                v-model="slot.endTime"
                class="form-control"
                type="time"
                required
              />
            </div>
            <div class="col-12">
              <label class="form-label" :for="`reopen-room-${index}`">{{
                t('scheduling.room')
              }}</label
              ><select :id="`reopen-room-${index}`" v-model="slot.roomId" class="form-select">
                <option :value="null">{{ t('scheduling.noRoom') }}</option>
                <option
                  v-if="slot.roomId && !rooms.some((room) => room.id === slot.roomId)"
                  :value="slot.roomId"
                  disabled
                >
                  {{ t('scheduling.unavailableRoom') }}
                </option>
                <option v-for="room in rooms" :key="room.id" :value="room.id">
                  {{ room.name }} · {{ room.siteName }}
                </option>
              </select>
            </div>
          </div>
        </div>
      </template>
      <template v-if="weeklyForm">
        <label class="form-label" for="applies-on">{{ t('scheduling.appliesOn') }}</label>
        <input
          id="applies-on"
          v-model="weeklyForm.appliesOn"
          type="date"
          class="form-control mb-3"
          required
          @change="copyWeekly"
        />
        <div v-for="(slot, index) in weeklyForm.slots" :key="index" class="border rounded p-3 mb-3">
          <div class="row g-3">
            <div class="col-sm-3">
              <label class="form-label" :for="`weekday-${index}`">{{
                t('scheduling.weekday')
              }}</label
              ><select :id="`weekday-${index}`" v-model.number="slot.weekday" class="form-select">
                <option v-for="n in 7" :key="n" :value="n">{{ t(`scheduling.days.${n}`) }}</option>
              </select>
            </div>
            <div class="col-sm-3">
              <label class="form-label" :for="`start-${index}`">{{ t('scheduling.start') }}</label
              ><input
                :id="`start-${index}`"
                v-model="slot.startTime"
                class="form-control"
                type="time"
                required
              />
            </div>
            <div class="col-sm-3">
              <label class="form-label" :for="`end-${index}`">{{ t('scheduling.end') }}</label
              ><input
                :id="`end-${index}`"
                v-model="slot.endTime"
                class="form-control"
                type="time"
                required
              />
            </div>
            <div class="col-sm-3 d-flex align-items-end">
              <button
                type="button"
                class="btn btn-outline-danger"
                @click="weeklyForm.slots.splice(index, 1)"
              >
                {{ t('scheduling.removeSlot') }}
              </button>
            </div>
            <div class="col-12">
              <label class="form-label" :for="`room-${index}`">{{ t('scheduling.room') }}</label
              ><select :id="`room-${index}`" v-model="slot.roomId" class="form-select">
                <option :value="null">{{ t('scheduling.noRoom') }}</option>
                <option v-for="room in rooms" :key="room.id" :value="room.id">
                  {{ room.name }} · {{ room.siteName }}
                </option>
              </select>
            </div>
          </div>
        </div>
        <button class="btn btn-outline-primary" type="button" @click="addSlot">
          {{ t('scheduling.addSlot') }}
        </button>
        <p class="small text-body-secondary mt-2">{{ t('scheduling.emptyWeekly') }}</p>
      </template>
      <div v-if="form.op === 'makeup' || form.op === 'move'" class="row g-3">
        <div class="col-12">
          <label class="form-label" for="session-date">{{ t('scheduling.date') }}</label
          ><input id="session-date" v-model="form.date" class="form-control" type="date" required />
        </div>
        <div class="col-sm-6">
          <label class="form-label" for="session-start">{{ t('scheduling.start') }}</label
          ><input
            id="session-start"
            v-model="form.startTime"
            class="form-control"
            type="time"
            required
          />
        </div>
        <div class="col-sm-6">
          <label class="form-label" for="session-end">{{ t('scheduling.end') }}</label
          ><input
            id="session-end"
            v-model="form.endTime"
            class="form-control"
            type="time"
            required
          />
        </div>
        <div class="col-12">
          <label class="form-label" for="session-room">{{ t('scheduling.room') }}</label
          ><select id="session-room" v-model="form.roomId" class="form-select">
            <option :value="null">{{ t('scheduling.noRoom') }}</option>
            <option v-for="room in rooms" :key="room.id" :value="room.id">
              {{ room.name }} · {{ room.siteName }}
            </option>
          </select>
        </div>
      </div>
      <template v-if="form.op === 'holiday' || form.op === 'remove_holiday'">
        <label class="form-label" for="holiday-date">{{ t('scheduling.holidayDate') }}</label
        ><input
          id="holiday-date"
          v-model="form.date"
          class="form-control mb-3"
          type="date"
          required
        />
        <template v-if="form.op === 'holiday'"
          ><label class="form-label" for="holiday-name">{{ t('scheduling.holidayName') }}</label
          ><input
            id="holiday-name"
            v-model="form.name"
            class="form-control"
            maxlength="200"
            required
        /></template>
      </template>
    </form>
    <template #footer>
      <button
        type="button"
        class="btn btn-outline-secondary"
        :disabled="busy"
        @click="emit('close')"
      >
        {{ t('common.close') }}
      </button>
      <template v-if="preview">
        <button
          class="btn btn-outline-secondary"
          type="button"
          data-testid="schedule-cancel-preview"
          :disabled="busy"
          @click="preview = null"
        >
          {{ t('scheduling.back') }}
        </button>
        <button
          class="btn btn-primary"
          type="button"
          data-testid="schedule-confirm"
          :disabled="busy"
          @click="confirm"
        >
          {{ t('scheduling.confirm') }}
        </button>
      </template>
      <button
        v-else
        type="submit"
        form="schedule-change-form"
        class="btn btn-primary"
        data-testid="schedule-preview"
        :disabled="busy"
      >
        {{ t('scheduling.preview') }}
      </button>
    </template>
  </ModalDialog>
</template>
