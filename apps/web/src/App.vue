<script setup lang="ts">
import { watch } from 'vue'
import { RouterView, useRoute, useRouter } from 'vue-router'
import { profile, workspaces } from './app/session'

const route = useRoute()
const router = useRouter()

// Applies session and permission changes noticed while a page is open: sign-out,
// a forced password change, or a type change that removes the current workspace.
watch(profile, (current) => {
  if (route.meta.public) return
  if (!current) void router.replace({ name: 'login' })
  else if (current.mustChangePassword) void router.replace({ name: 'change-password' })
  else if (route.meta.workspace && !workspaces.value.includes(route.meta.workspace)) {
    void router.replace({ name: 'dashboard' })
  }
})
</script>

<template>
  <div id="app-alerts" class="app-alerts"></div>
  <RouterView />
</template>
