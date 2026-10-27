<script setup lang="ts">
import { AccountPage } from '@mledu/contracts/accounts'
import { computed, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { describeError, type DescribedError } from '../../app/errors'
import { apiRequest, profile, workspace } from '../../app/session'
import ErrorAlert from '../../components/ErrorAlert.vue'

const { t } = useI18n()
const totals = ref<number[] | null>(null)
const accounts = ref<AccountPage['items']>([])
const loading = ref(false)
const error = ref<DescribedError | null>(null)
const isAdmin = computed(() => workspace.value === 'admin')
const statuses = ['active', 'disabled', 'deleted'] as const
const icons = ['bi-people', 'bi-person-check', 'bi-person-dash', 'bi-archive']
let requestId = 0

async function load() {
  const id = ++requestId
  totals.value = null
  accounts.value = []
  error.value = null
  loading.value = false
  if (!isAdmin.value) return
  loading.value = true
  try {
    const pages = await Promise.all(
      ['', ...statuses].map((status) =>
        apiRequest(`/v1/accounts?page=1&pageSize=5${status ? `&status=${status}` : ''}`, {
          schema: AccountPage,
        }),
      ),
    )
    if (id !== requestId) return
    totals.value = pages.map((page) => page.total)
    accounts.value = pages[0]!.items
  } catch (cause) {
    if (id === requestId) error.value = describeError(cause)
  } finally {
    if (id === requestId) loading.value = false
  }
}
watch(workspace, load, { immediate: true })

const stats = computed(() =>
  isAdmin.value
    ? [t('dashboard.totalAccounts'), ...statuses.map((status) => t(`status.${status}`))].map(
        (label, index) => ({
          label,
          icon: icons[index],
          value: totals.value?.[index]?.toLocaleString() ?? '—',
          hint: t('dashboard.accountUnit'),
        }),
      )
    : [
        {
          label: t('nav.workspace'),
          icon: 'bi-grid',
          value: workspace.value ? t(`workspace.${workspace.value}`) : '—',
          hint: t('dashboard.currentWorkspace'),
        },
        {
          label: t('profile.accountType'),
          icon: 'bi-person-badge',
          value: profile.value ? t(`accountType.${profile.value.accountType}`) : '—',
          hint: t('dashboard.yourAccount'),
        },
        {
          label: t('profile.password'),
          icon: 'bi-shield-check',
          value: t('dashboard.passwordSet'),
          hint: t('dashboard.securityHint'),
        },
        {
          label: t('profile.fullName'),
          icon: 'bi-person-circle',
          value: profile.value?.fullName ?? '—',
          hint: t('nav.profile'),
        },
      ],
)
</script>

<template>
  <div class="container-fluid page dashboard-page">
    <div class="page-header">
      <div>
        <h1 class="page-title">{{ t('dashboard.title') }}</h1>
        <p class="text-body-secondary mb-0" data-testid="welcome">
          {{ t('dashboard.welcome', { name: profile?.fullName }) }}
        </p>
      </div>
      <div class="d-flex gap-2">
        <RouterLink class="btn btn-primary" :to="{ name: isAdmin ? 'accounts' : 'profile' }"
          ><i class="bi me-2" :class="isAdmin ? 'bi-people' : 'bi-person'" aria-hidden="true"></i
          >{{ t(isAdmin ? 'dashboard.manageAccounts' : 'nav.profile') }}</RouterLink
        >
        <button
          v-if="isAdmin"
          type="button"
          class="btn btn-outline-secondary"
          :aria-label="t('dashboard.refresh')"
          :disabled="loading"
          @click="load"
        >
          <i class="bi bi-arrow-clockwise" aria-hidden="true"></i>
        </button>
      </div>
    </div>
    <ErrorAlert :error="error" />
    <div class="dashboard-stats" data-testid="dashboard-stats" :aria-busy="loading">
      <section v-for="stat in stats" :key="stat.label" class="card stat-card">
        <div class="stat-icon"><i class="bi" :class="stat.icon" aria-hidden="true"></i></div>
        <div class="stat-content">
          <h2 class="stat-label">{{ stat.label }}</h2>
          <div class="stat-value" :class="{ 'stat-text-value': !isAdmin }">{{ stat.value }}</div>
          <p class="stat-hint">{{ loading ? t('common.loading') : stat.hint }}</p>
        </div>
      </section>
    </div>
    <div class="dashboard-panels">
      <section class="card overview-panel">
        <div class="panel-heading">
          <h2>{{ t(isAdmin ? 'dashboard.accountOverview' : 'dashboard.learningOverview') }}</h2>
          <span class="panel-caption">{{ t('dashboard.currentData') }}</span>
        </div>
        <div v-if="isAdmin && totals && totals[0]" class="account-distribution">
          <div class="distribution-total">
            <strong>{{ totals[0].toLocaleString() }}</strong
            ><span>{{ t('dashboard.totalAccounts') }}</span>
          </div>
          <div v-for="(status, index) in statuses" :key="status" class="distribution-row">
            <div class="d-flex justify-content-between gap-3">
              <span>{{ t(`status.${status}`) }}</span
              ><strong>{{ totals[index + 1]?.toLocaleString() }}</strong>
            </div>
            <div
              class="distribution-track"
              role="meter"
              :aria-label="t(`status.${status}`)"
              :aria-valuenow="totals[index + 1]"
              :aria-valuemin="0"
              :aria-valuemax="totals[0]"
            >
              <div
                class="distribution-fill"
                :class="`fill-${status}`"
                :style="{ width: `${(totals[index + 1]! / totals[0]) * 100}%` }"
              ></div>
            </div>
          </div>
        </div>
        <div v-else class="dashboard-empty">
          <i class="bi bi-bar-chart-line" aria-hidden="true"></i>
          <h3>
            {{
              loading
                ? t('common.loading')
                : error
                  ? t('dashboard.loadFailed')
                  : t('dashboard.noData')
            }}
          </h3>
          <p>{{ isAdmin ? t('dashboard.accountDataHint') : t('dashboard.upcoming') }}</p>
        </div>
        <div class="panel-footer" data-testid="workspace-note">
          <i class="bi bi-grid me-2" aria-hidden="true"></i
          >{{
            t('dashboard.workspaceNote', {
              workspace: workspace ? t(`workspace.${workspace}`) : '',
            })
          }}
        </div>
      </section>
      <section class="card quick-access-panel">
        <div class="panel-heading">
          <h2>{{ t('dashboard.quickAccess') }}</h2>
        </div>
        <div class="quick-access-list">
          <RouterLink v-if="isAdmin" :to="{ name: 'accounts' }" class="quick-access-item"
            ><span class="activity-icon"><i class="bi bi-people" aria-hidden="true"></i></span
            ><span
              ><strong>{{ t('nav.accounts') }}</strong
              ><small>{{ t('dashboard.manageAccounts') }}</small></span
            ><i class="bi bi-chevron-right ms-auto" aria-hidden="true"></i
          ></RouterLink>
          <RouterLink :to="{ name: 'profile' }" class="quick-access-item"
            ><span class="activity-icon"><i class="bi bi-person" aria-hidden="true"></i></span
            ><span
              ><strong>{{ t('nav.profile') }}</strong
              ><small>{{ t('dashboard.editProfile') }}</small></span
            ><i class="bi bi-chevron-right ms-auto" aria-hidden="true"></i
          ></RouterLink>
          <RouterLink :to="{ name: 'change-password' }" class="quick-access-item"
            ><span class="activity-icon"><i class="bi bi-shield-lock" aria-hidden="true"></i></span
            ><span
              ><strong>{{ t('profile.changePassword') }}</strong
              ><small>{{ t('dashboard.securityHint') }}</small></span
            ><i class="bi bi-chevron-right ms-auto" aria-hidden="true"></i
          ></RouterLink>
        </div>
      </section>
    </div>
    <section v-if="isAdmin && accounts.length" class="card dashboard-accounts">
      <div class="panel-heading">
        <h2>{{ t('nav.accounts') }}</h2>
        <RouterLink :to="{ name: 'accounts' }"
          >{{ t('dashboard.viewAll') }}<i class="bi bi-arrow-right ms-2" aria-hidden="true"></i
        ></RouterLink>
      </div>
      <div v-for="account in accounts" :key="account.id" class="dashboard-account-row">
        <span class="activity-icon"><i class="bi bi-person" aria-hidden="true"></i></span>
        <div>
          <strong>{{ account.fullName }}</strong
          ><small class="d-block text-body-secondary">{{ account.email }}</small>
        </div>
        <span
          class="badge ms-auto"
          :class="account.status === 'active' ? 'bg-success' : 'bg-secondary'"
          >{{ t(`status.${account.status}`) }}</span
        >
      </div>
    </section>
  </div>
</template>
