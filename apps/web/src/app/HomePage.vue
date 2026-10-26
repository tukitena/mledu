<script setup lang="ts">
import { HealthResponse } from '@mledu/contracts/common'
import { onMounted, ref } from 'vue'
import { ApiError } from '../lib/api-client'
import { api } from './api'

const state = ref<'checking' | 'ok' | 'unavailable'>('checking')
const detail = ref('')

onMounted(async () => {
  try {
    const health = await api.request('/v1/health', { schema: HealthResponse })
    state.value = 'ok'
    detail.value = `${health.environment} · ${health.version}`
  } catch (error) {
    state.value = 'unavailable'
    detail.value = error instanceof ApiError ? `${error.code} · ${error.requestId}` : ''
  }
})
</script>

<template>
  <main class="container py-5">
    <h1 class="h3 mb-3"><i class="bi bi-mortarboard me-2" aria-hidden="true"></i>MLedu</h1>
    <p class="text-body-secondary">
      Nền ứng dụng (GĐ 1). Chức năng nghiệp vụ được bổ sung từ GĐ 2.
    </p>
    <p data-testid="api-status" :data-state="state">
      <span
        class="badge"
        :class="
          state === 'ok'
            ? 'text-bg-success'
            : state === 'checking'
              ? 'text-bg-secondary'
              : 'text-bg-danger'
        "
      >
        API: {{ state }}
      </span>
      <small v-if="detail" class="ms-2 text-body-secondary">{{ detail }}</small>
    </p>
  </main>
</template>
