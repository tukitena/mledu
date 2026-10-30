<script setup lang="ts">
import { ClassStudent } from '@mledu/contracts/enrollments'
import { ref, watch } from 'vue'
import { RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { z } from 'zod'
import { apiRequest } from '../../app/session'
import { describeError, type DescribedError } from '../../app/errors'
import ErrorAlert from '../../components/ErrorAlert.vue'
import { formatIsoDate } from '../../lib/format'
const props = defineProps<{ studentId: string }>()
const { t } = useI18n()
const items = ref<ClassStudent[]>([])
const error = ref<DescribedError | null>(null)
const loading = ref(false)
watch(
  () => props.studentId,
  async (id, _old, onCleanup) => {
    let active = true
    onCleanup(() => {
      active = false
    })
    items.value = []
    error.value = null
    loading.value = true
    try {
      const result = await apiRequest(`/v1/students/${id}/classes`, {
        schema: z.array(ClassStudent),
      })
      if (active) items.value = result
    } catch (cause) {
      if (active) error.value = describeError(cause)
    } finally {
      if (active) loading.value = false
    }
  },
  { immediate: true },
)
</script>
<template>
  <section class="border-top pt-3 mt-3">
    <h3 class="h6">{{ t('enrollments.history') }}</h3>
    <ErrorAlert :error="error" />
    <p v-if="!items.length" class="small text-body-secondary">
      {{ t(loading ? 'common.loading' : 'enrollments.empty') }}
    </p>
    <div v-for="record in items" :key="record.id" class="mb-3">
      <RouterLink :to="`/classes/${record.classId}?tab=students`">{{
        record.className
      }}</RouterLink>
      <span v-if="record.deleted" class="badge text-bg-secondary ms-2">{{
        t('enrollments.recordDeleted')
      }}</span>
      <span v-if="record.classDeleted" class="badge text-bg-secondary ms-2">{{
        t('enrollments.classDeleted')
      }}</span>
      <span v-else-if="record.classAdminState === 'closed'" class="badge text-bg-secondary ms-2">{{
        t('classes.closed')
      }}</span>
      <div v-for="part in record.participations" :key="part.id" class="small mt-1">
        {{ formatIsoDate(part.joinDate) }} –
        {{ part.leaveDate ? formatIsoDate(part.leaveDate) : '…' }} ·
        {{ t(`enrollments.status.${part.status}`) }}
        <div v-if="part.endReason">{{ part.endReason }}</div>
        <div v-if="part.note" class="text-preline text-body-secondary">{{ part.note }}</div>
      </div>
    </div>
  </section>
</template>
