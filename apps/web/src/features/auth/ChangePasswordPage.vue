<script setup lang="ts">
import { PasswordChangedResponse } from '@mledu/contracts/auth'
import { computed, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import { describeError, type DescribedError } from '../../app/errors'
import { apiRequest, loadProfile, profile, signOut } from '../../app/session'
import AuthLayout from '../../components/AuthLayout.vue'
import ErrorAlert from '../../components/ErrorAlert.vue'
import NewPasswordForm from '../../components/NewPasswordForm.vue'

// Forced after a temporary password (AUTH-01/02) or chosen from the profile (AUTH-08).
const { t } = useI18n()
const router = useRouter()
const forced = computed(() => profile.value?.mustChangePassword ?? false)
const busy = ref(false)
const error = ref<DescribedError | null>(null)

async function submit(password: string) {
  busy.value = true
  error.value = null
  try {
    await apiRequest('/v1/me/password', {
      method: 'POST',
      body: { password },
      schema: PasswordChangedResponse,
    })
    await loadProfile()
    await router.replace({ name: 'dashboard' })
  } catch (cause) {
    error.value = describeError(cause)
  } finally {
    busy.value = false
  }
}

async function leave() {
  await signOut()
  await router.replace({ name: 'login' })
}
</script>

<template>
  <AuthLayout
    :title="t('auth.change.title')"
    :subtitle="forced ? t('auth.change.forcedSubtitle') : t('auth.change.subtitle')"
  >
    <ErrorAlert :error="error" />
    <NewPasswordForm :submit-label="t('auth.change.submit')" :busy="busy" @submit="submit" />
    <p class="auth-footnote">
      <RouterLink v-if="!forced" :to="{ name: 'profile' }">{{ t('common.back') }}</RouterLink>
      <button v-else type="button" class="btn btn-link btn-sm p-0" @click="leave">
        {{ t('nav.signOut') }}
      </button>
    </p>
  </AuthLayout>
</template>
