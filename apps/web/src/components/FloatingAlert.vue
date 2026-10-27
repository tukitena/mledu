<script setup lang="ts">
import { onBeforeUnmount, ref, watch } from 'vue'

defineOptions({ inheritAttrs: false })
const props = withDefaults(
  defineProps<{
    message: string | null
    detail?: string
    variant?: 'success' | 'danger' | 'warning' | 'info'
  }>(),
  { variant: 'success', detail: '' },
)

const visible = ref(false)
const icons = {
  success: 'bi-check-circle',
  danger: 'bi-exclamation-circle',
  warning: 'bi-exclamation-triangle',
  info: 'bi-info-circle',
}
let timer: ReturnType<typeof setTimeout> | undefined
let hovered = false
let focused = false

function stopTimer() {
  clearTimeout(timer)
}
function startTimer() {
  stopTimer()
  if (visible.value && !hovered && !focused) timer = setTimeout(close, 5000)
}
function close() {
  visible.value = false
  hovered = false
  focused = false
  stopTimer()
}
function onPointerEnter() {
  hovered = true
  stopTimer()
}
function onPointerLeave() {
  hovered = false
  startTimer()
}
function onFocusIn() {
  focused = true
  stopTimer()
}
function onFocusOut(event: FocusEvent) {
  if ((event.currentTarget as HTMLElement).contains(event.relatedTarget as Node | null)) return
  focused = false
  startTimer()
}

watch(
  () => [props.message, props.detail],
  () => {
    if (!props.message) return close()
    visible.value = !!props.message
    startTimer()
  },
  { immediate: true },
)
onBeforeUnmount(stopTimer)
</script>

<template>
  <Teleport to="#app-alerts">
    <div
      v-if="visible && message"
      v-bind="$attrs"
      class="floating-alert"
      :class="`floating-alert-${variant}`"
      :role="variant === 'danger' || variant === 'warning' ? 'alert' : 'status'"
      aria-atomic="true"
      @pointerenter="onPointerEnter"
      @pointerleave="onPointerLeave"
      @focusin="onFocusIn"
      @focusout="onFocusOut"
    >
      <i class="bi floating-alert-icon" :class="icons[variant]" aria-hidden="true"></i>
      <div class="floating-alert-content">
        <div>{{ message }}</div>
        <small v-if="detail" class="text-body-secondary">{{ detail }}</small>
      </div>
      <button
        type="button"
        class="btn-close"
        :aria-label="$t('common.close')"
        @click="close"
      ></button>
    </div>
  </Teleport>
</template>
