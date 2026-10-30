<script setup lang="ts">
import { ClassDetail, type ClassSummary } from '@mledu/contracts/classes'
import { computed, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { RouterLink, useRoute, useRouter } from 'vue-router'
import { describeError, type DescribedError } from '../../app/errors'
import { apiRequest, workspace } from '../../app/session'
import ErrorAlert from '../../components/ErrorAlert.vue'
import FloatingAlert from '../../components/FloatingAlert.vue'
import { formatIsoDate, formatSchoolYear } from '../../lib/format'
import AssignmentsPanel from './AssignmentsPanel.vue'
import ClassFormDialog from './ClassFormDialog.vue'
import EnrollmentsPanel from './EnrollmentsPanel.vue'
import ClassLifecycleActions from './ClassLifecycleActions.vue'
import { periodBadge } from './labels'
import SchedulePanel from '../scheduling/SchedulePanel.vue'
import StaffWarnings from '../scheduling/StaffWarnings.vue'
import { ClassSchedule } from '@mledu/contracts/scheduling'

// One class (CLASS-03) with its staff (CLASS-01/02). The API answers 404 when
// the caller may not read it, including a User whose assignment just ended.
const { t, locale } = useI18n()
const route = useRoute()
const router = useRouter()

const TABS = ['staff', 'students', 'schedule'] as const
type Tab = (typeof TABS)[number]

const klass = ref<ClassDetail | null>(null)
const error = ref<DescribedError | null>(null)
const notice = ref<string | null>(null)
const editing = ref(false)
const scheduleWarnings = ref<ClassSchedule['warnings']>([])
const canManage = computed(() => workspace.value === 'admin' || workspace.value === 'receptionist')
const tab = computed<Tab>({
  get: () => (TABS.find((item) => item === route.query.tab) as Tab | undefined) ?? 'staff',
  set: (value) => void router.replace({ query: { ...route.query, tab: value } }),
})

async function load() {
  error.value = null
  try {
    klass.value = await apiRequest(`/v1/classes/${String(route.params.id)}`, {
      schema: ClassDetail,
    })
    scheduleWarnings.value = (
      await apiRequest(`/v1/classes/${String(route.params.id)}/schedule`, { schema: ClassSchedule })
    ).warnings
  } catch (cause) {
    klass.value = null
    error.value = describeError(cause)
  }
}
watch(() => route.params.id, load, { immediate: true })

function onSaved(saved: ClassSummary) {
  editing.value = false
  notice.value = t('classes.saved', { name: saved.name })
  void load()
}

const date = (value: string) => formatIsoDate(value, locale.value)
</script>

<template>
  <div class="container-fluid page class-detail-page">
    <div class="page-header">
      <div>
        <RouterLink class="small text-decoration-none" :to="{ name: 'classes' }">
          <i class="bi bi-arrow-left me-1" aria-hidden="true"></i>{{ t('classes.backToList') }}
        </RouterLink>
        <h1 class="page-title mt-1" data-testid="class-title">{{ klass?.name ?? '…' }}</h1>
        <p v-if="klass" class="text-body-secondary mb-0">
          {{ klass.subject.name }} · {{ klass.grade.name }} · {{ date(klass.startDate) }} –
          {{ date(klass.endDate) }}
        </p>
      </div>
      <div class="d-flex flex-wrap gap-2">
        <button
          v-if="klass && canManage && !klass.deleted"
          type="button"
          class="btn btn-outline-secondary"
          data-testid="class-edit"
          @click="editing = true"
        >
          <i class="bi bi-pencil me-1" aria-hidden="true"></i>{{ t('classes.actions.edit') }}
        </button>
        <ClassLifecycleActions v-if="klass && canManage" :klass="klass" @changed="load" />
      </div>
    </div>

    <FloatingAlert :message="notice" />
    <ErrorAlert :error="error" />

    <template v-if="klass">
      <StaffWarnings v-if="tab !== 'schedule'" :warnings="scheduleWarnings" />
      <div class="card mb-3">
        <div class="card-body">
          <dl class="row mb-0 class-facts">
            <dt class="col-sm-3">{{ t('classes.columns.status') }}</dt>
            <dd class="col-sm-9">
              <span v-if="klass.deleted" class="badge bg-danger-subtle text-danger-emphasis me-1">{{
                t('enrollments.classDeleted')
              }}</span>
              <span class="badge" :class="periodBadge[klass.period]">{{
                t(`classes.period.${klass.period}`)
              }}</span>
              <span v-if="klass.adminState === 'closed'" class="badge bg-secondary ms-1">{{
                t('classes.closed')
              }}</span>
              <span v-if="klass.myRole" class="badge text-bg-light border ms-1">{{
                t('classes.myRole', { role: t(`assignments.role.${klass.myRole}`) })
              }}</span>
            </dd>
            <dt class="col-sm-3">{{ t('classes.fields.subject') }}</dt>
            <dd class="col-sm-9">
              {{ klass.subject.name }}
              <span v-if="klass.subject.archived" class="badge text-bg-light border ms-1">{{
                t('catalogs.archivedBadge')
              }}</span>
            </dd>
            <dt class="col-sm-3">{{ t('classes.fields.grade') }}</dt>
            <dd class="col-sm-9">
              {{ klass.grade.name }}
              <span v-if="klass.grade.archived" class="badge text-bg-light border ms-1">{{
                t('catalogs.archivedBadge')
              }}</span>
            </dd>
            <dt class="col-sm-3">{{ t('classes.fields.schoolYear') }}</dt>
            <dd class="col-sm-9" data-testid="class-school-year">
              {{ formatSchoolYear(klass.schoolYearStart) || t('classes.noSchoolYear') }}
            </dd>
            <dt class="col-sm-3">{{ t('classes.fields.note') }}</dt>
            <dd class="col-sm-9 text-preline mb-0">{{ klass.note || '—' }}</dd>
          </dl>
        </div>
      </div>

      <div class="card data-card">
        <div class="card-header data-card-header">
          <div class="btn-group btn-group-sm" role="group" :aria-label="klass.name">
            <template v-for="item in TABS" :key="item">
              <input
                :id="`class-tab-${item}`"
                v-model="tab"
                type="radio"
                class="btn-check"
                name="class-tab"
                :value="item"
                autocomplete="off"
              />
              <label class="btn btn-outline-secondary" :for="`class-tab-${item}`">{{
                t(`classes.tabs.${item}`)
              }}</label>
            </template>
          </div>
        </div>
        <div class="card-body">
          <AssignmentsPanel
            v-if="tab === 'staff'"
            :klass="klass"
            :can-manage="canManage"
            @changed="load"
          />
          <EnrollmentsPanel
            v-if="tab === 'students'"
            :key="klass.id"
            :klass="klass"
            :can-manage="canManage"
          />
          <SchedulePanel v-if="tab === 'schedule'" :key="klass.id" :klass="klass" />
        </div>
      </div>
    </template>

    <ClassFormDialog
      v-if="editing && klass"
      :current="klass"
      @close="editing = false"
      @saved="onSaved"
    />
  </div>
</template>
