<script setup lang="ts">
import {
  AVATAR_MAX_BYTES,
  AvatarContentType,
  AvatarUploadResponse,
  MyProfile,
} from '@mledu/contracts/profile'
import { reactive, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { describeError, type DescribedError } from '../../app/errors'
import { apiRequest, profile } from '../../app/session'
import ErrorAlert from '../../components/ErrorAlert.vue'
import FloatingAlert from '../../components/FloatingAlert.vue'
import MyAvatar from '../../components/MyAvatar.vue'

const { t } = useI18n()
const form = reactive({ fullName: '', phone: '', birthDate: '' })
const saving = ref(false)
const notice = ref<string | null>(null)
const error = ref<DescribedError | null>(null)
const avatarBusy = ref(false)
const avatarNotice = ref<string | null>(null)
const avatarError = ref<DescribedError | string | null>(null)
const fileInput = ref<HTMLInputElement>()

function reset(current: MyProfile | null) {
  if (!current) return
  form.fullName = current.fullName
  form.phone = current.phone ?? ''
  form.birthDate = current.birthDate ?? ''
}
watch(
  profile,
  (current, previous) => {
    // Keep unsaved input when only the periodic refresh ran.
    if (!previous || current?.rowVersion !== previous.rowVersion) reset(current)
  },
  { immediate: true },
)

async function save() {
  if (!profile.value) return
  saving.value = true
  notice.value = null
  error.value = null
  try {
    profile.value = await apiRequest('/v1/me', {
      method: 'PATCH',
      body: {
        fullName: form.fullName,
        phone: form.phone.trim() || null,
        birthDate: form.birthDate || null,
        expectedVersion: profile.value.rowVersion,
      },
      schema: MyProfile,
    })
    notice.value = t('profile.saved')
  } catch (cause) {
    error.value = describeError(cause)
  } finally {
    saving.value = false
  }
}

// Avatar: reserve a path, upload straight to Storage with the signed URL, then
// ask the API to check the file and switch to it (techstack §4.5).
async function onFile(event: Event) {
  const file = (event.target as HTMLInputElement).files?.[0]
  if (fileInput.value) fileInput.value.value = ''
  if (!file || !profile.value) return
  avatarNotice.value = null
  avatarError.value = null
  const type = AvatarContentType.safeParse(file.type)
  if (!type.success) return void (avatarError.value = t('profile.avatar.invalidType'))
  if (file.size > AVATAR_MAX_BYTES) return void (avatarError.value = t('profile.avatar.tooLarge'))

  avatarBusy.value = true
  try {
    const upload = await apiRequest('/v1/me/avatar/uploads', {
      method: 'POST',
      body: { contentType: type.data, size: file.size },
      schema: AvatarUploadResponse,
    })
    const put = await fetch(upload.uploadUrl, {
      method: 'PUT',
      headers: { 'Content-Type': type.data },
      body: file,
    })
    // Storage refuses files above the bucket limit or of another declared type.
    if (!put.ok) throw new Error('avatar_invalid')
    profile.value = await apiRequest('/v1/me/avatar', {
      method: 'POST',
      body: { path: upload.path, expectedVersion: profile.value.rowVersion },
      schema: MyProfile,
    })
    avatarNotice.value = t('profile.avatar.updated')
  } catch (cause) {
    avatarError.value = describeError(cause)
  } finally {
    avatarBusy.value = false
  }
}

async function removeAvatar() {
  if (!profile.value) return
  avatarBusy.value = true
  avatarNotice.value = null
  avatarError.value = null
  try {
    profile.value = await apiRequest('/v1/me/avatar', {
      method: 'DELETE',
      body: { expectedVersion: profile.value.rowVersion },
      schema: MyProfile,
    })
    avatarNotice.value = t('profile.avatar.removed')
  } catch (cause) {
    avatarError.value = describeError(cause)
  } finally {
    avatarBusy.value = false
  }
}
</script>

<template>
  <div v-if="profile" class="container-fluid page">
    <h1 class="page-title">{{ t('profile.title') }}</h1>
    <p class="text-body-secondary">{{ t('profile.subtitle') }}</p>

    <div class="row g-4">
      <div class="col-12 col-lg-4">
        <section class="card h-100">
          <div class="card-body text-center">
            <h2 class="h6 text-start">{{ t('profile.avatar.title') }}</h2>
            <MyAvatar :path="profile.avatarPath" :name="profile.fullName" :size="112" />
            <p class="form-text">{{ t('profile.avatar.hint') }}</p>
            <FloatingAlert :message="avatarNotice" />
            <FloatingAlert
              v-if="typeof avatarError === 'string'"
              :message="avatarError"
              variant="danger"
            />
            <ErrorAlert v-else :error="avatarError" />
            <div class="d-flex flex-wrap justify-content-center gap-2">
              <label class="btn btn-outline-primary btn-sm" :class="{ disabled: avatarBusy }">
                <i class="bi bi-upload me-1" aria-hidden="true"></i>
                {{ avatarBusy ? t('profile.avatar.uploading') : t('profile.avatar.choose') }}
                <input
                  ref="fileInput"
                  type="file"
                  class="visually-hidden"
                  accept="image/jpeg,image/png,image/webp"
                  data-testid="avatar-input"
                  :disabled="avatarBusy"
                  @change="onFile"
                />
              </label>
              <button
                v-if="profile.avatarPath"
                type="button"
                class="btn btn-outline-secondary btn-sm"
                :disabled="avatarBusy"
                @click="removeAvatar"
              >
                {{ t('profile.avatar.remove') }}
              </button>
            </div>
          </div>
        </section>
      </div>

      <div class="col-12 col-lg-8">
        <section class="card">
          <div class="card-body">
            <FloatingAlert :message="notice" data-testid="profile-saved" />
            <ErrorAlert :error="error" />
            <form novalidate @submit.prevent="save">
              <div class="row g-3">
                <div class="col-12 col-md-6">
                  <label class="form-label" for="profile-email">{{ t('profile.email') }}</label>
                  <input id="profile-email" class="form-control" :value="profile.email" readonly />
                </div>
                <div class="col-12 col-md-6">
                  <label class="form-label" for="profile-type">{{
                    t('profile.accountType')
                  }}</label>
                  <input
                    id="profile-type"
                    class="form-control"
                    :value="t(`accountType.${profile.accountType}`)"
                    readonly
                  />
                </div>
                <div class="col-12">
                  <label class="form-label" for="profile-name">{{ t('profile.fullName') }}</label>
                  <input
                    id="profile-name"
                    v-model="form.fullName"
                    class="form-control"
                    maxlength="200"
                    autocomplete="name"
                    required
                  />
                </div>
                <div class="col-12 col-md-6">
                  <label class="form-label" for="profile-phone">
                    {{ t('profile.phone') }}
                    <span class="text-body-secondary">({{ t('common.optional') }})</span>
                  </label>
                  <input
                    id="profile-phone"
                    v-model="form.phone"
                    class="form-control"
                    inputmode="tel"
                    autocomplete="tel"
                  />
                </div>
                <div class="col-12 col-md-6">
                  <label class="form-label" for="profile-birth">
                    {{ t('profile.birthDate') }}
                    <span class="text-body-secondary">({{ t('common.optional') }})</span>
                  </label>
                  <input
                    id="profile-birth"
                    v-model="form.birthDate"
                    type="date"
                    class="form-control"
                  />
                </div>
              </div>
              <div class="d-flex flex-wrap gap-2 mt-4">
                <button type="submit" class="btn btn-primary" :disabled="saving">
                  {{ saving ? t('common.saving') : t('common.save') }}
                </button>
                <RouterLink class="btn btn-outline-secondary" :to="{ name: 'change-password' }">
                  <i class="bi bi-key me-1" aria-hidden="true"></i>{{ t('profile.changePassword') }}
                </RouterLink>
              </div>
            </form>
          </div>
        </section>
      </div>
    </div>
  </div>
</template>
