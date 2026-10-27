<script setup lang="ts">
import { ref } from 'vue'

defineProps<{
  id: string
  label: string
  autocomplete: string
  hint?: string | undefined
  invalid?: string | undefined
}>()
const model = defineModel<string>({ required: true })
const visible = ref(false)
</script>

<template>
  <div class="mb-3">
    <label class="form-label" :for="id">{{ label }}</label>
    <div class="password-field">
      <input
        :id="id"
        v-model="model"
        :type="visible ? 'text' : 'password'"
        class="form-control"
        :class="{ 'is-invalid': invalid }"
        :autocomplete="autocomplete"
        :aria-describedby="hint ? `${id}-hint` : undefined"
        required
      />
      <button
        type="button"
        class="password-toggle"
        :aria-label="visible ? $t('auth.hidePassword') : $t('auth.showPassword')"
        @click="visible = !visible"
      >
        <i class="bi" :class="visible ? 'bi-eye-slash' : 'bi-eye'" aria-hidden="true"></i>
      </button>
      <div v-if="invalid" class="invalid-feedback">{{ invalid }}</div>
    </div>
    <div v-if="hint" :id="`${id}-hint`" class="form-text">{{ hint }}</div>
  </div>
</template>
