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
import { formatIsoDate, formatSchoolYear } from '../../lib/format'
import ClassFormDialog from './ClassFormDialog.vue'
import { periodBadge } from './labels'

// Classes (CLASS-03). Admin/Receptionist see every class; the API returns a
// User only the classes in which it has an assignment in effect now.
const { t, locale } = useI18n()
const router = useRouter()
const PAGE_SIZE = 20

const canManage = computed(() => workspace.value === 'admin' || workspace.value === 'receptionist')
const search = ref('')
const schoolYear = ref('all')
const gradeId = ref('')
const subjectId = ref('')
const status = ref('all')
const staffId = ref('')
const page = ref(1)
const result = ref<ClassPage | null>(null)
const loading = ref(false)
const error = ref<DescribedError | null>(null)
const notice = ref<string | null>(null)
const pages = computed(() => Math.max(1, Math.ceil((result.value?.total ?? 0) / PAGE_SIZE)))
const schoolYears = computed(() => {
  const years = result.value?.schoolYears ?? []
  // Keep a selected year visible even when its last class is moved to another year.
  return [
    ...new Set([...years, ...(/^\d{4}$/.test(schoolYear.value) ? [Number(schoolYear.value)] : [])]),
  ].sort((a, b) => b - a)
})
let loadId = 0

async function load() {
  const requestId = ++loadId
  loading.value = true
  error.value = null
  try {
    const query = new URLSearchParams({ page: String(page.value), pageSize: String(PAGE_SIZE) })
    query.set('schoolYear', schoolYear.value)
    query.set('status', status.value)
    if (gradeId.value) query.set('gradeId', gradeId.value)
    if (subjectId.value) query.set('subjectId', subjectId.value)
    if (staffId.value) query.set('staffId', staffId.value)
    if (search.value.trim()) query.set('search', search.value.trim())
    const data = await apiRequest(`/v1/classes?${query}`, { schema: ClassPage })
    if (requestId === loadId) result.value = data
  } catch (cause) {
    if (requestId === loadId) error.value = describeError(cause)
  } finally {
    if (requestId === loadId) loading.value = false
  }
}
onMounted(load)
// The list depends on the workspace for an Admin (all classes vs. own classes).
watch([workspace, schoolYear, gradeId, subjectId, status, staffId], ([current], [previous]) => {
  if (current !== previous) {
    result.value = null
    schoolYear.value = 'all'
    gradeId.value = ''
    subjectId.value = ''
    status.value = 'all'
    staffId.value = ''
  }
  page.value = 1
  void load()
})

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
        <form class="row g-2 table-controls" role="search" @submit.prevent="((page = 1), load())">
          <div class="col-12 col-sm-6 col-lg-4">
            <div class="input-group">
              <input
                v-model="search"
                type="search"
                class="form-control"
                :placeholder="t('classes.searchPlaceholder')"
                :aria-label="t('common.search')"
              />
              <button type="submit" class="btn btn-outline-secondary">
                <i class="bi bi-search" aria-hidden="true"></i>
                <span class="visually-hidden">{{ t('common.search') }}</span>
              </button>
            </div>
          </div>
          <div class="col-12 col-sm-6 col-lg-4">
            <select
              v-model="schoolYear"
              class="form-select"
              :aria-label="t('classes.filterSchoolYear')"
            >
              <option value="all">{{ t('classes.allSchoolYears') }}</option>
              <option value="none">{{ t('classes.noSchoolYear') }}</option>
              <option v-for="year in schoolYears" :key="year" :value="String(year)">
                {{ formatSchoolYear(year) }}
              </option>
            </select>
          </div>
          <div class="col-12 col-sm-6 col-lg-4">
            <select v-model="gradeId" class="form-select" :aria-label="t('classes.filterGrade')">
              <option value="">{{ t('classes.allGrades') }}</option>
              <option
                v-for="grade in result?.filterOptions.grades ?? []"
                :key="grade.id"
                :value="grade.id"
              >
                {{ grade.name }}
              </option>
            </select>
          </div>
          <div class="col-12 col-sm-6 col-lg-4">
            <select
              v-model="subjectId"
              class="form-select"
              :aria-label="t('classes.filterSubject')"
            >
              <option value="">{{ t('classes.allSubjects') }}</option>
              <option
                v-for="subject in result?.filterOptions.subjects ?? []"
                :key="subject.id"
                :value="subject.id"
              >
                {{ subject.name }}
              </option>
            </select>
          </div>
          <div class="col-12 col-sm-6 col-lg-4">
            <select v-model="status" class="form-select" :aria-label="t('classes.filterStatus')">
              <option value="all">{{ t('classes.allStatuses') }}</option>
              <option value="open">{{ t('classes.open') }}</option>
              <option value="closed">{{ t('classes.closed') }}</option>
              <option
                v-for="period in ['upcoming', 'running', 'ended']"
                :key="period"
                :value="period"
              >
                {{ t(`classes.period.${period}`) }}
              </option>
            </select>
          </div>
          <div class="col-12 col-sm-6 col-lg-4">
            <select v-model="staffId" class="form-select" :aria-label="t('classes.filterStaff')">
              <option value="">{{ t('classes.allStaff') }}</option>
              <option
                v-for="person in result?.filterOptions.staff ?? []"
                :key="person.id"
                :value="person.id"
              >
                {{ person.fullName }}
              </option>
            </select>
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
                <th scope="col">{{ t('classes.fields.schoolYear') }}</th>
                <th scope="col">{{ t('classes.columns.dates') }}</th>
                <th scope="col">{{ t('classes.columns.staff') }}</th>
                <th scope="col">{{ t('classes.columns.status') }}</th>
                <th scope="col" class="text-end">{{ t('common.actions') }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-if="loading && !result">
                <td colspan="7" class="text-body-secondary">{{ t('common.loading') }}</td>
              </tr>
              <tr v-else-if="result && !result.items.length">
                <td colspan="7" class="text-body-secondary">
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
                <td class="small text-nowrap">
                  {{ formatSchoolYear(item.schoolYearStart) || t('classes.noSchoolYear') }}
                </td>
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
