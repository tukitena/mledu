<script setup lang="ts">
import { phoneKey } from '@mledu/contracts/normalize'
import { useI18n } from 'vue-i18n'

// Editable list of phone numbers (STU-04). Numbers are checked with the same
// key as the backend so mistakes show before saving; the API still decides.
const props = defineProps<{ id: string; label: string; max?: number }>()
const phones = defineModel<string[]>({ required: true })
const { t } = useI18n()

const invalid = (value: string) => value.trim() !== '' && phoneKey(value) === null

function add() {
  phones.value = [...phones.value, '']
}
function remove(index: number) {
  phones.value = phones.value.filter((_, position) => position !== index)
}
function update(index: number, value: string) {
  phones.value = phones.value.map((phone, position) => (position === index ? value : phone))
}
</script>

<template>
  <fieldset class="phone-list">
    <legend class="form-label">
      {{ props.label }}
      <span class="text-body-secondary">({{ t('common.optional') }})</span>
    </legend>
    <div v-for="(phone, index) in phones" :key="index" class="input-group mb-2 has-validation">
      <span class="input-group-text"><i class="bi bi-telephone" aria-hidden="true"></i></span>
      <input
        :id="`${props.id}-${index}`"
        class="form-control"
        :class="{ 'is-invalid': invalid(phone) }"
        :value="phone"
        inputmode="tel"
        maxlength="32"
        :aria-label="`${props.label} ${index + 1}`"
        @input="update(index, ($event.target as HTMLInputElement).value)"
      />
      <button
        type="button"
        class="btn btn-outline-secondary"
        :aria-label="t('students.removePhone')"
        @click="remove(index)"
      >
        <i class="bi bi-x-lg" aria-hidden="true"></i>
      </button>
      <div class="invalid-feedback">{{ t('students.invalidPhone') }}</div>
    </div>
    <button
      v-if="phones.length < (props.max ?? 10)"
      type="button"
      class="btn btn-sm btn-outline-secondary"
      :data-testid="`${props.id}-add`"
      @click="add"
    >
      <i class="bi bi-plus-lg me-1" aria-hidden="true"></i>{{ t('students.addPhone') }}
    </button>
  </fieldset>
</template>
