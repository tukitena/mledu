<script setup lang="ts">
import PreferenceControls from './PreferenceControls.vue'

defineProps<{ title: string; subtitle?: string }>()
</script>

<template>
  <div class="auth-layout">
    <main class="auth-main">
      <div class="auth-topbar">
        <PreferenceControls />
      </div>
      <div class="auth-body">
        <div class="auth-heading">
          <h1>{{ title }}</h1>
          <p v-if="subtitle">{{ subtitle }}</p>
        </div>
        <slot />
      </div>
    </main>
    <aside class="auth-aside" aria-hidden="true"></aside>
  </div>
</template>
