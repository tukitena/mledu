<script setup lang="ts">
import { CommentBatch, CommentBatchList } from '@mledu/contracts/comments'
import type { ClassDetail } from '@mledu/contracts/classes'
import { ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { describeError, type DescribedError } from '../../app/errors'
import { apiRequest } from '../../app/session'
import ErrorAlert from '../../components/ErrorAlert.vue'
import FloatingAlert from '../../components/FloatingAlert.vue'
import ModalDialog from '../../components/ModalDialog.vue'
import RowActionMenu, { type RowAction } from '../../components/RowActionMenu.vue'
import { formatInstant } from '../../lib/format'
import CommentsDialog from './CommentsDialog.vue'

// Comment batches of a class (COMMENT-02/03), as the class page's "Comments"
// tab: same card table + row menu as the Tests tab. Rights come from the API.
const props = defineProps<{ klass: ClassDetail }>()
const { t } = useI18n()

const list = ref<CommentBatchList | null>(null)
const loading = ref(false)
const showArchived = ref(false)
const error = ref<DescribedError | null>(null)
const actionError = ref<DescribedError | null>(null)
const notice = ref<string | null>(null)
const busy = ref(false)
const naming = ref<{ batch: CommentBatch | null; name: string } | null>(null)
const archiving = ref<CommentBatch | null>(null)
const reason = ref('')
const restoring = ref<CommentBatch | null>(null)
const open = ref<CommentBatch | null>(null)

async function load() {
  loading.value = true
  error.value = null
  try {
    list.value = await apiRequest(
      `/v1/classes/${props.klass.id}/comment-batches?includeArchived=${showArchived.value}`,
      { schema: CommentBatchList },
    )
  } catch (cause) {
    error.value = describeError(cause)
  } finally {
    loading.value = false
  }
}
watch([() => props.klass.id, showArchived], load, { immediate: true })

function actionsFor(batch: CommentBatch): RowAction[] {
  if (batch.deleted)
    return list.value?.canManage ? [{ key: 'restore', label: t('comments.actions.restore') }] : []
  const items: RowAction[] = [
    {
      key: 'open',
      label: t(list.value?.canEdit ? 'comments.actions.enter' : 'comments.actions.view'),
    },
  ]
  if (list.value?.canEdit) items.push({ key: 'rename', label: t('comments.actions.rename') })
  if (list.value?.canManage)
    items.push({ key: 'archive', label: t('comments.actions.archive'), danger: true })
  return items
}

function onAction(batch: CommentBatch, key: string) {
  notice.value = null
  actionError.value = null
  if (key === 'open') open.value = batch
  if (key === 'rename') naming.value = { batch, name: batch.name }
  if (key === 'archive') {
    reason.value = ''
    archiving.value = batch
  }
  if (key === 'restore') restoring.value = batch
}

async function run(action: () => Promise<CommentBatch>, message: (saved: CommentBatch) => string) {
  busy.value = true
  actionError.value = null
  try {
    const saved = await action()
    notice.value = message(saved)
    naming.value = null
    archiving.value = null
    restoring.value = null
    await load()
  } catch (cause) {
    actionError.value = describeError(cause)
  } finally {
    busy.value = false
  }
}

const saveName = (state: { batch: CommentBatch | null; name: string }) =>
  run(
    () =>
      state.batch
        ? apiRequest(`/v1/comment-batches/${state.batch.id}`, {
            method: 'PUT',
            schema: CommentBatch,
            body: { name: state.name, expectedVersion: state.batch.rowVersion },
          })
        : apiRequest(`/v1/classes/${props.klass.id}/comment-batches`, {
            method: 'POST',
            schema: CommentBatch,
            body: { name: state.name },
          }),
    (saved) => t(state.batch ? 'comments.renamed' : 'comments.created', { name: saved.name }),
  )

const confirmArchive = (batch: CommentBatch) =>
  run(
    () =>
      apiRequest(`/v1/comment-batches/${batch.id}/archive`, {
        method: 'POST',
        schema: CommentBatch,
        body: { reason: reason.value, expectedVersion: batch.rowVersion },
      }),
    (saved) => t('comments.archived', { name: saved.name }),
  )

const confirmRestore = (batch: CommentBatch) =>
  run(
    () =>
      apiRequest(`/v1/comment-batches/${batch.id}/restore`, {
        method: 'POST',
        schema: CommentBatch,
        body: { expectedVersion: batch.rowVersion },
      }),
    (saved) => t('comments.restored', { name: saved.name }),
  )
</script>

<template>
  <div class="comment-batches-panel">
    <div class="table-controls d-flex align-items-center justify-content-between gap-2">
      <div class="form-check form-switch mb-0">
        <input
          id="cb-show-archived"
          v-model="showArchived"
          class="form-check-input"
          type="checkbox"
          role="switch"
        />
        <label class="form-check-label small" for="cb-show-archived">
          {{ t('comments.showArchived') }}
        </label>
      </div>
      <button
        v-if="list?.canEdit"
        type="button"
        class="btn btn-primary btn-sm"
        data-testid="batch-create"
        @click="
          () => {
            notice = null
            actionError = null
            naming = { batch: null, name: '' }
          }
        "
      >
        <i class="bi bi-plus-lg me-1" aria-hidden="true"></i>{{ t('comments.create') }}
      </button>
    </div>

    <FloatingAlert :message="notice" />
    <ErrorAlert :error="error" />

    <div class="table-responsive">
      <table
        class="table table-hover align-middle mb-0 data-table"
        data-testid="batches-table"
        :aria-busy="loading || busy"
      >
        <thead>
          <tr>
            <th scope="col">{{ t('comments.batchName') }}</th>
            <th scope="col">{{ t('comments.comments') }}</th>
            <th scope="col">{{ t('comments.createdBy') }}</th>
            <th scope="col" class="text-end">{{ t('common.actions') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-if="loading && !list">
            <td colspan="4" class="text-body-secondary">{{ t('common.loading') }}</td>
          </tr>
          <tr v-else-if="list && !list.items.length">
            <td colspan="4" class="text-body-secondary">{{ t('comments.emptyList') }}</td>
          </tr>
          <tr v-for="batch in list?.items ?? []" :key="batch.id" :data-name="batch.name">
            <td>
              <div class="fw-medium text-break">{{ batch.name }}</div>
              <span v-if="batch.deleted" class="badge bg-secondary" data-testid="batch-archived">
                {{ t('catalogs.archivedBadge') }}
              </span>
            </td>
            <td class="small text-nowrap" data-testid="batch-counts">
              {{ t('comments.commentCount', { n: batch.commentCount }) }}
              <span v-if="batch.publishedCount" class="d-block text-primary">
                {{ t('tests.publishedCount', { n: batch.publishedCount }) }}
              </span>
            </td>
            <td class="small">
              {{ batch.createdByName }}
              <span class="d-block text-body-secondary">{{ formatInstant(batch.createdAt) }}</span>
            </td>
            <td class="text-end">
              <RowActionMenu
                v-if="actionsFor(batch).length"
                :id="batch.id"
                :label="`${t('common.actions')}: ${batch.name}`"
                :items="actionsFor(batch)"
                @select="onAction(batch, $event)"
              />
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <div v-if="list" class="table-pagination small text-body-secondary">
      {{ t('comments.total', { n: list.items.length }) }}
    </div>

    <CommentsDialog
      v-if="open"
      kind="batch"
      :target-id="open.id"
      :name="open.name"
      @close="open = null"
      @saved="load"
    />

    <ModalDialog
      v-if="naming"
      :title="naming.batch ? t('comments.renameTitle') : t('comments.create')"
      @close="naming = null"
    >
      <ErrorAlert :error="actionError" />
      <form id="batch-name-form" @submit.prevent="saveName(naming)">
        <label class="form-label" for="batch-name">{{ t('comments.batchName') }}</label>
        <input
          id="batch-name"
          v-model="naming.name"
          class="form-control"
          maxlength="200"
          required
          data-testid="batch-name"
        />
        <div class="form-text">{{ t('comments.nameHint') }}</div>
      </form>
      <template #footer>
        <button type="button" class="btn btn-outline-secondary" @click="naming = null">
          {{ t('common.cancel') }}
        </button>
        <button
          type="submit"
          form="batch-name-form"
          class="btn btn-primary"
          :disabled="busy || !naming.name.trim()"
          data-testid="batch-save"
        >
          {{ t('common.save') }}
        </button>
      </template>
    </ModalDialog>

    <ModalDialog
      v-if="archiving"
      :title="t('comments.archiveTitle', { name: archiving.name })"
      @close="archiving = null"
    >
      <ErrorAlert :error="actionError" />
      <p data-testid="batch-archive-impact">
        {{
          t('comments.archiveHint', {
            n: archiving.commentCount,
            published: archiving.publishedCount,
          })
        }}
      </p>
      <label class="form-label" for="cb-reason">{{ t('accounts.reason') }}</label>
      <textarea
        id="cb-reason"
        v-model="reason"
        class="form-control"
        rows="3"
        maxlength="1000"
        data-testid="batch-reason"
      ></textarea>
      <template #footer>
        <button type="button" class="btn btn-outline-secondary" @click="archiving = null">
          {{ t('common.cancel') }}
        </button>
        <button
          type="button"
          class="btn btn-danger"
          :disabled="busy || !reason.trim()"
          data-testid="batch-confirm-archive"
          @click="confirmArchive(archiving)"
        >
          {{ t('comments.actions.archive') }}
        </button>
      </template>
    </ModalDialog>

    <ModalDialog v-if="restoring" :title="t('comments.actions.restore')" @close="restoring = null">
      <ErrorAlert :error="actionError" />
      <p class="mb-0">{{ t('comments.restoreHint', { name: restoring.name }) }}</p>
      <template #footer>
        <button type="button" class="btn btn-outline-secondary" @click="restoring = null">
          {{ t('common.cancel') }}
        </button>
        <button
          type="button"
          class="btn btn-primary"
          :disabled="busy"
          data-testid="batch-confirm-restore"
          @click="confirmRestore(restoring)"
        >
          {{ t('common.confirm') }}
        </button>
      </template>
    </ModalDialog>
  </div>
</template>
