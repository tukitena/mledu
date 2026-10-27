<script setup lang="ts">
import { Password } from '@mledu/contracts/auth'
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'
import PasswordField from './PasswordField.vue'

/** New password + confirmation (AUTH-01/02/08): 8+ characters, no composition rules. */
defineProps<{ submitLabel: string; busy: boolean }>()
const emit = defineEmits<{ submit: [password: string] }>()
const { t } = useI18n()
const password = ref('')
const confirmation = ref('')
const problem = ref<'policy' | 'mismatch' | null>(null)

function submit() {
  problem.value = !Password.safeParse(password.value).success
    ? 'policy'
    : password.value !== confirmation.value
      ? 'mismatch'
      : null
  if (!problem.value) emit('submit', password.value)
}
</script>

<template>
  <form class="auth-form" novalidate @submit.prevent="submit">
    <PasswordField
      id="new-password"
      v-model="password"
      :label="t('auth.newPassword')"
      autocomplete="new-password"
      :hint="t('auth.passwordHint')"
      :invalid="problem === 'policy' ? t('errors.validation_failed') : undefined"
    />
    <PasswordField
      id="confirm-password"
      v-model="confirmation"
      :label="t('auth.confirmPassword')"
      autocomplete="new-password"
      :invalid="problem === 'mismatch' ? t('auth.mismatch') : undefined"
    />
    <button type="submit" class="btn btn-primary w-100" :disabled="busy">
      <span v-if="busy" class="spinner-border spinner-border-sm me-2" aria-hidden="true"></span>
      {{ submitLabel }}
    </button>
  </form>
</template>
