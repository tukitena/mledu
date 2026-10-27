<script setup lang="ts">
import { RouterLink } from 'vue-router'
</script>

<template>
  <main class="container py-5">
    <h1 class="h4">404</h1>
    <p>{{ $t('notFound.title') }}</p>
    <RouterLink to="/">{{ $t('notFound.back') }}</RouterLink>
  </main>
</template>
