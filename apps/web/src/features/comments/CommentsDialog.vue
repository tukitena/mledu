<script setup lang="ts">
import {
  COMMENT_MAX,
  commentLength,
  Comments,
  PublishCommentsResponse,
  type CommentRow,
  type CommentTargetKind,
} from '@mledu/contracts/comments'
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { describeError, type DescribedError } from '../../app/errors'
import { apiRequest } from '../../app/session'
import ErrorAlert from '../../components/ErrorAlert.vue'
import ModalDialog from '../../components/ModalDialog.vue'
import { formatInstant, formatIsoDate } from '../../lib/format'

// Comments of one test or batch (COMMENT-01), in the same wide-dialog grid as
// results. Plain text rendered as text; only changed rows are sent. Publication
// (ACAD-01) is per student or the whole target, apart from scores.
const props = defineProps<{ kind: CommentTargetKind; targetId: string; name: string }>()
const emit = defineEmits<{ close: []; saved: [] }>()
const { t } = useI18n()

interface Row {
  student: CommentRow
  body: string
}

const data = ref<Comments | null>(null)
const rows = ref<Row[]>([])
const error = ref<DescribedError | null>(null)
const notice = ref<string | null>(null)
const busy = ref(false)
const path = computed(() => `/v1/comments/${props.kind}/${props.targetId}`)

function update(value: Comments) {
  data.value = value
  rows.value = value.students.map((student) => ({ student, body: student.comment?.body ?? '' }))
}

onMounted(async () => {
  try {
    update(await apiRequest(path.value, { schema: Comments }))
  } catch (cause) {
    error.value = describeError(cause)
  }
})

const editable = computed(() => !!data.value?.canEdit)
const canPublish = computed(() => !!data.value?.canPublish)
const saved = (row: Row) => row.student.comment?.body ?? ''
const changed = (row: Row) => row.body.trim() !== saved(row)
const tooLong = (row: Row) => commentLength(row.body.trim()) > COMMENT_MAX
const dirtyCount = computed(() => rows.value.filter(changed).length)
const anyPublished = computed(() => rows.value.some((row) => row.student.comment?.published))
const locked = (row: Row) => !editable.value || busy.value || !!row.student.comment?.published

type Status = 'published' | 'unsaved' | 'written' | 'empty'
function status(row: Row): Status {
  if (row.student.comment?.published) return 'published'
  if (changed(row)) return 'unsaved'
  return row.student.comment ? 'written' : 'empty'
}
const statusClass: Record<Status, string> = {
  published: 'bg-primary',
  unsaved: 'bg-warning-subtle text-warning-emphasis',
  written: 'bg-success-subtle text-success-emphasis',
  empty: 'text-bg-light border',
}

async function save() {
  error.value = null
  notice.value = null
  if (rows.value.some((row) => changed(row) && tooLong(row))) return
  const items = rows.value.filter(changed).map((row) => ({
    studentId: row.student.studentId,
    expectedVersion: row.student.comment?.rowVersion ?? null,
    body: row.body.trim() || null,
  }))
  if (!items.length) return
  busy.value = true
  try {
    update(await apiRequest(path.value, { method: 'PUT', schema: Comments, body: { items } }))
    emit('saved')
  } catch (cause) {
    error.value = describeError(cause)
  } finally {
    busy.value = false
  }
}

async function publish(studentId: string | null, value: boolean) {
  error.value = null
  notice.value = null
  if (dirtyCount.value) {
    notice.value = t('comments.saveFirst')
    return
  }
  busy.value = true
  try {
    const outcome = await apiRequest(`${path.value}/publication`, {
      method: 'POST',
      schema: PublishCommentsResponse,
      body: { studentId, publish: value },
    })
    update(outcome)
    const parts = [
      t(value ? 'comments.publishedSummary' : 'comments.unpublishedSummary', {
        n: outcome.changed,
      }),
    ]
    if (outcome.missing.length)
      parts.push(
        t('comments.missingList', {
          names: outcome.missing.map((student) => student.fullName).join(', '),
        }),
      )
    notice.value = parts.join(' ')
    emit('saved')
  } catch (cause) {
    error.value = describeError(cause)
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <ModalDialog :title="t('comments.title', { name })" wide @close="emit('close')">
    <ErrorAlert :error="error" />
    <div
      v-if="notice"
      class="alert alert-info small py-2"
      role="status"
      data-testid="comments-notice"
    >
      {{ notice }}
    </div>
    <p class="small text-body-secondary mb-1">
      <span v-if="data?.target.testOn">{{ formatIsoDate(data.target.testOn) }} · </span>
      {{ t(kind === 'test' ? 'comments.testHint' : 'comments.batchHint') }}
    </p>
    <p v-if="canPublish" class="small text-body-secondary">{{ t('comments.publishHint') }}</p>

    <p v-if="!data && !error" class="text-body-secondary">{{ t('common.loading') }}</p>
    <div v-else-if="data" class="table-responsive results-table-wrap">
      <table class="table align-middle mb-0 results-table" data-testid="comments-table">
        <thead>
          <tr>
            <th scope="col">{{ t('results.student') }}</th>
            <th scope="col">{{ t('comments.comment') }}</th>
            <th scope="col">{{ t('results.status') }}</th>
            <th v-if="canPublish" scope="col" class="text-end">{{ t('results.publication') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-if="!rows.length">
            <td :colspan="canPublish ? 4 : 3" class="text-body-secondary">
              {{ t(kind === 'test' ? 'results.empty' : 'comments.emptyBatch') }}
            </td>
          </tr>
          <tr v-for="row in rows" :key="row.student.studentId" :data-student="row.student.fullName">
            <td>
              <div class="fw-medium text-break">{{ row.student.fullName }}</div>
              <small class="text-body-secondary">{{ row.student.code }}</small>
            </td>
            <td class="comment-cell">
              <textarea
                v-model="row.body"
                class="form-control form-control-sm"
                :class="{ 'is-invalid': tooLong(row) }"
                rows="2"
                :aria-label="`${t('comments.comment')}: ${row.student.fullName}`"
                :disabled="locked(row)"
                data-testid="comment-body"
              ></textarea>
              <small
                class="d-block text-end"
                :class="tooLong(row) ? 'text-danger' : 'text-body-secondary'"
                data-testid="comment-length"
              >
                {{ commentLength(row.body.trim()) }}/{{ COMMENT_MAX }}
              </small>
            </td>
            <td>
              <span
                class="badge"
                :class="statusClass[status(row)]"
                :title="
                  row.student.comment?.publishedAt
                    ? t('results.publishedBy', {
                        name: row.student.comment.publishedByName,
                        at: formatInstant(row.student.comment.publishedAt),
                      })
                    : undefined
                "
                data-testid="comment-status"
              >
                {{ t(`comments.status.${status(row)}`) }}
              </span>
            </td>
            <td v-if="canPublish" class="text-end text-nowrap">
              <button
                v-if="row.student.comment?.published"
                type="button"
                class="btn btn-outline-secondary btn-sm"
                :disabled="busy"
                data-testid="comment-unpublish"
                @click="publish(row.student.studentId, false)"
              >
                {{ t('results.unpublish') }}
              </button>
              <button
                v-else-if="row.student.comment && !changed(row)"
                type="button"
                class="btn btn-outline-primary btn-sm"
                :disabled="busy || dirtyCount > 0"
                data-testid="comment-publish"
                @click="publish(row.student.studentId, true)"
              >
                {{ t('results.publish') }}
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <p v-if="rows.some((row) => changed(row) && tooLong(row))" class="text-danger small mt-2">
      {{ t('comments.tooLong', { max: COMMENT_MAX }) }}
    </p>

    <template #footer>
      <span v-if="editable && dirtyCount" class="small text-body-secondary me-auto">
        {{ t('results.unsavedCount', { n: dirtyCount }) }}
      </span>
      <button type="button" class="btn btn-outline-secondary" @click="emit('close')">
        {{ t('common.close') }}
      </button>
      <button
        v-if="canPublish && anyPublished"
        type="button"
        class="btn btn-outline-secondary"
        data-testid="comments-unpublish-all"
        :disabled="busy"
        @click="publish(null, false)"
      >
        {{ t('results.unpublishAll') }}
      </button>
      <button
        v-if="canPublish && rows.length"
        type="button"
        class="btn btn-outline-primary"
        data-testid="comments-publish-all"
        :disabled="busy || dirtyCount > 0"
        @click="publish(null, true)"
      >
        {{ t('results.publishAll') }}
      </button>
      <button
        v-if="editable"
        type="button"
        class="btn btn-primary"
        data-testid="comments-save"
        :disabled="busy || !dirtyCount"
        @click="save"
      >
        {{ busy ? t('common.saving') : t('comments.save') }}
      </button>
    </template>
  </ModalDialog>
</template>
