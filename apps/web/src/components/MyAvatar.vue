<script setup lang="ts">
import { onBeforeUnmount, ref, watch } from 'vue'
import { apiFetch } from '../app/session'

/**
 * The signed-in user's avatar, fetched through the API (permission checked on
 * each request) and cached by path for the page's lifetime.
 */
const props = defineProps<{ path: string | null; name: string; size?: number }>()
const src = ref<string | null>(null)

const initials = () =>
  props.name
    .split(/\s+/)
    .filter(Boolean)
    .slice(-2)
    .map((part) => part[0]!.toUpperCase())
    .join('')

watch(
  () => props.path,
  async (path) => {
    if (src.value) URL.revokeObjectURL(src.value)
    src.value = null
    if (!path) return
    const response = await apiFetch('/v1/me/avatar').catch(() => null)
    if (response?.ok && props.path === path) src.value = URL.createObjectURL(await response.blob())
  },
  { immediate: true },
)
onBeforeUnmount(() => {
  if (src.value) URL.revokeObjectURL(src.value)
})
</script>

<template>
  <img
    v-if="src"
    :src="src"
    class="avatar"
    :style="{ width: `${size ?? 32}px`, height: `${size ?? 32}px` }"
    :alt="$t('profile.avatar.alt', { name })"
    data-testid="avatar-image"
  />
  <span
    v-else
    class="avatar avatar-initials"
    :style="{
      width: `${size ?? 32}px`,
      height: `${size ?? 32}px`,
      fontSize: `${(size ?? 32) / 2.6}px`,
    }"
    aria-hidden="true"
    >{{ initials() }}</span
  >
</template>
