<script setup lang="ts">
import {
  ClassTest,
  ClassTestDetail,
  ClassTestList,
  hasDetails,
  type TestSource,
} from '@mledu/contracts/assessments'
import type { ClassDetail } from '@mledu/contracts/classes'
import { ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { describeError, type DescribedError } from '../../app/errors'
import { apiRequest } from '../../app/session'
import ErrorAlert from '../../components/ErrorAlert.vue'
import FloatingAlert from '../../components/FloatingAlert.vue'
import ModalDialog from '../../components/ModalDialog.vue'
import RowActionMenu, { type RowAction } from '../../components/RowActionMenu.vue'
import { formatInstant, formatIsoDate } from '../../lib/format'
import TestFormDialog from './TestFormDialog.vue'
import TestResultsDialog from './TestResultsDialog.vue'
import { configSummary } from './labels'

// Tests of a class (TEST-05), as the class page's "Tests" tab. Table + row menu
// as in the Metis "Product Catalog" card. What the caller may do comes from the
// API (current assignment); the API checks again on every write.
const props = defineProps<{ klass: ClassDetail }>()
const { t, locale } = useI18n()

const list = ref<ClassTestList | null>(null)
const loading = ref(false)
const error = ref<DescribedError | null>(null)
const notice = ref<string | null>(null)
const editing = ref<{ mode: 'create' | 'info' | 'config'; test: ClassTest | null } | null>(null)
const history = ref<{ test: ClassTest; detail: ClassTestDetail | null } | null>(null)
const results = ref<ClassTest | null>(null)
const busy = ref(false)

async function load() {
  loading.value = true
  error.value = null
  try {
    list.value = await apiRequest(`/v1/classes/${props.klass.id}/tests`, {
      schema: ClassTestList,
    })
  } catch (cause) {
    error.value = describeError(cause)
  } finally {
    loading.value = false
  }
}
watch(() => props.klass.id, load, { immediate: true })

const summary = (test: ClassTest) => configSummary(test.config, t, locale.value)
const sourceLabel = (source: TestSource | null) =>
  source
    ? t('tests.fromTemplate', { name: source.name, revision: source.revision })
    : t('tests.ownConfig')

function actionsFor(test: ClassTest): RowAction[] {
  const items: RowAction[] = [
    {
      key: 'results',
      label: t(list.value?.canEdit ? 'tests.actions.enterResults' : 'tests.actions.viewResults'),
    },
  ]
  if (list.value?.canEdit) {
    items.push({ key: 'info', label: t('tests.actions.info') })
    items.push({ key: 'config', label: t('tests.actions.config') })
  }
  if (list.value?.canChangeDisplay && hasDetails(test.config))
    items.push({
      key: 'display',
      label: t(test.showComponents ? 'tests.actions.hideDetails' : 'tests.actions.showDetails'),
    })
  items.push({ key: 'history', label: t('tests.actions.history') })
  return items
}

async function onAction(test: ClassTest, key: string) {
  notice.value = null
  error.value = null
  if (key === 'results') results.value = test
  if (key === 'info' || key === 'config') editing.value = { mode: key, test }
  if (key === 'display') await toggleDisplay(test)
  if (key === 'history') {
    history.value = { test, detail: null }
    try {
      const detail = await apiRequest(`/v1/tests/${test.id}`, { schema: ClassTestDetail })
      if (history.value?.test.id === test.id) history.value.detail = detail
    } catch (cause) {
      history.value = null
      error.value = describeError(cause)
    }
  }
}

async function toggleDisplay(test: ClassTest) {
  busy.value = true
  try {
    const saved = await apiRequest(`/v1/tests/${test.id}/show-components`, {
      method: 'PUT',
      body: { showComponents: !test.showComponents, expectedVersion: test.rowVersion },
      schema: ClassTest,
    })
    notice.value = t(saved.showComponents ? 'tests.detailsShown' : 'tests.detailsHidden', {
      name: saved.name,
    })
    await load()
  } catch (cause) {
    error.value = describeError(cause)
  } finally {
    busy.value = false
  }
}

async function onSaved(saved: ClassTest) {
  const mode = editing.value?.mode
  editing.value = null
  notice.value = t(
    mode === 'create' ? 'tests.created' : mode === 'config' ? 'tests.configSaved' : 'tests.saved',
    { name: saved.name, revision: saved.configRevision },
  )
  await load()
}
</script>

<template>
  <div class="tests-panel">
    <div v-if="list?.canEdit" class="table-controls d-flex justify-content-end">
      <button
        type="button"
        class="btn btn-primary btn-sm"
        data-testid="test-create"
        @click="
          () => {
            notice = null
            editing = { mode: 'create', test: null }
          }
        "
      >
        <i class="bi bi-plus-lg me-1" aria-hidden="true"></i>{{ t('tests.create') }}
      </button>
    </div>

    <FloatingAlert :message="notice" />
    <ErrorAlert :error="error" />

    <div class="table-responsive">
      <table
        class="table table-hover align-middle mb-0 data-table"
        data-testid="tests-table"
        :aria-busy="loading || busy"
      >
        <thead>
          <tr>
            <th scope="col">{{ t('tests.name') }}</th>
            <th scope="col">{{ t('tests.testOn') }}</th>
            <th scope="col">{{ t('testTemplates.scaleKind') }}</th>
            <th scope="col">{{ t('testTemplates.configuration') }}</th>
            <th scope="col">{{ t('tests.source') }}</th>
            <th scope="col">{{ t('tests.results') }}</th>
            <th scope="col" class="text-end">{{ t('common.actions') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-if="loading && !list">
            <td colspan="7" class="text-body-secondary">{{ t('common.loading') }}</td>
          </tr>
          <tr v-else-if="list && !list.items.length">
            <td colspan="7" class="text-body-secondary">{{ t('tests.empty') }}</td>
          </tr>
          <tr v-for="test in list?.items ?? []" :key="test.id" :data-name="test.name">
            <td>
              <div class="fw-medium text-break">{{ test.name }}</div>
              <small v-if="test.description" class="text-body-secondary d-block text-break">
                {{ test.description }}
              </small>
            </td>
            <td class="text-nowrap">{{ formatIsoDate(test.testOn) }}</td>
            <td>
              <span class="badge bg-light text-dark border">
                {{ t(`testTemplates.scale.${test.config.scaleKind}`) }}
              </span>
            </td>
            <td class="small text-break" data-testid="test-summary">
              {{ summary(test) }}
              <span
                v-if="hasDetails(test.config)"
                class="badge ms-1"
                :class="test.showComponents ? 'bg-info-subtle text-info-emphasis' : 'bg-secondary'"
                data-testid="test-display"
              >
                {{ t(test.showComponents ? 'tests.detailsVisible' : 'tests.detailsHiddenBadge') }}
              </span>
            </td>
            <td class="small">
              <span class="text-break" data-testid="test-source">{{
                sourceLabel(test.source)
              }}</span>
              <span class="d-block text-body-secondary">
                {{ t('tests.configRevision', { n: test.configRevision }) }}
              </span>
            </td>
            <td class="small text-nowrap" data-testid="test-result-count">
              {{ t('tests.resultCount', { n: test.resultCount }) }}
            </td>
            <td class="text-end">
              <RowActionMenu
                :id="test.id"
                :label="`${t('common.actions')}: ${test.name}`"
                :items="actionsFor(test)"
                @select="onAction(test, $event)"
              />
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <div v-if="list" class="table-pagination small text-body-secondary">
      {{ t('tests.total', { n: list.items.length }) }}
    </div>

    <TestFormDialog
      v-if="editing"
      :klass="klass"
      :mode="editing.mode"
      :test="editing.test"
      :can-change-display="list?.canChangeDisplay ?? false"
      @close="editing = null"
      @saved="onSaved"
    />

    <TestResultsDialog v-if="results" :test="results" @close="results = null" @saved="load" />

    <ModalDialog
      v-if="history"
      wide
      :title="t('tests.historyTitle', { name: history.test.name })"
      @close="history = null"
    >
      <p class="small text-body-secondary">{{ t('tests.historyHint') }}</p>
      <p v-if="!history.detail" class="text-body-secondary">{{ t('common.loading') }}</p>
      <div v-else class="table-responsive">
        <table class="table align-middle mb-0" data-testid="test-history">
          <thead>
            <tr>
              <th scope="col">{{ t('testTemplates.version') }}</th>
              <th scope="col">{{ t('testTemplates.scaleKind') }}</th>
              <th scope="col">{{ t('tests.source') }}</th>
              <th scope="col">{{ t('testTemplates.savedBy') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="version in history.detail.configVersions" :key="version.id">
              <td class="text-nowrap">
                {{ t('tests.configRevision', { n: version.revision }) }}
                <span v-if="version.id === history.detail.configId" class="badge bg-primary ms-1">
                  {{ t('testTemplates.current') }}
                </span>
              </td>
              <td>
                <span class="badge bg-light text-dark border">
                  {{ t(`testTemplates.scale.${version.scaleKind}`) }}
                </span>
              </td>
              <td class="small text-break">{{ sourceLabel(version.source) }}</td>
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
  </div>
</template>
