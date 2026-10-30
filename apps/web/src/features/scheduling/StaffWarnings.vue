<script setup lang="ts">
import type { ClassSchedule } from '@mledu/contracts/scheduling'
import { useI18n } from 'vue-i18n'
defineProps<{ warnings: ClassSchedule['warnings'] }>()
const { t, locale } = useI18n()
const instant = (value: string) =>
  new Intl.DateTimeFormat(locale.value, {
    dateStyle: 'short',
    timeStyle: 'short',
    timeZone: 'Asia/Ho_Chi_Minh',
  }).format(new Date(value))
</script>
<template>
  <div v-if="warnings.length" class="alert alert-warning" role="status">
    <strong>{{ t('scheduling.staffWarning') }}</strong>
    <ul class="mb-0 mt-1">
      <li v-for="(item, index) in warnings" :key="index">
        {{ item.fullName }} · {{ item.className }} · {{ instant(item.startsAt) }} –
        {{ instant(item.endsAt) }}
      </li>
    </ul>
  </div>
</template>
