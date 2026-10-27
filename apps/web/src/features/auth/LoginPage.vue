<script setup lang="ts">
import { HealthResponse } from '@mledu/contracts/common'
import { onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute, useRouter } from 'vue-router'
import { describeError, type DescribedError } from '../../app/errors'
import { apiRequest, endedReason, signIn } from '../../app/session'
import AuthLayout from '../../components/AuthLayout.vue'
import ErrorAlert from '../../components/ErrorAlert.vue'
import FloatingAlert from '../../components/FloatingAlert.vue'
import PasswordField from '../../components/PasswordField.vue'

const { t } = useI18n()
const route = useRoute()
const router = useRouter()
const email = ref('')
const password = ref('')
const submitting = ref(false)
const invalidCredentials = ref(false)
const error = ref<DescribedError | null>(null)
const apiState = ref<'checking' | 'ok' | 'unavailable'>('checking')

onMounted(async () => {
  try {
    await apiRequest('/v1/health', { schema: HealthResponse })
    apiState.value = 'ok'
  } catch {
    apiState.value = 'unavailable'
  }
})

async function submit() {
  submitting.value = true
  invalidCredentials.value = false
  error.value = null
  try {
    const profile = await signIn(email.value, password.value)
    if (!profile) throw new Error('profile_unavailable')
    const redirect = typeof route.query.redirect === 'string' ? route.query.redirect : null
    await router.replace(
      profile.mustChangePassword
        ? { name: 'change-password' }
        : redirect?.startsWith('/') && !redirect.startsWith('//')
          ? redirect
          : { name: 'dashboard' },
    )
  } catch (cause) {
    const code = (cause as { code?: string }).code
    if (code === 'invalid_credentials') invalidCredentials.value = true
    else error.value = describeError(cause)
  } finally {
    submitting.value = false
  }
}
</script>

<template>
  <AuthLayout :title="t('auth.login.title')" :subtitle="t('auth.login.subtitle')">
    <div v-if="endedReason && !error" class="alert alert-warning py-2 px-3 small" role="status">
      {{ t(`errors.${endedReason}`) }}
    </div>
    <FloatingAlert
      :message="invalidCredentials ? t('auth.login.invalid') : null"
      variant="danger"
    />
    <ErrorAlert :error="error" />
    <form class="auth-form" novalidate @submit.prevent="submit">
      <div class="mb-3">
        <label class="form-label" for="login-email">{{ t('auth.login.email') }}</label>
        <input
          id="login-email"
          v-model="email"
          type="email"
          class="form-control"
          autocomplete="username"
          required
        />
      </div>
      <div class="form-label-row">
        <span></span>
        <RouterLink :to="{ name: 'forgot-password' }">{{ t('auth.login.forgot') }}</RouterLink>
      </div>
      <PasswordField
        id="login-password"
        v-model="password"
        :label="t('auth.login.password')"
        autocomplete="current-password"
      />
      <button
        type="submit"
        class="btn btn-primary w-100"
        :disabled="submitting || !email || !password"
      >
        <span
          v-if="submitting"
          class="spinner-border spinner-border-sm me-2"
          aria-hidden="true"
        ></span>
        {{ submitting ? t('auth.login.submitting') : t('auth.login.submit') }}
      </button>
    </form>
    <p class="auth-footnote" data-testid="api-status" :data-state="apiState">
      <span class="status-dot" :class="`status-${apiState}`" aria-hidden="true"></span>
      API: {{ apiState }}
    </p>
  </AuthLayout>
</template>
