<script setup lang="ts">
import PreferenceControls from './PreferenceControls.vue'

defineProps<{ title: string; subtitle?: string }>()
</script>

<template>
  <div class="auth-layout">
    <main class="auth-main">
      <div class="auth-topbar">
        <RouterLink class="auth-brand" to="/">
          <i class="bi bi-mortarboard-fill" aria-hidden="true"></i>
          <span>{{ $t('app.name') }}</span>
        </RouterLink>
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
    <aside class="auth-aside" aria-hidden="true">
      <div class="auth-aside-inner">
        <p class="auth-quote">{{ $t('app.tagline') }}</p>
      </div>
    </aside>
  </div>
</template>
