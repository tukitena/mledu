<script setup lang="ts">
import { TestTemplate, TestTemplateVersion, type ScaleKind } from '@mledu/contracts/assessments'
import { nameKey } from '@mledu/contracts/normalize'
import { computed, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { z } from 'zod'
import { describeError, type DescribedError } from '../../app/errors'
import { apiRequest } from '../../app/session'
import ErrorAlert from '../../components/ErrorAlert.vue'
import FloatingAlert from '../../components/FloatingAlert.vue'
import ModalDialog from '../../components/ModalDialog.vue'
import RowActionMenu, { type RowAction } from '../../components/RowActionMenu.vue'
import { formatInstant } from '../../lib/format'
import TestTemplateFormDialog from './TestTemplateFormDialog.vue'
import { configSummary } from './labels'

// Shared test template library (TEST-02), Admin workspace only. Layout follows
// the catalog pages (Metis "Product Catalog" card + table + row menu). The API
// refuses every other account whatever the page shows.
const { t, locale } = useI18n()

const SCALES: ScaleKind[] = ['numeric', 'fraction', 'letter', 'ielts']
const rows = ref<TestTemplate[]>([])
const loading = ref(false)
const error = ref<DescribedError | null>(null)
const notice = ref<string | null>(null)
const showArchived = ref(false)
const search = ref('')
const scaleFilter = ref<ScaleKind | ''>('')

async function load() {
  loading.value = true
  error.value = null
  try {
    rows.value = await apiRequest(
      `/v1/test-templates${showArchived.value ? '?includeArchived=true' : ''}`,
      { schema: z.array(TestTemplate) },
    )
  } catch (cause) {
    error.value = describeError(cause)
  } finally {
    loading.value = false
  }
}
watch(showArchived, () => void load(), { immediate: true })

const filtered = computed(() => {
  const key = nameKey(search.value)
  return rows.value.filter(
    (row) =>
      (!scaleFilter.value || row.config.scaleKind === scaleFilter.value) &&
      (!key || nameKey(`${row.name} ${row.description ?? ''}`).includes(key)),
  )
})

const summary = (row: { config: TestTemplate['config'] }) =>
  configSummary(row.config, t, locale.value)

// --- Create / edit / history ---------------------------------------------------

const editing = ref<{ template: TestTemplate | null } | null>(null)
const history = ref<{ template: TestTemplate; versions: TestTemplateVersion[] | null } | null>(null)
const archiving = ref<TestTemplate | null>(null)
const restoring = ref<TestTemplate | null>(null)
const reason = ref('')
const busy = ref(false)
const actionError = ref<DescribedError | null>(null)

function actionsFor(row: TestTemplate): RowAction[] {
  const items: RowAction[] = row.archived
    ? [{ key: 'restore', label: t('testTemplates.actions.restore') }]
    : [{ key: 'edit', label: t('testTemplates.actions.edit') }]
  items.push({ key: 'history', label: t('testTemplates.actions.history') })
  if (!row.archived)
    items.push({ key: 'archive', label: t('testTemplates.actions.archive'), danger: true })
  return items
}

async function onAction(row: TestTemplate, key: string) {
  actionError.value = null
  notice.value = null
  if (key === 'edit') editing.value = { template: row }
  if (key === 'archive') {
    reason.value = ''
    archiving.value = row
  }
  if (key === 'restore') restoring.value = row
  if (key === 'history') {
    history.value = { template: row, versions: null }
    try {
      const versions = await apiRequest(`/v1/test-templates/${row.id}/versions`, {
        schema: z.array(TestTemplateVersion),
      })
      if (history.value?.template.id === row.id) history.value.versions = versions
    } catch (cause) {
      actionError.value = describeError(cause)
    }
  }
}

async function onSaved(saved: TestTemplate) {
  const created = !editing.value?.template
  editing.value = null
  notice.value = t(created ? 'testTemplates.created' : 'testTemplates.saved', {
    name: saved.name,
    revision: saved.revision,
  })
  await load()
}

async function command(path: string, body: unknown, message: string) {
  busy.value = true
  actionError.value = null
  try {
    await apiRequest(path, { method: 'POST', body, schema: TestTemplate })
    notice.value = message
    archiving.value = null
    restoring.value = null
    await load()
  } catch (cause) {
    actionError.value = describeError(cause)
  } finally {
    busy.value = false
  }
}

const confirmArchive = (row: TestTemplate) =>
  command(
    `/v1/test-templates/${row.id}/archive`,
    { reason: reason.value, expectedVersion: row.rowVersion },
    t('testTemplates.archived', { name: row.name }),
  )
const confirmRestore = (row: TestTemplate) =>
  command(
    `/v1/test-templates/${row.id}/restore`,
    { expectedVersion: row.rowVersion },
    t('testTemplates.restored', { name: row.name }),
  )
</script>

<template>
  <div class="container-fluid page test-templates-page">
    <div class="page-header">
      <div>
        <h1 class="page-title">{{ t('testTemplates.title') }}</h1>
        <p class="text-body-secondary mb-0">{{ t('testTemplates.subtitle') }}</p>
      </div>
      <button
        type="button"
        class="btn btn-primary"
        data-testid="tt-create"
        @click="
          () => {
            notice = null
            editing = { template: null }
          }
        "
      >
        <i class="bi bi-plus-lg me-1" aria-hidden="true"></i>{{ t('testTemplates.create') }}
      </button>
    </div>

    <div class="card data-card">
      <div class="card-header data-card-header">
        <h2 class="h5 card-title mb-0">{{ t('testTemplates.library') }}</h2>
        <div class="form-check form-switch mb-0">
          <input
            id="tt-show-archived"
            v-model="showArchived"
            class="form-check-input"
            type="checkbox"
            role="switch"
          />
          <label class="form-check-label small" for="tt-show-archived">
            {{ t('testTemplates.showArchived') }}
          </label>
        </div>
      </div>
      <div class="card-body">
        <div class="row g-3 table-controls">
          <div class="col-12 col-md-7">
            <input
              v-model="search"
              type="search"
              class="form-control"
              :placeholder="t('testTemplates.searchPlaceholder')"
              :aria-label="t('common.search')"
            />
          </div>
          <div class="col-12 col-md-5">
            <select
              v-model="scaleFilter"
              class="form-select"
              :aria-label="t('testTemplates.scaleFilter')"
            >
              <option value="">{{ t('testTemplates.allScales') }}</option>
              <option v-for="scale in SCALES" :key="scale" :value="scale">
                {{ t(`testTemplates.scale.${scale}`) }}
              </option>
            </select>
          </div>
        </div>

        <FloatingAlert :message="notice" />
        <ErrorAlert :error="error" />

        <div class="table-responsive">
          <table
            class="table table-hover align-middle mb-0 data-table"
            data-testid="tt-table"
            :aria-busy="loading"
          >
            <thead>
              <tr>
                <th scope="col">{{ t('testTemplates.name') }}</th>
                <th scope="col">{{ t('testTemplates.scaleKind') }}</th>
                <th scope="col">{{ t('testTemplates.configuration') }}</th>
                <th scope="col">{{ t('testTemplates.version') }}</th>
                <th scope="col">{{ t('catalogs.status') }}</th>
                <th scope="col" class="text-end">{{ t('common.actions') }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-if="loading && !rows.length">
                <td colspan="6" class="text-body-secondary">{{ t('common.loading') }}</td>
              </tr>
              <tr v-else-if="!filtered.length">
                <td colspan="6" class="text-body-secondary">{{ t('testTemplates.empty') }}</td>
              </tr>
              <tr v-for="row in filtered" :key="row.id" :data-name="row.name">
                <td>
                  <div class="fw-medium text-break">{{ row.name }}</div>
                  <small v-if="row.description" class="text-body-secondary d-block text-break">
                    {{ row.description }}
                  </small>
                </td>
                <td>
                  <span class="badge bg-light text-dark border">
                    {{ t(`testTemplates.scale.${row.config.scaleKind}`) }}
                  </span>
                </td>
                <td class="small text-break" data-testid="tt-summary">{{ summary(row) }}</td>
                <td class="text-nowrap">
                  v{{ row.revision }}
                  <small class="d-block text-body-secondary">{{
                    formatInstant(row.updatedAt)
                  }}</small>
                </td>
                <td>
                  <span
                    class="badge"
                    :class="row.archived ? 'bg-secondary' : 'bg-success'"
                    data-testid="tt-status"
                    :title="row.deletedReason ?? undefined"
                  >
                    {{ row.archived ? t('catalogs.archivedBadge') : t('catalogs.activeBadge') }}
                  </span>
                </td>
                <td class="text-end">
                  <RowActionMenu
                    :id="row.id"
                    :label="`${t('common.actions')}: ${row.name}`"
                    :items="actionsFor(row)"
                    @select="onAction(row, $event)"
                  />
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <div class="table-pagination small text-body-secondary">
          {{ t('testTemplates.total', { n: filtered.length }) }}
        </div>
      </div>
    </div>

    <TestTemplateFormDialog
      v-if="editing"
      :template="editing.template"
      @close="editing = null"
      @saved="onSaved"
    />

    <ModalDialog
      v-if="history"
      wide
      :title="t('testTemplates.historyTitle', { name: history.template.name })"
      @close="history = null"
    >
      <ErrorAlert :error="actionError" />
      <p class="small text-body-secondary">{{ t('testTemplates.historyHint') }}</p>
      <p v-if="!history.versions && !actionError" class="text-body-secondary">
        {{ t('common.loading') }}
      </p>
      <div v-else-if="history.versions" class="table-responsive">
        <table class="table align-middle mb-0" data-testid="tt-history">
          <thead>
            <tr>
              <th scope="col">{{ t('testTemplates.version') }}</th>
              <th scope="col">{{ t('testTemplates.name') }}</th>
              <th scope="col">{{ t('testTemplates.configuration') }}</th>
              <th scope="col">{{ t('testTemplates.savedBy') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="version in history.versions" :key="version.id">
              <td class="text-nowrap">
                v{{ version.revision }}
                <span
                  v-if="version.id === history.template.currentVersionId"
                  class="badge bg-primary ms-1"
                >
                  {{ t('testTemplates.current') }}
                </span>
              </td>
              <td class="text-break">{{ version.name }}</td>
              <td class="small text-break">
                <span class="badge bg-light text-dark border me-1">
                  {{ t(`testTemplates.scale.${version.config.scaleKind}`) }}
                </span>
                {{ summary(version) }}
              </td>
              <td class="small">
                {{ version.createdByName }}
                <span class="d-block text-body-secondary">{{
                  formatInstant(version.createdAt)
                }}</span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <template #footer>
        <button type="button" class="btn btn-outline-secondary" @click="history = null">
          {{ t('common.close') }}
        </button>
      </template>
    </ModalDialog>

    <ModalDialog
      v-if="archiving"
      :title="t('testTemplates.archiveTitle', { name: archiving.name })"
      @close="archiving = null"
    >
      <ErrorAlert :error="actionError" />
      <p>{{ t('testTemplates.archiveHint') }}</p>
      <label class="form-label" for="tt-reason">{{ t('accounts.reason') }}</label>
      <textarea
        id="tt-reason"
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
          data-testid="tt-confirm-archive"
          @click="confirmArchive(archiving)"
        >
          {{ t('testTemplates.actions.archive') }}
        </button>
      </template>
    </ModalDialog>

    <ModalDialog
      v-if="restoring"
      :title="t('testTemplates.actions.restore')"
      @close="restoring = null"
    >
      <ErrorAlert :error="actionError" />
      <p class="mb-0">{{ t('testTemplates.restoreHint', { name: restoring.name }) }}</p>
      <template #footer>
        <button type="button" class="btn btn-outline-secondary" @click="restoring = null">
          {{ t('common.cancel') }}
        </button>
        <button
          type="button"
          class="btn btn-primary"
          :disabled="busy"
          data-testid="tt-confirm-restore"
          @click="confirmRestore(restoring)"
        >
          {{ t('common.confirm') }}
        </button>
      </template>
    </ModalDialog>
  </div>
</template>
