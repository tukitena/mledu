<script setup lang="ts">
import { ClassPage, type ClassSummary } from '@mledu/contracts/classes'
import { computed, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { RouterLink, useRouter } from 'vue-router'
import { describeError, type DescribedError } from '../../app/errors'
import { apiRequest, workspace } from '../../app/session'
import ErrorAlert from '../../components/ErrorAlert.vue'
import FloatingAlert from '../../components/FloatingAlert.vue'
import RowActionMenu, { type RowAction } from '../../components/RowActionMenu.vue'
import { formatIsoDate } from '../../lib/format'
import ClassFormDialog from './ClassFormDialog.vue'
import { periodBadge } from './labels'

// Classes (CLASS-03). Admin/Receptionist see every class; the API returns a
// User only the classes in which it has an assignment in effect now.
const { t, locale } = useI18n()
const router = useRouter()
const PAGE_SIZE = 20

const canManage = computed(() => workspace.value === 'admin' || workspace.value === 'receptionist')
const search = ref('')
const page = ref(1)
const result = ref<ClassPage | null>(null)
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
    result.value = await apiRequest(`/v1/classes?${query}`, { schema: ClassPage })
  } catch (cause) {
    error.value = describeError(cause)
  } finally {
    loading.value = false
  }
}
onMounted(load)
// The list depends on the workspace for an Admin (all classes vs. own classes).
watch(workspace, () => void load())

const editing = ref<{ current: ClassSummary | null } | null>(null)

function onSaved(saved: ClassSummary) {
  const created = !editing.value?.current
  editing.value = null
  notice.value = t('classes.saved', { name: saved.name })
  if (created) void router.push({ name: 'class-detail', params: { id: saved.id } })
  else void load()
}

function actionsFor(): RowAction[] {
  const open = { key: 'open', label: t('classes.actions.open') }
  return canManage.value ? [open, { key: 'edit', label: t('classes.actions.edit') }] : [open]
}

function onAction(item: ClassSummary, key: string) {
  notice.value = null
  if (key === 'open') void router.push({ name: 'class-detail', params: { id: item.id } })
  if (key === 'edit') editing.value = { current: item }
}

const dates = (item: ClassSummary) =>
  `${formatIsoDate(item.startDate, locale.value)} – ${formatIsoDate(item.endDate, locale.value)}`
const staffNames = (item: ClassSummary) =>
  item.currentStaff.map((staff) => staff.fullName).join(', ')
</script>

<template>
  <div class="container-fluid page classes-page">
    <div class="page-header">
      <div>
        <h1 class="page-title">{{ canManage ? t('classes.title') : t('classes.myTitle') }}</h1>
        <p class="text-body-secondary mb-0">
          {{ canManage ? t('classes.subtitle') : t('classes.mySubtitle') }}
        </p>
      </div>
      <button
        v-if="canManage"
        type="button"
        class="btn btn-primary"
        data-testid="class-create"
        @click="editing = { current: null }"
      >
        <i class="bi bi-plus-lg me-1" aria-hidden="true"></i>{{ t('classes.create') }}
      </button>
    </div>

    <div class="card data-card">
      <div class="card-body">
        <form class="row g-3 table-controls" role="search" @submit.prevent="((page = 1), load())">
          <div class="col-8 col-md-9">
            <input
              v-model="search"
              type="search"
              class="form-control"
              :placeholder="t('classes.searchPlaceholder')"
              :aria-label="t('common.search')"
            />
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
            class="table table-hover align-middle mb-0 data-table"
            data-testid="classes-table"
            :aria-busy="loading"
          >
            <thead>
              <tr>
                <th scope="col">{{ t('classes.columns.name') }}</th>
                <th scope="col">{{ t('classes.columns.subjectGrade') }}</th>
                <th scope="col">{{ t('classes.columns.dates') }}</th>
                <th scope="col">{{ t('classes.columns.staff') }}</th>
                <th scope="col">{{ t('classes.columns.status') }}</th>
                <th scope="col" class="text-end">{{ t('common.actions') }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-if="loading && !result">
                <td colspan="6" class="text-body-secondary">{{ t('common.loading') }}</td>
              </tr>
              <tr v-else-if="result && !result.items.length">
                <td colspan="6" class="text-body-secondary">
                  {{ canManage ? t('classes.empty') : t('classes.myEmpty') }}
                </td>
              </tr>
              <tr v-for="item in result?.items ?? []" :key="item.id" :data-name="item.name">
                <td>
                  <RouterLink
                    class="fw-medium text-decoration-none"
                    :to="{ name: 'class-detail', params: { id: item.id } }"
                    >{{ item.name }}</RouterLink
                  >
                </td>
                <td class="small">{{ item.subject.name }} · {{ item.grade.name }}</td>
                <td class="small text-nowrap">{{ dates(item) }}</td>
                <td class="small">{{ staffNames(item) || '—' }}</td>
                <td>
                  <span class="badge" :class="periodBadge[item.period]">{{
                    t(`classes.period.${item.period}`)
                  }}</span>
                  <span v-if="item.adminState === 'closed'" class="badge bg-secondary ms-1">{{
                    t('classes.closed')
                  }}</span>
                </td>
                <td class="text-end">
                  <RowActionMenu
                    :id="item.id"
                    :label="`${t('common.actions')}: ${item.name}`"
                    :items="actionsFor()"
                    @select="onAction(item, $event)"
                  />
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
            t('classes.total', { n: result.total })
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

    <ClassFormDialog
      v-if="editing"
      :current="editing.current"
      @close="editing = null"
      @saved="onSaved"
    />
  </div>
</template>
