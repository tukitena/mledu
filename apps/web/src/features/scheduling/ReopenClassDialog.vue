<script setup lang="ts">
import { ClassSchedule, type ScheduleChange } from '@mledu/contracts/scheduling'
import { Room } from '@mledu/contracts/catalogs'
import { z } from 'zod'
import { onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { apiRequest } from '../../app/session'
import { describeError, type DescribedError } from '../../app/errors'
import ModalDialog from '../../components/ModalDialog.vue'
import ErrorAlert from '../../components/ErrorAlert.vue'
import ScheduleChangeDialog from './ScheduleChangeDialog.vue'
const props = defineProps<{ classId: string; expectedVersion: number }>()
const emit = defineEmits<{ close: []; saved: [] }>()
const { t } = useI18n()
const schedule = ref<ClassSchedule | null>(null)
const rooms = ref<Room[]>([])
const change = ref<ScheduleChange | null>(null)
const error = ref<DescribedError | null>(null)
onMounted(async () => {
  try {
    const [value, activeRooms] = await Promise.all([
      apiRequest(`/v1/classes/${props.classId}/schedule`, { schema: ClassSchedule }),
      apiRequest('/v1/rooms', { schema: z.array(Room) }),
    ])
    schedule.value = value
    rooms.value = activeRooms
    change.value = {
      op: 'reopen',
      expectedVersion: props.expectedVersion,
      weekly: null,
      adjustments: value.sessions
        .filter(
          (item) =>
            item.status === 'removed_class' && new Date(item.startsAt).getTime() > Date.now(),
        )
        .map((item) => ({
          sessionId: item.id,
          date: item.date,
          startTime: item.startTime,
          endTime: item.endTime,
          roomId: item.roomId,
        })),
    }
  } catch (cause) {
    error.value = describeError(cause)
  }
})
</script>
<template>
  <ScheduleChangeDialog
    v-if="schedule && change"
    :class-id="classId"
    :initial="change"
    :rooms="rooms"
    :weekly="schedule.weekly"
    @close="emit('close')"
    @saved="emit('saved')"
  />
  <ModalDialog v-else :title="t('scheduling.op.reopen')" @close="emit('close')"
    ><ErrorAlert :error="error" />
    <p v-if="!error">{{ t('common.loading') }}</p></ModalDialog
  >
</template>
