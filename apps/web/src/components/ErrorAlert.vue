<script setup lang="ts">
import type { DescribedError } from '../app/errors'
import FloatingAlert from './FloatingAlert.vue'

defineProps<{ error: DescribedError | null }>()
</script>

<template>
  <FloatingAlert
    :message="error ? $t(`errors.${error.code}`) : null"
    :detail="error?.requestId ? $t('errors.requestId', { id: error.requestId }) : ''"
    variant="danger"
    data-testid="error-alert"
  />
</template>
