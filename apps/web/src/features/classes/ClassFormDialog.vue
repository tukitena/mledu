<script setup lang="ts">
import { CatalogEntry } from '@mledu/contracts/catalogs'
import { ClassSummary, SchoolYearStart, type ClassFields } from '@mledu/contracts/classes'
import { computed, onMounted, reactive, ref } from 'vue'
import { formatSchoolYear } from '../../lib/format'
import { useI18n } from 'vue-i18n'
import { z } from 'zod'
import { describeError, type DescribedError } from '../../app/errors'
import { apiRequest } from '../../app/session'
import ErrorAlert from '../../components/ErrorAlert.vue'
import ModalDialog from '../../components/ModalDialog.vue'

// Create/edit a class (CLASS-03). Only active subjects/grades are offered; an
// archived one already on the class stays selectable so other edits work.
const props = defineProps<{ current: ClassSummary | null }>()
const emit = defineEmits<{ close: []; saved: [value: ClassSummary] }>()
const { t } = useI18n()

const subjects = ref<{ id: string; name: string }[]>([])
const grades = ref<{ id: string; name: string }[]>([])
const form = reactive<ClassFields>({
  name: props.current?.name ?? '',
  subjectId: props.current?.subject.id ?? '',
  gradeId: props.current?.grade.id ?? '',
  startDate: props.current?.startDate ?? '',
  endDate: props.current?.endDate ?? '',
  note: props.current?.note ?? null,
})
const busy = ref(false)
const schoolYearInput = ref<number | string>(props.current?.schoolYearStart ?? '')
// A malformed number (e.g. an incomplete exponent) also reports value=''.
// Only an intentionally empty input may clear the year.
const schoolYearBadInput = ref(false)
const schoolYearStart = computed(() =>
  schoolYearInput.value === '' ? null : Number(schoolYearInput.value),
)
const validSchoolYear = computed(
  () =>
    !schoolYearBadInput.value &&
    SchoolYearStart.nullable().safeParse(schoolYearStart.value).success,
)
const error = ref<DescribedError | null>(null)

const withCurrent = (
  entries: CatalogEntry[],
  current: { id: string; name: string; archived: boolean } | undefined,
) =>
  current && !entries.some((entry) => entry.id === current.id)
    ? [...entries, { id: current.id, name: `${current.name} (${t('catalogs.archivedBadge')})` }]
    : entries

onMounted(async () => {
  try {
    const [subjectList, gradeList] = await Promise.all([
      apiRequest('/v1/catalogs/subjects', { schema: z.array(CatalogEntry) }),
      apiRequest('/v1/catalogs/grades', { schema: z.array(CatalogEntry) }),
    ])
    subjects.value = withCurrent(subjectList, props.current?.subject)
    grades.value = withCurrent(gradeList, props.current?.grade)
  } catch (cause) {
    error.value = describeError(cause)
  }
})

const valid = computed(
  () =>
    form.name.trim() !== '' &&
    form.subjectId !== '' &&
    form.gradeId !== '' &&
    validSchoolYear.value &&
    form.startDate !== '' &&
    form.endDate !== '' &&
    form.endDate >= form.startDate,
)

async function submit() {
  if (!valid.value || busy.value) return
  busy.value = true
  error.value = null
  const body = {
    ...form,
    schoolYearStart: schoolYearStart.value,
    note: form.note?.trim() ? form.note : null,
  }
  try {
    const saved = props.current
      ? await apiRequest(`/v1/classes/${props.current.id}`, {
          method: 'PUT',
          body: { ...body, expectedVersion: props.current.rowVersion },
          schema: ClassSummary,
        })
      : await apiRequest('/v1/classes', { method: 'POST', body, schema: ClassSummary })
    emit('saved', saved)
  } catch (cause) {
    error.value = describeError(cause)
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <ModalDialog
    :title="
      props.current ? t('classes.editTitle', { name: props.current.name }) : t('classes.create')
    "
    @close="emit('close')"
  >
    <p v-if="props.current" class="small text-body-secondary">{{ t('classes.dateRule') }}</p>
    <ErrorAlert :error="error" />
    <form id="class-form" novalidate @submit.prevent="submit">
      <div class="mb-3">
        <label class="form-label" for="class-name">{{ t('classes.fields.name') }}</label>
        <input id="class-name" v-model="form.name" class="form-control" maxlength="200" required />
      </div>
      <div class="mb-3">
        <label class="form-label" for="class-school-year">
          {{ t('classes.fields.schoolYear') }}
          <span class="text-body-secondary">({{ t('common.optional') }})</span>
        </label>
        <input
          id="class-school-year"
          v-model="schoolYearInput"
          type="number"
          class="form-control"
          :class="{ 'is-invalid': !validSchoolYear }"
          min="1000"
          max="9998"
          step="1"
          placeholder="2026"
          aria-describedby="class-school-year-hint class-school-year-error"
          :aria-invalid="!validSchoolYear"
          @input="schoolYearBadInput = ($event.target as HTMLInputElement).validity.badInput"
        />
        <div id="class-school-year-hint" class="form-text">
          {{ t('classes.schoolYearHint') }}
          <span
            v-if="validSchoolYear && schoolYearStart !== null"
            class="fw-medium"
            data-testid="school-year-preview"
            >{{ formatSchoolYear(schoolYearStart) }}</span
          >
        </div>
        <div id="class-school-year-error" class="invalid-feedback">
          {{ t('classes.invalidSchoolYear') }}
        </div>
      </div>
      <div class="row g-3 mb-3">
        <div class="col-12 col-sm-6">
          <label class="form-label" for="class-subject">{{ t('classes.fields.subject') }}</label>
          <select id="class-subject" v-model="form.subjectId" class="form-select" required>
            <option value="" disabled>{{ t('classes.choose') }}</option>
            <option v-for="item in subjects" :key="item.id" :value="item.id">
              {{ item.name }}
            </option>
          </select>
        </div>
        <div class="col-12 col-sm-6">
          <label class="form-label" for="class-grade">{{ t('classes.fields.grade') }}</label>
          <select id="class-grade" v-model="form.gradeId" class="form-select" required>
            <option value="" disabled>{{ t('classes.choose') }}</option>
            <option v-for="item in grades" :key="item.id" :value="item.id">{{ item.name }}</option>
          </select>
        </div>
      </div>
      <div class="row g-3 mb-3">
        <div class="col-12 col-sm-6">
          <label class="form-label" for="class-start">{{ t('classes.fields.startDate') }}</label>
          <input
            id="class-start"
            v-model="form.startDate"
            type="date"
            class="form-control"
            required
          />
        </div>
        <div class="col-12 col-sm-6">
          <label class="form-label" for="class-end">{{ t('classes.fields.endDate') }}</label>
          <input
            id="class-end"
            v-model="form.endDate"
            type="date"
            class="form-control"
            :min="form.startDate"
            required
          />
        </div>
      </div>
      <div>
        <label class="form-label" for="class-note">
          {{ t('classes.fields.note') }}
          <span class="text-body-secondary">({{ t('common.optional') }})</span>
        </label>
        <textarea
          id="class-note"
          v-model="form.note"
          class="form-control"
          rows="3"
          maxlength="1000"
        ></textarea>
      </div>
    </form>
    <template #footer>
      <button type="button" class="btn btn-outline-secondary" @click="emit('close')">
        {{ t('common.cancel') }}
      </button>
      <button
        type="submit"
        form="class-form"
        class="btn btn-primary"
        :disabled="busy || !valid"
        data-testid="class-submit"
      >
        {{ t('common.save') }}
      </button>
    </template>
  </ModalDialog>
</template>
