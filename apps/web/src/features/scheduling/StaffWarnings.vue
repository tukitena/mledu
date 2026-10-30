<script setup lang="ts">
import { formatInstant } from '../../lib/format'
import type { ClassSchedule } from '@mledu/contracts/scheduling'
import { useI18n } from 'vue-i18n'
defineProps<{ warnings: ClassSchedule['warnings'] }>()
const { t } = useI18n()
const instant = formatInstant
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
