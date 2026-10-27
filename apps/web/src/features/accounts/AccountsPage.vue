<script setup lang="ts">
import {
  AccountPage,
  AccountSummary,
  IssuedPasswordResponse,
  type AccountStatus,
} from '@mledu/contracts/accounts'
import { computed, onBeforeUnmount, onMounted, reactive, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { describeError, type DescribedError } from '../../app/errors'
import { apiRequest } from '../../app/session'
import ErrorAlert from '../../components/ErrorAlert.vue'
import FloatingAlert from '../../components/FloatingAlert.vue'
import ModalDialog from '../../components/ModalDialog.vue'

// Account administration (AUTH-02–07). The API refuses anything not allowed,
// including every operation on Admin accounts (AUTH-06).
const { t } = useI18n()
const PAGE_SIZE = 20

const search = ref('')
const status = ref<AccountStatus | ''>('')
const page = ref(1)
const result = ref<AccountPage | null>(null)
const loading = ref(false)
const error = ref<DescribedError | null>(null)
const notice = ref<string | null>(null)
const pages = computed(() => Math.max(1, Math.ceil((result.value?.total ?? 0) / PAGE_SIZE)))

async function load() {
  loading.value = true
  error.value = null
  try {
    const query = new URLSearchParams({ page: String(page.value), pageSize: String(PAGE_SIZE) })
    if (search.value.trim()) query.set('search', search.value.trim())
    if (status.value) query.set('status', status.value)
    result.value = await apiRequest(`/v1/accounts?${query}`, { schema: AccountPage })
  } catch (cause) {
    error.value = describeError(cause)
  } finally {
    loading.value = false
  }
}
onMounted(load)
watch(status, () => {
  page.value = 1
  void load()
})

// --- Row actions --------------------------------------------------------------

type Action = 'disable' | 'enable' | 'restore' | 'toReceptionist' | 'toUser' | 'tempPassword'
const pending = ref<{ action: Action; account: AccountSummary } | null>(null)
const deleting = ref<AccountSummary | null>(null)
const deleteReason = ref('')
const issued = ref<{ email: string; password: string } | null>(null)
const copied = ref(false)
const busy = ref(false)
const actionError = ref<DescribedError | null>(null)

function actionsFor(account: AccountSummary): Action[] {
  if (account.accountType === 'admin') return []
  if (account.status === 'deleted') return ['restore']
  return [
    account.status === 'active' ? 'disable' : 'enable',
    account.accountType === 'user' ? 'toReceptionist' : 'toUser',
    'tempPassword',
  ]
}

const replaceRow = (updated: AccountSummary) => {
  if (!result.value) return
  result.value.items = result.value.items.map((item) => (item.id === updated.id ? updated : item))
}

async function run(action: Action, account: AccountSummary) {
  const expectedVersion = account.rowVersion
  const base = `/v1/accounts/${account.id}`
  if (action === 'tempPassword') {
    const response = await apiRequest(`${base}/temporary-password`, {
      method: 'POST',
      body: { expectedVersion },
      schema: IssuedPasswordResponse,
    })
    replaceRow(response.account)
    issued.value = { email: response.account.email, password: response.temporaryPassword }
    return
  }
  const request =
    action === 'toReceptionist' || action === 'toUser'
      ? {
          path: `${base}/type`,
          method: 'PUT' as const,
          body: { accountType: action === 'toUser' ? 'user' : 'receptionist', expectedVersion },
        }
      : { path: `${base}/${action}`, method: 'POST' as const, body: { expectedVersion } }
  replaceRow(
    await apiRequest(request.path, {
      method: request.method,
      body: request.body,
      schema: AccountSummary,
    }),
  )
  notice.value = t('accounts.updated', { name: account.fullName })
}

async function confirmPending() {
  if (!pending.value) return
  busy.value = true
  actionError.value = null
  try {
    await run(pending.value.action, pending.value.account)
    pending.value = null
  } catch (cause) {
    actionError.value = describeError(cause)
  } finally {
    busy.value = false
  }
}

async function confirmDelete() {
  if (!deleting.value) return
  busy.value = true
  actionError.value = null
  try {
    replaceRow(
      await apiRequest(`/v1/accounts/${deleting.value.id}/delete`, {
        method: 'POST',
        body: { reason: deleteReason.value, expectedVersion: deleting.value.rowVersion },
        schema: AccountSummary,
      }),
    )
    notice.value = t('accounts.updated', { name: deleting.value.fullName })
    deleting.value = null
  } catch (cause) {
    actionError.value = describeError(cause)
  } finally {
    busy.value = false
  }
}

function openAction(action: Action, account: AccountSummary) {
  actionError.value = null
  notice.value = null
  pending.value = { action, account }
}

function openDelete(account: AccountSummary) {
  actionError.value = null
  notice.value = null
  deleteReason.value = ''
  deleting.value = account
}

async function copyPassword() {
  if (!issued.value) return
  await navigator.clipboard?.writeText(issued.value.password).catch(() => undefined)
  copied.value = true
}

function closeIssued() {
  issued.value = null
  copied.value = false
}

// --- Create -------------------------------------------------------------------

const creating = ref(false)
const createForm = reactive({ email: '', fullName: '', phone: '', birthDate: '' })

function openCreate() {
  Object.assign(createForm, { email: '', fullName: '', phone: '', birthDate: '' })
  actionError.value = null
  creating.value = true
}

async function submitCreate() {
  busy.value = true
  actionError.value = null
  try {
    const response = await apiRequest('/v1/accounts', {
      method: 'POST',
      body: {
        email: createForm.email,
        fullName: createForm.fullName,
        phone: createForm.phone.trim() || null,
        birthDate: createForm.birthDate || null,
      },
      schema: IssuedPasswordResponse,
    })
    creating.value = false
    issued.value = { email: response.account.email, password: response.temporaryPassword }
    await load()
  } catch (cause) {
    actionError.value = describeError(cause)
  } finally {
    busy.value = false
  }
}

const statusBadge: Record<AccountStatus, string> = {
  active: 'text-bg-success',
  disabled: 'text-bg-warning',
  deleted: 'text-bg-secondary',
}
const roleBadge = {
  admin: 'text-bg-danger',
  receptionist: 'text-bg-warning',
  user: 'text-bg-primary',
}
const menuPosition = ref({ left: '0px', top: '0px' })

function closeRowMenu() {
  document.querySelector<HTMLElement>('.account-action-menu:popover-open')?.hidePopover()
}

function positionRowMenu(event: Event, id: string) {
  const menu = event.currentTarget as HTMLElement
  placeRowMenu(menu, id)
}

function placeRowMenu(menu: HTMLElement, id: string) {
  if (!menu.matches(':popover-open')) return
  const trigger = document.getElementById(`account-action-${id}`)
  if (!trigger) return
  const anchor = trigger.getBoundingClientRect()
  const { width, height } = menu.getBoundingClientRect()
  const gap = 6
  const edge = 8
  const below = anchor.bottom + gap
  const top = below + height <= window.innerHeight - edge ? below : anchor.top - gap - height
  menuPosition.value = {
    left: `${Math.max(edge, Math.min(anchor.right - width, window.innerWidth - width - edge))}px`,
    top: `${Math.max(edge, Math.min(top, window.innerHeight - height - edge))}px`,
  }
}

function onViewportChange(event: Event) {
  // Keep the overlay attached while the page or the responsive table scrolls.
  if (event.target instanceof Element && event.target.closest('.account-action-menu')) return
  const menu = document.querySelector<HTMLElement>('.account-action-menu:popover-open')
  if (menu?.dataset.accountId) placeRowMenu(menu, menu.dataset.accountId)
}

watch([page, status, result], closeRowMenu)
onMounted(() => {
  window.addEventListener('resize', onViewportChange)
  window.addEventListener('scroll', onViewportChange, true)
})
onBeforeUnmount(() => {
  window.removeEventListener('resize', onViewportChange)
  window.removeEventListener('scroll', onViewportChange, true)
})
function initials(name: string) {
  return name
    .trim()
    .split(/\s+/)
    .slice(-2)
    .map((part) => part[0])
    .join('')
    .toUpperCase()
}
</script>

<template>
  <div class="container-fluid page accounts-page">
    <div class="page-header">
      <div>
        <h1 class="page-title">{{ t('accounts.title') }}</h1>
        <p class="text-body-secondary mb-0">{{ t('accounts.subtitle') }}</p>
      </div>
      <button
        type="button"
        class="btn btn-primary"
        data-testid="create-account"
        @click="openCreate"
      >
        <i class="bi bi-person-plus me-1" aria-hidden="true"></i>{{ t('accounts.create') }}
      </button>
    </div>

    <div class="card accounts-card">
      <div class="card-body">
        <form class="row g-3 table-controls" role="search" @submit.prevent="((page = 1), load())">
          <div class="col-12 col-md-6">
            <input
              v-model="search"
              type="search"
              class="form-control"
              :placeholder="t('accounts.searchPlaceholder')"
              :aria-label="t('common.search')"
            />
          </div>
          <div class="col-8 col-md-3">
            <select v-model="status" class="form-select" :aria-label="t('accounts.statusFilter')">
              <option value="">{{ t('common.all') }}</option>
              <option
                v-for="value in ['active', 'disabled', 'deleted'] as const"
                :key="value"
                :value="value"
              >
                {{ t(`status.${value}`) }}
              </option>
            </select>
          </div>
          <div class="col-4 col-md-3 d-grid">
            <button type="submit" class="btn btn-outline-secondary">
              {{ t('common.search') }}
            </button>
          </div>
        </form>

        <FloatingAlert :message="notice" />
        <ErrorAlert :error="error" />

        <div class="table-responsive">
          <table
            class="table table-hover align-middle mb-0 accounts-table"
            data-testid="accounts-table"
            :aria-busy="loading"
          >
            <thead>
              <tr>
                <th scope="col">{{ t('accounts.columns.name') }}</th>
                <th scope="col">{{ t('accounts.columns.email') }}</th>
                <th scope="col">{{ t('accounts.columns.type') }}</th>
                <th scope="col">{{ t('accounts.columns.status') }}</th>
                <th scope="col" class="text-end">{{ t('common.actions') }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-if="loading && !result">
                <td colspan="5" class="text-body-secondary">{{ t('common.loading') }}</td>
              </tr>
              <tr v-else-if="result && result.items.length === 0">
                <td colspan="5" class="text-body-secondary">{{ t('accounts.empty') }}</td>
              </tr>
              <tr
                v-for="account in result?.items ?? []"
                :key="account.id"
                :data-email="account.email"
              >
                <td>
                  <div class="account-identity">
                    <span class="account-avatar" aria-hidden="true">{{
                      initials(account.fullName)
                    }}</span>
                    <div>
                      <div class="fw-semibold">{{ account.fullName }}</div>
                      <span
                        v-if="account.mustChangePassword"
                        class="badge text-bg-light border d-block mt-1"
                        >{{ t('accounts.mustChange') }}</span
                      >
                    </div>
                  </div>
                </td>
                <td class="text-break">{{ account.email }}</td>
                <td>
                  <span class="badge" :class="roleBadge[account.accountType]">{{
                    t(`accountType.${account.accountType}`)
                  }}</span>
                </td>
                <td>
                  <span
                    class="badge"
                    :class="statusBadge[account.status]"
                    data-testid="account-status"
                  >
                    {{ t(`status.${account.status}`) }}
                  </span>
                </td>
                <td class="text-end">
                  <span v-if="account.accountType === 'admin'" class="small text-body-secondary">
                    {{ t('accounts.adminManaged') }}
                  </span>
                  <div v-else class="account-actions">
                    <button
                      :id="`account-action-${account.id}`"
                      type="button"
                      class="btn btn-outline-secondary row-action-toggle"
                      :aria-label="`${t('common.actions')}: ${account.fullName}`"
                      :popovertarget="`account-menu-${account.id}`"
                    >
                      <i class="bi bi-three-dots" aria-hidden="true"></i
                      ><i class="bi bi-caret-down-fill" aria-hidden="true"></i>
                    </button>
                    <div
                      :id="`account-menu-${account.id}`"
                      :data-account-id="account.id"
                      popover="auto"
                      class="account-action-menu"
                      :style="menuPosition"
                      :aria-label="`${t('common.actions')}: ${account.fullName}`"
                      @toggle="positionRowMenu($event, account.id)"
                      @click="closeRowMenu"
                    >
                      <button
                        v-for="action in actionsFor(account)"
                        :key="action"
                        type="button"
                        class="user-menu-item"
                        :data-action="action"
                        @click="openAction(action, account)"
                      >
                        {{ t(`accounts.actions.${action}`) }}
                      </button>
                      <button
                        v-if="account.status !== 'deleted'"
                        type="button"
                        class="user-menu-item text-danger"
                        data-action="delete"
                        @click="openDelete(account)"
                      >
                        {{ t('accounts.actions.delete') }}
                      </button>
                    </div>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div
          v-if="result"
          class="table-pagination d-flex flex-wrap align-items-center justify-content-between gap-2"
        >
          <span class="small text-body-secondary">{{
            t('accounts.total', { n: result.total })
          }}</span>
          <div class="btn-group btn-group-sm">
            <button
              type="button"
              class="btn btn-outline-secondary"
              :disabled="page <= 1"
              @click="(page--, load())"
            >
              {{ t('common.previous') }}
            </button>
            <span class="btn btn-outline-secondary disabled">
              {{ t('common.page', { page, pages }) }}
            </span>
            <button
              type="button"
              class="btn btn-outline-secondary"
              :disabled="page >= pages"
              @click="(page++, load())"
            >
              {{ t('common.next') }}
            </button>
          </div>
        </div>
      </div>
    </div>

    <ModalDialog
      v-if="pending"
      :title="t(`accounts.actions.${pending.action}`)"
      @close="pending = null"
    >
      <ErrorAlert :error="actionError" />
      <p class="mb-0">
        {{ t(`accounts.confirm.${pending.action}`, { name: pending.account.fullName }) }}
      </p>
      <template #footer>
        <button type="button" class="btn btn-outline-secondary" @click="pending = null">
          {{ t('common.cancel') }}
        </button>
        <button
          type="button"
          class="btn btn-primary"
          :disabled="busy"
          data-testid="confirm-action"
          @click="confirmPending"
        >
          {{ t('common.confirm') }}
        </button>
      </template>
    </ModalDialog>

    <ModalDialog v-if="deleting" :title="t('accounts.deleteTitle')" @close="deleting = null">
      <ErrorAlert :error="actionError" />
      <p>{{ t('accounts.deleteHint', { name: deleting.fullName }) }}</p>
      <label class="form-label" for="delete-reason">{{ t('accounts.reason') }}</label>
      <textarea
        id="delete-reason"
        v-model="deleteReason"
        class="form-control"
        rows="3"
        maxlength="1000"
      ></textarea>
      <template #footer>
        <button type="button" class="btn btn-outline-secondary" @click="deleting = null">
          {{ t('common.cancel') }}
        </button>
        <button
          type="button"
          class="btn btn-danger"
          :disabled="busy || !deleteReason.trim()"
          data-testid="confirm-delete"
          @click="confirmDelete"
        >
          {{ t('accounts.actions.delete') }}
        </button>
      </template>
    </ModalDialog>

    <ModalDialog v-if="creating" :title="t('accounts.createTitle')" @close="creating = false">
      <p class="small text-body-secondary">{{ t('accounts.createHint') }}</p>
      <ErrorAlert :error="actionError" />
      <form id="create-account-form" novalidate @submit.prevent="submitCreate">
        <div class="mb-3">
          <label class="form-label" for="create-email">{{ t('profile.email') }}</label>
          <input
            id="create-email"
            v-model="createForm.email"
            type="email"
            class="form-control"
            required
          />
        </div>
        <div class="mb-3">
          <label class="form-label" for="create-name">{{ t('profile.fullName') }}</label>
          <input
            id="create-name"
            v-model="createForm.fullName"
            class="form-control"
            maxlength="200"
            required
          />
        </div>
        <div class="row g-3">
          <div class="col-12 col-sm-6">
            <label class="form-label" for="create-phone">
              {{ t('profile.phone') }}
              <span class="text-body-secondary">({{ t('common.optional') }})</span>
            </label>
            <input
              id="create-phone"
              v-model="createForm.phone"
              class="form-control"
              inputmode="tel"
            />
          </div>
          <div class="col-12 col-sm-6">
            <label class="form-label" for="create-birth">
              {{ t('profile.birthDate') }}
              <span class="text-body-secondary">({{ t('common.optional') }})</span>
            </label>
            <input
              id="create-birth"
              v-model="createForm.birthDate"
              type="date"
              class="form-control"
            />
          </div>
        </div>
      </form>
      <template #footer>
        <button type="button" class="btn btn-outline-secondary" @click="creating = false">
          {{ t('common.cancel') }}
        </button>
        <button
          type="submit"
          form="create-account-form"
          class="btn btn-primary"
          :disabled="busy || !createForm.email || !createForm.fullName.trim()"
          data-testid="submit-create"
        >
          {{ t('accounts.create') }}
        </button>
      </template>
    </ModalDialog>

    <ModalDialog v-if="issued" :title="t('accounts.issuedTitle')" @close="closeIssued">
      <p>{{ t('accounts.issuedHint', { email: issued.email }) }}</p>
      <div class="input-group">
        <input
          class="form-control font-monospace"
          :value="issued.password"
          readonly
          data-testid="temporary-password"
        />
        <button type="button" class="btn btn-outline-secondary" @click="copyPassword">
          {{ copied ? t('common.copied') : t('common.copy') }}
        </button>
      </div>
      <template #footer>
        <button type="button" class="btn btn-primary" @click="closeIssued">
          {{ t('common.close') }}
        </button>
      </template>
    </ModalDialog>
  </div>
</template>
