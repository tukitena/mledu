<script setup lang="ts">
import { nextTick, onBeforeUnmount, onMounted, ref } from 'vue'

defineProps<{ title: string }>()
const emit = defineEmits<{ close: [] }>()
const dialog = ref<HTMLElement>()

const onKey = (event: KeyboardEvent) => {
  if (event.key === 'Escape') emit('close')
}
onMounted(async () => {
  document.addEventListener('keydown', onKey)
  document.body.classList.add('modal-open')
  await nextTick()
  dialog.value?.querySelector<HTMLElement>('input, select, textarea, button')?.focus()
})
onBeforeUnmount(() => {
  document.removeEventListener('keydown', onKey)
  document.body.classList.remove('modal-open')
})
</script>

<template>
  <div class="modal d-block" tabindex="-1" role="dialog" aria-modal="true" :aria-label="title">
    <div ref="dialog" class="modal-dialog modal-dialog-centered modal-dialog-scrollable">
      <div class="modal-content">
        <div class="modal-header">
          <h2 class="modal-title h5">{{ title }}</h2>
          <button
            type="button"
            class="btn-close"
            :aria-label="$t('common.close')"
            @click="emit('close')"
          ></button>
        </div>
        <div class="modal-body">
          <slot />
        </div>
        <div v-if="$slots.footer" class="modal-footer">
          <slot name="footer" />
        </div>
      </div>
    </div>
  </div>
  <div class="modal-backdrop show" @click="emit('close')"></div>
</template>
