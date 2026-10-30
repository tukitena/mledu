<script setup lang="ts">
import DateInput from '../../components/DateInput.vue'
import { formatIsoDate } from '../../lib/format'
import { ClassSchedule, type ClassSession, type ScheduleChange } from '@mledu/contracts/scheduling'
import type { ClassDetail } from '@mledu/contracts/classes'
import { Room } from '@mledu/contracts/catalogs'
import { computed, onBeforeUnmount, onMounted, ref, toRaw, watch } from 'vue'
import { z } from 'zod'
import { useI18n } from 'vue-i18n'
import { apiRequest, workspace } from '../../app/session'
import { describeError, type DescribedError } from '../../app/errors'
import ErrorAlert from '../../components/ErrorAlert.vue'
import FloatingAlert from '../../components/FloatingAlert.vue'
import AttendanceDialog from '../attendance/AttendanceDialog.vue'
import ScheduleChangeDialog from './ScheduleChangeDialog.vue'
import StaffWarnings from './StaffWarnings.vue'
import RowActionMenu, { type RowAction } from '../../components/RowActionMenu.vue'
const props = defineProps<{ klass: ClassDetail }>()
const { t } = useI18n()
const data = ref<ClassSchedule | null>(null)
const rooms = ref<Room[]>([])
const error = ref<DescribedError | null>(null)
const notice = ref<string | null>(null)
const editing = ref<ScheduleChange | null>(null)
const attending = ref<ClassSession | null>(null)
const month = ref(new Date(Date.now() + 7 * 3600_000).toISOString().slice(0, 7))
const site = ref('')
const removed = ref(false)
const now = ref(Date.now())
let clock: ReturnType<typeof setInterval> | undefined
onMounted(() => {
  void load()
  clock = setInterval(() => {
    now.value = Date.now()
  }, 15_000)
})
onBeforeUnmount(() => clearInterval(clock))
watch(
  () => props.klass.rowVersion,
  () => void load(),
)
const today = () => new Date(now.value + 7 * 3600_000).toISOString().slice(0, 10)
const canSchedule = computed(
  () =>
    !props.klass.deleted &&
    props.klass.adminState === 'open' &&
    (workspace.value === 'admin' ||
      workspace.value === 'receptionist' ||
      props.klass.myRole === 'teacher'),
)
const canAttend = (item: ClassSession) =>
  !props.klass.deleted &&
  item.status === 'scheduled' &&
  new Date(item.startsAt).getTime() < now.value
const sessions = computed(
  () =>
    data.value?.sessions.filter(
      (item) =>
        item.date.slice(0, 7) === month.value &&
        (!site.value || item.siteName === site.value) &&
        (removed.value || !item.status.startsWith('removed_')),
    ) ?? [],
)
const sites = computed(() => [
  ...new Set(
    data.value?.sessions.map((item) => item.siteName).filter((name): name is string => !!name),
  ),
])
async function load() {
  error.value = null
  try {
    const [schedule, activeRooms] = await Promise.all([
      apiRequest(`/v1/classes/${props.klass.id}/schedule`, { schema: ClassSchedule }),
      apiRequest('/v1/rooms', { schema: z.array(Room) }),
    ])
    data.value = schedule
    rooms.value = activeRooms
  } catch (cause) {
    error.value = describeError(cause)
  }
}
function weekly() {
  const appliesOn = today()
  const revision = [...(data.value?.weekly ?? [])]
    .reverse()
    .find((item) => item.appliesOn <= appliesOn)
  editing.value = { op: 'weekly', appliesOn, slots: structuredClone(toRaw(revision?.slots ?? [])) }
}
function move(item: ClassSession) {
  editing.value = {
    op: 'move',
    sessionId: item.id,
    expectedVersion: item.rowVersion,
    date: item.date,
    startTime: item.startTime,
    endTime: item.endTime,
    roomId: item.roomId,
  }
}
function actionsFor(item: ClassSession): RowAction[] {
  const actions: RowAction[] = []
  const startsAt = new Date(item.startsAt).getTime()
  if (canSchedule.value && startsAt > now.value && ['scheduled', 'off'].includes(item.status)) {
    const key = item.status === 'off' ? 'resume' : 'off'
    actions.push(
      { key: 'move', label: t('scheduling.op.move') },
      { key, label: t(`scheduling.op.${key}`) },
    )
  }
  if (item.status === 'scheduled' && startsAt < now.value) {
    actions.push({ key: 'attendance', label: t('attendance.title') })
  }
  return actions
}
function onAction(item: ClassSession, key: string) {
  if (key === 'move') move(item)
  else if (key === 'off' || key === 'resume') {
    editing.value = { op: key, sessionId: item.id, expectedVersion: item.rowVersion }
  } else if (key === 'attendance') attending.value = item
}
async function saved() {
  editing.value = null
  notice.value = t('scheduling.saved')
  await load()
}
</script>
<template>
  <div class="schedule-panel p-3 p-lg-4">
    <FloatingAlert :message="notice" />
    <ErrorAlert :error="error" />
    <div class="d-flex flex-wrap align-items-center gap-2 mb-3">
      <button
        v-if="canSchedule"
        class="btn btn-outline-primary"
        type="button"
        data-testid="schedule-weekly"
        @click="weekly"
      >
        {{ t('scheduling.op.weekly') }}
      </button>
      <button
        v-if="canSchedule"
        class="btn btn-primary"
        type="button"
        data-testid="schedule-makeup"
        @click="
          editing = {
            op: 'makeup',
            date: today(),
            startTime: '09:00',
            endTime: '10:00',
            roomId: null,
          }
        "
      >
        <i class="bi bi-plus-lg me-1" aria-hidden="true"></i>{{ t('scheduling.op.makeup') }}
      </button>
      <button
        v-if="workspace === 'admin'"
        class="btn btn-outline-secondary"
        type="button"
        @click="editing = { op: 'holiday', date: today(), name: '' }"
      >
        {{ t('scheduling.op.holiday') }}
      </button>
      <button class="btn btn-outline-secondary ms-sm-auto" type="button" @click="load">
        {{ t('scheduling.refresh') }}
      </button>
    </div>
    <StaffWarnings :warnings="data?.warnings ?? []" />
    <form class="row g-3 mb-3" @submit.prevent="load">
      <div class="col-sm-6">
        <label for="schedule-month" class="form-label">{{ t('scheduling.month') }}</label
        ><DateInput id="schedule-month" v-model="month" mode="month" class="form-control" />
      </div>
      <div class="col-sm-6">
        <label for="schedule-site" class="form-label">{{ t('scheduling.site') }}</label
        ><select id="schedule-site" v-model="site" class="form-select">
          <option value="">{{ t('scheduling.allSites') }}</option>
          <option v-for="name in sites" :key="name">{{ name }}</option>
        </select>
      </div>
      <div class="col-12">
        <label class="form-check-label"
          ><input v-model="removed" type="checkbox" class="form-check-input me-2" />{{
            t('scheduling.showRemoved')
          }}</label
        >
      </div>
    </form>
    <div class="table-responsive">
      <table class="table table-hover align-middle mb-0 data-table" data-testid="sessions-table">
        <thead>
          <tr>
            <th scope="col">{{ t('scheduling.date') }}</th>
            <th scope="col">{{ t('scheduling.time') }}</th>
            <th scope="col">{{ t('scheduling.room') }}</th>
            <th scope="col">{{ t('scheduling.status') }}</th>
            <th scope="col" class="text-end">{{ t('common.actions') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="item in sessions" :key="item.id" :data-session="item.id">
            <td class="text-nowrap">
              {{ formatIsoDate(item.date) }}<br /><small class="text-body-secondary">{{
                t(`scheduling.kind.${item.kind}`)
              }}</small>
            </td>
            <td class="text-nowrap">{{ item.startTime }}–{{ item.endTime }}</td>
            <td>
              {{ item.roomName ?? t('scheduling.noRoom') }}<br /><small
                class="text-body-secondary"
                >{{ item.siteName }}</small
              >
            </td>
            <td>
              <span
                class="badge"
                :class="
                  item.status === 'scheduled'
                    ? 'bg-success-subtle text-success-emphasis'
                    : 'bg-secondary-subtle text-secondary-emphasis'
                "
                >{{ t(`scheduling.state.${item.status}`) }}</span
              >
            </td>
            <td class="text-end">
              <RowActionMenu
                v-if="actionsFor(item).length"
                :id="`session-${item.id}`"
                :label="`${t('common.actions')}: ${formatIsoDate(item.date)} ${item.startTime}–${item.endTime}`"
                :items="actionsFor(item)"
                @select="onAction(item, $event)"
              />
            </td>
          </tr>
        </tbody>
      </table>
      <p v-if="data && !sessions.length" class="text-body-secondary">{{ t('scheduling.empty') }}</p>
    </div>
    <template v-if="data?.holidays.length">
      <h3 class="h6 mt-4">{{ t('scheduling.holidays') }}</h3>
      <ul class="list-group list-group-flush">
        <li
          v-for="holiday in data.holidays"
          :key="holiday.date"
          class="list-group-item d-flex flex-wrap gap-2 align-items-center px-0"
        >
          {{ formatIsoDate(holiday.date) }} · {{ holiday.name }}
          <button
            v-if="workspace === 'admin'"
            type="button"
            class="btn btn-sm btn-outline-secondary ms-auto"
            @click="editing = { op: 'remove_holiday', date: holiday.date }"
          >
            {{ t('scheduling.op.remove_holiday') }}
          </button>
        </li>
      </ul>
    </template>
    <ScheduleChangeDialog
      v-if="editing && data"
      :class-id="klass.id"
      :initial="editing"
      :rooms="rooms"
      :weekly="data.weekly"
      @close="editing = null"
      @saved="saved"
    />
    <AttendanceDialog
      v-if="attending"
      :session-id="attending.id"
      :readonly="!canAttend(attending)"
      @close="attending = null"
      @saved="load"
    />
  </div>
</template>
