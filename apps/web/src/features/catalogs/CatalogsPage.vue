<script setup lang="ts">
import {
  CATALOG_PATHS,
  CatalogEntry,
  Room,
  Site,
  type CatalogKind,
} from '@mledu/contracts/catalogs'
import { nameKey } from '@mledu/contracts/normalize'
import { computed, reactive, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute, useRouter } from 'vue-router'
import { z } from 'zod'
import { describeError, type DescribedError } from '../../app/errors'
import { apiRequest, workspace } from '../../app/session'
import ErrorAlert from '../../components/ErrorAlert.vue'
import FloatingAlert from '../../components/FloatingAlert.vue'
import ModalDialog from '../../components/ModalDialog.vue'
import RowActionMenu, { type RowAction } from '../../components/RowActionMenu.vue'

// Shared catalogs (CAT-01, SCHED-02/03/05). Subjects/grades are written in the
// Admin workspace only; sites/rooms by Admin and Receptionist. The API refuses
// anything else, whatever the page shows.
const { t } = useI18n()
const route = useRoute()
const router = useRouter()

const TABS = ['subject', 'grade', 'site', 'room'] as const
type Tab = (typeof TABS)[number]
type Row = CatalogEntry | Site | Room

const tab = computed<Tab>({
  get: () =>
    ((TABS as readonly string[]).find((item) => item === route.query.tab) as Tab) ?? 'subject',
  set: (value) => void router.replace({ query: { ...route.query, tab: value } }),
})
const canEdit = computed(() =>
  tab.value === 'subject' || tab.value === 'grade'
    ? workspace.value === 'admin'
    : workspace.value === 'admin' || workspace.value === 'receptionist',
)

const showArchived = ref(false)
const search = ref('')
const siteFilter = ref('')
const rows = ref<Row[]>([])
const activeSites = ref<Site[]>([])
const loading = ref(false)
const error = ref<DescribedError | null>(null)
const notice = ref<string | null>(null)

const listPath = (current: Tab) =>
  current === 'site'
    ? '/v1/sites'
    : current === 'room'
      ? '/v1/rooms'
      : `/v1/catalogs/${CATALOG_PATHS[current as CatalogKind]}`
const rowSchema = (current: Tab) =>
  current === 'site' ? Site : current === 'room' ? Room : CatalogEntry

async function load() {
  const current = tab.value
  loading.value = true
  error.value = null
  try {
    const query = new URLSearchParams()
    if (showArchived.value && canEdit.value) query.set('includeArchived', 'true')
    const suffix = query.size ? `?${query}` : ''
    const [list, sites] = await Promise.all([
      apiRequest(`${listPath(current)}${suffix}`, { schema: z.array(rowSchema(current)) }),
      current === 'room'
        ? apiRequest('/v1/sites', { schema: z.array(Site) })
        : Promise.resolve(activeSites.value),
    ])
    if (current !== tab.value) return
    rows.value = list
    activeSites.value = sites
  } catch (cause) {
    error.value = describeError(cause)
  } finally {
    loading.value = false
  }
}

watch([tab, showArchived], () => void load(), { immediate: true })
watch(tab, () => {
  rows.value = []
  search.value = ''
  siteFilter.value = ''
  notice.value = null
})

const filtered = computed(() => {
  const key = nameKey(search.value)
  return rows.value.filter((row) => {
    if (siteFilter.value && 'siteId' in row && row.siteId !== siteFilter.value) return false
    if (!key) return true
    const haystack = 'address' in row ? `${row.name} ${row.address}` : row.name
    return nameKey(haystack).includes(key)
  })
})

// --- Create / edit ------------------------------------------------------------

const editing = ref<{ row: Row | null } | null>(null)
const form = reactive({ name: '', address: '', siteId: '' })
const busy = ref(false)
const actionError = ref<DescribedError | null>(null)

function openForm(row: Row | null) {
  actionError.value = null
  notice.value = null
  Object.assign(form, {
    name: row?.name ?? '',
    address: row && 'address' in row ? row.address : '',
    siteId:
      row && 'siteId' in row ? row.siteId : ((siteFilter.value || activeSites.value[0]?.id) ?? ''),
  })
  editing.value = { row }
}

const formValid = computed(
  () =>
    form.name.trim().length > 0 &&
    (tab.value !== 'site' || form.address.trim().length > 0) &&
    (tab.value !== 'room' || form.siteId !== ''),
)

function requestFor(row: Row | null) {
  const base = listPath(tab.value)
  const body =
    tab.value === 'site'
      ? { name: form.name, address: form.address }
      : tab.value === 'room'
        ? { siteId: form.siteId, name: form.name }
        : { name: form.name }
  return row
    ? {
        path: `${base}/${row.id}`,
        method: 'PATCH' as const,
        body: { ...body, expectedVersion: row.rowVersion },
      }
    : { path: base, method: 'POST' as const, body }
}

async function submitForm() {
  if (!editing.value) return
  busy.value = true
  actionError.value = null
  try {
    const request = requestFor(editing.value.row)
    const saved = await apiRequest(request.path, {
      method: request.method,
      body: request.body,
      schema: rowSchema(tab.value),
    })
    notice.value = t('catalogs.saved', { name: saved.name })
    editing.value = null
    await load()
  } catch (cause) {
    actionError.value = describeError(cause)
  } finally {
    busy.value = false
  }
}

// --- Archive / restore --------------------------------------------------------

const archiving = ref<Row | null>(null)
const restoring = ref<Row | null>(null)
const reason = ref('')

function actionsFor(row: Row): RowAction[] {
  if (!canEdit.value) return []
  return row.archived
    ? [{ key: 'restore', label: t('catalogs.actions.restore') }]
    : [
        { key: 'edit', label: t('catalogs.actions.edit') },
        { key: 'archive', label: t('catalogs.actions.archive'), danger: true },
      ]
}

function onAction(row: Row, key: string) {
  actionError.value = null
  notice.value = null
  if (key === 'edit') openForm(row)
  if (key === 'archive') {
    reason.value = ''
    archiving.value = row
  }
  if (key === 'restore') restoring.value = row
}

async function confirmArchive() {
  const row = archiving.value
  if (!row) return
  busy.value = true
  actionError.value = null
  try {
    await apiRequest(`${listPath(tab.value)}/${row.id}/archive`, {
      method: 'POST',
      body: { reason: reason.value, expectedVersion: row.rowVersion },
      schema: rowSchema(tab.value),
    })
    notice.value = t('catalogs.archived', { name: row.name })
    archiving.value = null
    await load()
  } catch (cause) {
    actionError.value = describeError(cause)
  } finally {
    busy.value = false
  }
}

async function confirmRestore() {
  const row = restoring.value
  if (!row) return
  busy.value = true
  actionError.value = null
  try {
    await apiRequest(`${listPath(tab.value)}/${row.id}/restore`, {
      method: 'POST',
      body: { expectedVersion: row.rowVersion },
      schema: rowSchema(tab.value),
    })
    notice.value = t('catalogs.restored', { name: row.name })
    restoring.value = null
    await load()
  } catch (cause) {
    actionError.value = describeError(cause)
  } finally {
    busy.value = false
  }
}

const EXTRA_COLUMNS: Record<Tab, string[]> = {
  subject: [],
  grade: [],
  site: ['address', 'roomCount'],
  room: ['siteOfRoom'],
}
const columns = computed(() =>
  [tab.value, ...EXTRA_COLUMNS[tab.value]].map((key) => t(`catalogs.columns.${key}`)),
)
</script>

<template>
  <div class="container-fluid page catalogs-page">
    <div class="page-header">
      <div>
        <h1 class="page-title">{{ t('catalogs.title') }}</h1>
        <p class="text-body-secondary mb-0">{{ t('catalogs.subtitle') }}</p>
      </div>
      <button
        v-if="canEdit"
        type="button"
        class="btn btn-primary"
        data-testid="catalog-create"
        :disabled="tab === 'room' && !activeSites.length"
        @click="openForm(null)"
      >
        <i class="bi bi-plus-lg me-1" aria-hidden="true"></i>{{ t(`catalogs.create.${tab}`) }}
      </button>
    </div>

    <div class="card data-card">
      <div class="card-header data-card-header">
        <div
          class="btn-group btn-group-sm catalog-tabs"
          role="group"
          :aria-label="t('catalogs.title')"
        >
          <template v-for="item in TABS" :key="item">
            <input
              :id="`catalog-tab-${item}`"
              v-model="tab"
              type="radio"
              class="btn-check"
              name="catalog-tab"
              :value="item"
              autocomplete="off"
            />
            <label
              class="btn btn-outline-secondary"
              :for="`catalog-tab-${item}`"
              :data-testid="`catalog-tab-${item}`"
              >{{ t(`catalogs.tabs.${item}`) }}</label
            >
          </template>
        </div>
        <div v-if="canEdit" class="form-check form-switch mb-0">
          <input
            id="catalog-show-archived"
            v-model="showArchived"
            class="form-check-input"
            type="checkbox"
            role="switch"
          />
          <label class="form-check-label small" for="catalog-show-archived">
            {{ t('catalogs.showArchived') }}
          </label>
        </div>
      </div>
      <div class="card-body">
        <div class="row g-3 table-controls">
          <div class="col-12" :class="tab === 'room' ? 'col-md-7' : 'col-md-6'">
            <input
              v-model="search"
              type="search"
              class="form-control"
              :placeholder="t('catalogs.searchPlaceholder')"
              :aria-label="t('common.search')"
            />
          </div>
          <div v-if="tab === 'room'" class="col-12 col-md-5">
            <select v-model="siteFilter" class="form-select" :aria-label="t('catalogs.siteFilter')">
              <option value="">{{ t('catalogs.allSites') }}</option>
              <option v-for="site in activeSites" :key="site.id" :value="site.id">
                {{ site.name }}
              </option>
            </select>
          </div>
        </div>

        <FloatingAlert :message="notice" />
        <ErrorAlert :error="error" />

        <div class="table-responsive">
          <table
            class="table table-hover align-middle mb-0 data-table"
            data-testid="catalog-table"
            :aria-busy="loading"
          >
            <thead>
              <tr>
                <th v-for="column in columns" :key="column" scope="col">{{ column }}</th>
                <th scope="col">{{ t('catalogs.status') }}</th>
                <th scope="col" class="text-end">{{ t('common.actions') }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-if="loading && !rows.length">
                <td :colspan="columns.length + 2" class="text-body-secondary">
                  {{ t('common.loading') }}
                </td>
              </tr>
              <tr v-else-if="!filtered.length">
                <td :colspan="columns.length + 2" class="text-body-secondary">
                  {{ t('catalogs.empty') }}
                </td>
              </tr>
              <tr v-for="row in filtered" :key="row.id" :data-name="row.name">
                <td class="fw-medium">{{ row.name }}</td>
                <td v-if="'address' in row" class="text-break">{{ row.address }}</td>
                <td v-if="'address' in row">{{ row.activeRoomCount }}</td>
                <td v-if="'siteName' in row">
                  {{ row.siteName }}
                  <span v-if="row.siteArchived" class="badge text-bg-light border ms-1">
                    {{ t('catalogs.archivedBadge') }}
                  </span>
                </td>
                <td>
                  <span
                    class="badge"
                    :class="row.archived ? 'bg-secondary' : 'bg-success'"
                    data-testid="catalog-status"
                    :title="row.deletedReason ?? undefined"
                  >
                    {{ row.archived ? t('catalogs.archivedBadge') : t('catalogs.activeBadge') }}
                  </span>
                </td>
                <td class="text-end">
                  <RowActionMenu
                    v-if="canEdit"
                    :id="row.id"
                    :label="`${t('common.actions')}: ${row.name}`"
                    :items="actionsFor(row)"
                    @select="onAction(row, $event)"
                  />
                  <span v-else class="small text-body-secondary">{{ t('catalogs.readOnly') }}</span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <div class="table-pagination small text-body-secondary">
          {{ t('catalogs.total', { n: filtered.length }) }}
        </div>
      </div>
    </div>

    <ModalDialog
      v-if="editing"
      :title="t(editing.row ? `catalogs.edit.${tab}` : `catalogs.create.${tab}`)"
      @close="editing = null"
    >
      <ErrorAlert :error="actionError" />
      <p v-if="actionError?.code === 'archived_duplicate'" class="small text-body-secondary">
        {{ t('catalogs.archivedDuplicateHint') }}
      </p>
      <form id="catalog-form" novalidate @submit.prevent="submitForm">
        <div v-if="tab === 'room'" class="mb-3">
          <label class="form-label" for="catalog-site">{{ t('catalogs.site') }}</label>
          <select id="catalog-site" v-model="form.siteId" class="form-select" required>
            <option v-for="site in activeSites" :key="site.id" :value="site.id">
              {{ site.name }}
            </option>
          </select>
        </div>
        <div class="mb-3">
          <label class="form-label" for="catalog-name">{{ t('catalogs.name') }}</label>
          <input
            id="catalog-name"
            v-model="form.name"
            class="form-control"
            :maxlength="tab === 'subject' || tab === 'grade' ? 100 : 200"
            required
          />
        </div>
        <div v-if="tab === 'site'" class="mb-0">
          <label class="form-label" for="catalog-address">{{ t('catalogs.address') }}</label>
          <textarea
            id="catalog-address"
            v-model="form.address"
            class="form-control"
            rows="2"
            maxlength="500"
            required
          ></textarea>
        </div>
      </form>
      <template #footer>
        <button type="button" class="btn btn-outline-secondary" @click="editing = null">
          {{ t('common.cancel') }}
        </button>
        <button
          type="submit"
          form="catalog-form"
          class="btn btn-primary"
          :disabled="busy || !formValid"
          data-testid="catalog-submit"
        >
          {{ t('common.save') }}
        </button>
      </template>
    </ModalDialog>

    <ModalDialog
      v-if="archiving"
      :title="t('catalogs.archiveTitle', { name: archiving.name })"
      @close="archiving = null"
    >
      <ErrorAlert :error="actionError" />
      <p>{{ t(`catalogs.archiveHint.${tab}`) }}</p>
      <label class="form-label" for="catalog-reason">{{ t('accounts.reason') }}</label>
      <textarea
        id="catalog-reason"
        v-model="reason"
        class="form-control"
        rows="3"
        maxlength="1000"
      ></textarea>
      <template #footer>
        <button type="button" class="btn btn-outline-secondary" @click="archiving = null">
          {{ t('common.cancel') }}
        </button>
        <button
          type="button"
          class="btn btn-danger"
          :disabled="busy || !reason.trim()"
          data-testid="catalog-confirm-archive"
          @click="confirmArchive"
        >
          {{ t('catalogs.actions.archive') }}
        </button>
      </template>
    </ModalDialog>

    <ModalDialog v-if="restoring" :title="t('catalogs.actions.restore')" @close="restoring = null">
      <ErrorAlert :error="actionError" />
      <p class="mb-0">{{ t(`catalogs.restoreHint.${tab}`, { name: restoring.name }) }}</p>
      <template #footer>
        <button type="button" class="btn btn-outline-secondary" @click="restoring = null">
          {{ t('common.cancel') }}
        </button>
        <button
          type="button"
          class="btn btn-primary"
          :disabled="busy"
          data-testid="catalog-confirm-restore"
          @click="confirmRestore"
        >
          {{ t('common.confirm') }}
        </button>
      </template>
    </ModalDialog>
  </div>
</template>
