<script setup lang="ts">
import { AcceptedResponse } from '@mledu/contracts/auth'
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { describeError, type DescribedError } from '../../app/errors'
import { apiRequest } from '../../app/session'
import AuthLayout from '../../components/AuthLayout.vue'
import ErrorAlert from '../../components/ErrorAlert.vue'
import FloatingAlert from '../../components/FloatingAlert.vue'

const { t } = useI18n()
const email = ref('')
const sent = ref(false)
const submitting = ref(false)
const error = ref<DescribedError | null>(null)

async function submit() {
  submitting.value = true
  error.value = null
  try {
    await apiRequest('/v1/auth/password-reset', {
      method: 'POST',
      body: { email: email.value },
      schema: AcceptedResponse,
    })
    sent.value = true
  } catch (cause) {
    error.value = describeError(cause)
  } finally {
    submitting.value = false
  }
}
</script>

<template>
  <AuthLayout :title="t('auth.forgot.title')" :subtitle="t('auth.forgot.subtitle')">
    <FloatingAlert :message="sent ? t('auth.forgot.sent') : null" data-testid="reset-sent" />
    <ErrorAlert :error="error" />
    <form v-if="!sent" class="auth-form" novalidate @submit.prevent="submit">
      <div class="mb-3">
        <label class="form-label" for="forgot-email">{{ t('auth.login.email') }}</label>
        <input
          id="forgot-email"
          v-model="email"
          type="email"
          class="form-control"
          autocomplete="username"
          required
        />
      </div>
      <button type="submit" class="btn btn-primary w-100" :disabled="submitting || !email">
        {{ t('auth.forgot.submit') }}
      </button>
    </form>
    <p class="auth-footnote">
      <RouterLink :to="{ name: 'login' }">{{ t('auth.forgot.back') }}</RouterLink>
    </p>
  </AuthLayout>
</template>
