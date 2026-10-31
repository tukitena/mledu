<script setup lang="ts">
import { ClassTest, ClassTestList, hasDetails, type TestSource } from '@mledu/contracts/assessments'
import type { ClassDetail } from '@mledu/contracts/classes'
import { ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { describeError, type DescribedError } from '../../app/errors'
import { apiRequest } from '../../app/session'
import ErrorAlert from '../../components/ErrorAlert.vue'
import FloatingAlert from '../../components/FloatingAlert.vue'
import ModalDialog from '../../components/ModalDialog.vue'
import RowActionMenu, { type RowAction } from '../../components/RowActionMenu.vue'
import { formatIsoDate } from '../../lib/format'
import TestFormDialog from './TestFormDialog.vue'
import TestResultsDialog from './TestResultsDialog.vue'
import CommentsDialog from '../comments/CommentsDialog.vue'
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
const editing = ref<{ mode: 'create' | 'info'; test: ClassTest | null } | null>(null)
const results = ref<ClassTest | null>(null)
const showArchived = ref(false)
const archiving = ref<ClassTest | null>(null)
const restoring = ref<ClassTest | null>(null)
const reason = ref('')
const actionError = ref<DescribedError | null>(null)
const comments = ref<ClassTest | null>(null)
const busy = ref(false)

async function load() {
  loading.value = true
  error.value = null
  try {
    list.value = await apiRequest(
      `/v1/classes/${props.klass.id}/tests?includeArchived=${showArchived.value}`,
      { schema: ClassTestList },
    )
  } catch (cause) {
    error.value = describeError(cause)
  } finally {
    loading.value = false
  }
}
watch([() => props.klass.id, showArchived], load, { immediate: true })

const summary = (test: ClassTest) => configSummary(test.config, t, locale.value)
const sourceLabel = (source: TestSource | null) =>
  source
    ? t('tests.fromTemplate', { name: source.name, revision: source.revision })
    : t('tests.ownConfig')

function actionsFor(test: ClassTest): RowAction[] {
  if (test.deleted)
    return [
      { key: 'results', label: t('tests.actions.viewResults') },
      ...(list.value?.canArchive ? [{ key: 'restore', label: t('tests.actions.restore') }] : []),
    ]
  const items: RowAction[] = [
    {
      key: 'results',
      label: t(list.value?.canEdit ? 'tests.actions.enterResults' : 'tests.actions.viewResults'),
    },
    {
      key: 'comments',
      label: t(list.value?.canEdit ? 'tests.actions.enterComments' : 'tests.actions.viewComments'),
    },
  ]
  if (list.value?.canEdit) items.push({ key: 'info', label: t('tests.actions.info') })
  if (list.value?.canChangeDisplay && hasDetails(test.config))
    items.push({
      key: 'display',
      label: t(test.showComponents ? 'tests.actions.hideDetails' : 'tests.actions.showDetails'),
    })
  if (list.value?.canArchive)
    items.push({ key: 'archive', label: t('tests.actions.archive'), danger: true })
  return items
}

async function onAction(test: ClassTest, key: string) {
  notice.value = null
  error.value = null
  if (key === 'results') results.value = test
  if (key === 'comments') comments.value = test
  if (key === 'info') editing.value = { mode: key, test }
  if (key === 'display') await toggleDisplay(test)
  if (key === 'archive') {
    reason.value = ''
    actionError.value = null
    archiving.value = test
  }
  if (key === 'restore') {
    actionError.value = null
    restoring.value = test
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

async function archiveOrRestore(test: ClassTest, archive: boolean) {
  busy.value = true
  actionError.value = null
  try {
    const saved = await apiRequest(`/v1/tests/${test.id}/${archive ? 'archive' : 'restore'}`, {
      method: 'POST',
      schema: ClassTest,
      body: archive
        ? { reason: reason.value, expectedVersion: test.rowVersion }
        : { expectedVersion: test.rowVersion },
    })
    archiving.value = null
    restoring.value = null
    notice.value = t(archive ? 'tests.archived' : 'tests.restored', { name: saved.name })
    await load()
  } catch (cause) {
    actionError.value = describeError(cause)
  } finally {
    busy.value = false
  }
}

async function onSaved(saved: ClassTest) {
  const mode = editing.value?.mode
  editing.value = null
  notice.value = t(mode === 'create' ? 'tests.created' : 'tests.saved', { name: saved.name })
  await load()
}
</script>

<template>
  <div class="tests-panel">
    <div class="table-controls d-flex align-items-center justify-content-between gap-2">
      <div class="form-check form-switch mb-0">
        <input
          id="tests-show-archived"
          v-model="showArchived"
          class="form-check-input"
          type="checkbox"
          role="switch"
        />
        <label class="form-check-label small" for="tests-show-archived">
          {{ t('tests.showArchived') }}
        </label>
      </div>
      <button
        v-if="list?.canEdit"
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
              <span v-if="test.deleted" class="badge bg-secondary" data-testid="test-archived">
                {{ t('catalogs.archivedBadge') }}
              </span>
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
            </td>
            <td class="small text-nowrap" data-testid="test-result-count">
              {{ t('tests.resultCount', { n: test.resultCount }) }}
              <span
                v-if="test.publishedCount"
                class="d-block text-primary"
                data-testid="test-published-count"
              >
                {{ t('tests.publishedCount', { n: test.publishedCount }) }}
              </span>
              <span
                v-if="test.commentCount"
                class="d-block text-body-secondary"
                data-testid="test-comment-count"
              >
                {{ t('comments.commentCount', { n: test.commentCount }) }}
              </span>
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
      @close="editing = null"
      @saved="onSaved"
    />

    <TestResultsDialog v-if="results" :test="results" @close="results = null" @saved="load" />
    <CommentsDialog
      v-if="comments"
      kind="test"
      :target-id="comments.id"
      :name="comments.name"
      @close="comments = null"
      @saved="load"
    />

    <ModalDialog
      v-if="archiving"
      :title="t('tests.archiveTitle', { name: archiving.name })"
      @close="archiving = null"
    >
      <ErrorAlert :error="actionError" />
      <p data-testid="test-archive-impact">
        {{
          t('tests.archiveHint', {
            results: archiving.resultCount,
            published: archiving.publishedCount,
            comments: archiving.commentCount,
            publishedComments: archiving.publishedCommentCount,
          })
        }}
      </p>
      <label class="form-label" for="test-archive-reason">{{ t('accounts.reason') }}</label>
      <textarea
        id="test-archive-reason"
        v-model="reason"
        class="form-control"
        rows="3"
        maxlength="1000"
        data-testid="test-archive-reason"
      ></textarea>
      <template #footer>
        <button type="button" class="btn btn-outline-secondary" @click="archiving = null">
          {{ t('common.cancel') }}
        </button>
        <button
          type="button"
          class="btn btn-danger"
          :disabled="busy || !reason.trim()"
          data-testid="test-confirm-archive"
          @click="archiveOrRestore(archiving, true)"
        >
          {{ t('tests.actions.archive') }}
        </button>
      </template>
    </ModalDialog>

    <ModalDialog v-if="restoring" :title="t('tests.actions.restore')" @close="restoring = null">
      <ErrorAlert :error="actionError" />
      <p class="mb-0">{{ t('tests.restoreHint', { name: restoring.name }) }}</p>
      <template #footer>
        <button type="button" class="btn btn-outline-secondary" @click="restoring = null">
          {{ t('common.cancel') }}
        </button>
        <button
          type="button"
          class="btn btn-primary"
          :disabled="busy"
          data-testid="test-confirm-restore"
          @click="archiveOrRestore(restoring, false)"
        >
          {{ t('common.confirm') }}
        </button>
      </template>
    </ModalDialog>
  </div>
</template>
