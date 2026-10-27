<script setup lang="ts">
import { PasswordChangedResponse } from '@mledu/contracts/auth'
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute, useRouter } from 'vue-router'
import { describeError, type DescribedError } from '../../app/errors'
import { apiRequest, signOut } from '../../app/session'
import AuthLayout from '../../components/AuthLayout.vue'
import ErrorAlert from '../../components/ErrorAlert.vue'
import FloatingAlert from '../../components/FloatingAlert.vue'
import NewPasswordForm from '../../components/NewPasswordForm.vue'

// Opened from the reset email. The token hash goes to the Worker together with
// the new password; this browser is never signed in by the link (AUTH-02).
const { t } = useI18n()
const route = useRoute()
const router = useRouter()
const link = ref<{ tokenHash: string; type: 'recovery' | 'magiclink' } | null>(null)
const busy = ref(false)
const done = ref(false)
const error = ref<DescribedError | null>(null)
// The Worker verified (and so used up) the link even when the new password was refused.
const linkUnusable = computed(
  () =>
    !link.value ||
    error.value?.code === 'reset_link_invalid' ||
    error.value?.code === 'password_unchanged',
)

onMounted(() => {
  const tokenHash = route.query.token_hash
  const type = route.query.type
  if (typeof tokenHash === 'string' && (type === 'recovery' || type === 'magiclink')) {
    link.value = { tokenHash, type }
  }
  // Keep the token out of the address bar and history.
  void router.replace({ name: 'reset-password' })
})

async function submit(password: string) {
  if (!link.value) return
  busy.value = true
  error.value = null
  try {
    await apiRequest('/v1/auth/password-reset/complete', {
      method: 'POST',
      body: { ...link.value, password },
      schema: PasswordChangedResponse,
    })
    // Every session ended, including any in this browser.
    await signOut()
    done.value = true
  } catch (cause) {
    error.value = describeError(cause)
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <AuthLayout :title="t('auth.reset.title')" :subtitle="t('auth.reset.subtitle')">
    <FloatingAlert v-if="done" :message="t('auth.reset.done')" data-testid="reset-done" />
    <template v-else>
      <div v-if="!link" class="alert alert-warning py-2 px-3 small" role="alert">
        {{ t('auth.reset.missingLink') }}
      </div>
      <ErrorAlert :error="error" />
      <NewPasswordForm
        v-if="!linkUnusable"
        :submit-label="t('auth.reset.submit')"
        :busy="busy"
        @submit="submit"
      />
    </template>
    <p class="auth-footnote d-flex gap-3 justify-content-center">
      <RouterLink :to="{ name: 'login' }">{{ t('auth.reset.toLogin') }}</RouterLink>
      <RouterLink v-if="!done && linkUnusable" :to="{ name: 'forgot-password' }">
        {{ t('auth.reset.requestNew') }}
      </RouterLink>
    </p>
  </AuthLayout>
</template>
