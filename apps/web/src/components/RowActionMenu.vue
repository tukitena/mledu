<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from 'vue'

export interface RowAction {
  key: string
  label: string
  danger?: boolean
}

// Metis row "⋯" menu. The native popover sits in the browser's top layer, so
// it is not clipped by the responsive table and follows its trigger on scroll.
const props = defineProps<{ id: string; label: string; items: RowAction[] }>()
const emit = defineEmits<{ select: [key: string] }>()
const trigger = ref<HTMLButtonElement>()
const menu = ref<HTMLElement>()
const position = ref({ left: '0px', top: '0px' })

function place() {
  if (!menu.value?.matches(':popover-open') || !trigger.value) return
  const anchor = trigger.value.getBoundingClientRect()
  const { width, height } = menu.value.getBoundingClientRect()
  const gap = 6
  const edge = 8
  const below = anchor.bottom + gap
  const top = below + height <= window.innerHeight - edge ? below : anchor.top - gap - height
  position.value = {
    left: `${Math.max(edge, Math.min(anchor.right - width, window.innerWidth - width - edge))}px`,
    top: `${Math.max(edge, Math.min(top, window.innerHeight - height - edge))}px`,
  }
}

function onViewportChange(event: Event) {
  if (event.target instanceof Node && menu.value?.contains(event.target)) return
  place()
}

function choose(key: string) {
  menu.value?.hidePopover()
  emit('select', key)
}

onMounted(() => {
  window.addEventListener('resize', onViewportChange)
  window.addEventListener('scroll', onViewportChange, true)
})
onBeforeUnmount(() => {
  window.removeEventListener('resize', onViewportChange)
  window.removeEventListener('scroll', onViewportChange, true)
})
</script>

<template>
  <div class="account-actions">
    <button
      ref="trigger"
      type="button"
      class="btn btn-outline-secondary row-action-toggle"
      :aria-label="props.label"
      :popovertarget="`row-menu-${props.id}`"
      :disabled="!props.items.length"
    >
      <i class="bi bi-three-dots" aria-hidden="true"></i
      ><i class="bi bi-caret-down-fill" aria-hidden="true"></i>
    </button>
    <div
      :id="`row-menu-${props.id}`"
      ref="menu"
      popover="auto"
      class="account-action-menu"
      :style="position"
      :aria-label="props.label"
      @toggle="place"
    >
      <button
        v-for="item in props.items"
        :key="item.key"
        type="button"
        class="user-menu-item"
        :class="{ 'text-danger': item.danger }"
        :data-action="item.key"
        @click="choose(item.key)"
      >
        {{ item.label }}
      </button>
    </div>
  </div>
</template>
