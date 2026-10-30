<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref, useId, watchEffect } from 'vue'
import { useI18n } from 'vue-i18n'
import { formatIsoDate, formatMonth, parseDisplayDate } from '../lib/format'

defineOptions({ inheritAttrs: false })
const props = withDefaults(
  defineProps<{
    mode?: 'date' | 'month'
    min?: string | undefined
    max?: string | undefined
    disabled?: boolean
    readonly?: boolean
    required?: boolean
  }>(),
  { mode: 'date', min: '', max: '' },
)
const model = defineModel<string | null>({ required: true })
const value = computed(() => model.value ?? '')
const emit = defineEmits<{ change: [] }>()
const { t, locale } = useI18n()
const input = ref<HTMLInputElement>()
const calendar = ref<HTMLElement>()
const calendarId = useId()
const open = ref(false)
const position = ref({ left: '0px', top: '0px' })
const today = () => new Date(Date.now() + 7 * 3600_000).toISOString().slice(0, 10)
const year = ref(Number(today().slice(0, 4)))
const month = ref(Number(today().slice(5, 7)))
const validYear = computed(
  () => Number.isInteger(year.value) && year.value >= 1 && year.value <= 9999,
)
const monthValue = computed(
  () => `${String(year.value).padStart(4, '0')}-${String(month.value).padStart(2, '0')}`,
)
const monthNames = computed(() =>
  Array.from({ length: 12 }, (_, i) =>
    locale.value === 'vi'
      ? `Tháng ${i + 1}`
      : new Intl.DateTimeFormat('en-GB', { month: 'long', timeZone: 'UTC' }).format(
          new Date(Date.UTC(2026, i, 1)),
        ),
  ),
)
const weekdays = computed(() =>
  locale.value === 'vi'
    ? ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN']
    : ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'],
)
const display = computed(() =>
  props.mode === 'month' && /^\d{4}-\d{2}$/.test(value.value)
    ? formatMonth(value.value, locale.value)
    : formatIsoDate(value.value),
)
const days = computed(() => {
  if (!validYear.value) return []
  const first = new Date(`${monthValue.value}-01T00:00:00Z`)
  const count = new Date(Date.UTC(year.value, month.value, 0)).getUTCDate()
  // Date.UTC treats years 0–99 specially; first is parsed from an ISO string.
  const leading = (first.getUTCDay() + 6) % 7
  return Array.from({ length: leading + count }, (_, i) =>
    i < leading ? '' : `${monthValue.value}-${String(i - leading + 1).padStart(2, '0')}`,
  )
})
const allowed = (value: string) =>
  (!props.min || value >= props.min) && (!props.max || value <= props.max)
const invalid = computed(
  () =>
    !!value.value &&
    (props.mode === 'date'
      ? parseDisplayDate(formatIsoDate(value.value)) !== value.value || !allowed(value.value)
      : !/^[0-9]{4}-(0[1-9]|1[0-2])$/.test(value.value)),
)
watchEffect(() =>
  input.value?.setCustomValidity(
    invalid.value
      ? t('dateInput.invalid')
      : props.required && !value.value
        ? t('dateInput.required')
        : '',
  ),
)

function typed(event: Event) {
  const value = (event.target as HTMLInputElement).value
  const iso = parseDisplayDate(value)
  // Keep invalid input in the model so a stale valid date can never be submitted.
  model.value = iso ?? value
  if (iso || !value) emit('change')
}
function place() {
  if (!calendar.value?.matches(':popover-open') || !input.value) return
  const anchor = input.value.getBoundingClientRect()
  const bounds = calendar.value.getBoundingClientRect()
  position.value = {
    left: `${Math.max(8, Math.min(anchor.left, innerWidth - bounds.width - 8))}px`,
    top: `${Math.max(8, Math.min(anchor.bottom + bounds.height + 6 <= innerHeight ? anchor.bottom + 6 : anchor.top - bounds.height - 6, innerHeight - bounds.height - 8))}px`,
  }
}
async function toggle() {
  if (props.disabled || props.readonly) return
  if (open.value) return calendar.value?.hidePopover()
  const selectedValue = /^\d{4}-\d{2}/.test(value.value) ? value.value : today()
  year.value = Number(selectedValue.slice(0, 4))
  month.value = Number(selectedValue.slice(5, 7))
  calendar.value?.showPopover()
  await nextTick()
  place()
  calendar.value?.querySelector<HTMLElement>('[aria-pressed="true"], select, input')?.focus()
}
function selected(value: string) {
  model.value = value
  emit('change')
  calendar.value?.hidePopover()
  void nextTick(() => input.value?.focus())
}
function move(direction: number) {
  if (!validYear.value) return
  if (props.mode === 'month') year.value = Math.min(9999, Math.max(1, year.value + direction))
  else {
    const index = (year.value - 1) * 12 + month.value - 1 + direction
    if (index < 0 || index >= 9999 * 12) return
    year.value = Math.floor(index / 12) + 1
    month.value = (index % 12) + 1
  }
}
function keydown(event: KeyboardEvent) {
  if (event.key === 'Escape') {
    event.stopPropagation()
    calendar.value?.hidePopover()
    input.value?.focus()
  }
}
function onToggle(event: Event) {
  open.value = (event as ToggleEvent).newState === 'open'
  place()
}
function closeCalendar() {
  calendar.value?.hidePopover()
  input.value?.focus()
}
// Existing forms intentionally use novalidate; dates must still reject malformed
// or out-of-range input before their submit handler can call the API.
function validateSubmit(event: Event) {
  if (input.value && !input.value.checkValidity()) {
    event.preventDefault()
    event.stopImmediatePropagation()
    input.value.reportValidity()
  }
}
let form: HTMLFormElement | null = null
let resizeObserver: ResizeObserver | undefined
onMounted(() => {
  form = input.value?.form ?? null
  form?.addEventListener('submit', validateSubmit, true)
  window.addEventListener('resize', place)
  window.addEventListener('scroll', place, true)
  resizeObserver = new ResizeObserver(place)
  if (calendar.value) resizeObserver.observe(calendar.value)
})
onBeforeUnmount(() => {
  form?.removeEventListener('submit', validateSubmit, true)
  window.removeEventListener('resize', place)
  window.removeEventListener('scroll', place, true)
  resizeObserver?.disconnect()
})
</script>

<template>
  <div class="date-input position-relative">
    <input
      ref="input"
      v-bind="$attrs"
      type="text"
      class="form-control date-input-text"
      :value="display"
      :placeholder="mode === 'date' ? 'dd-mm-yyyy' : t('dateInput.month')"
      :disabled="disabled"
      :readonly="readonly || mode === 'month'"
      :required="required"
      :aria-invalid="invalid || undefined"
      :aria-controls="calendarId"
      :aria-expanded="open"
      autocomplete="off"
      @input="typed"
      @keydown.alt.down.prevent="toggle"
      @click="mode === 'month' && !readonly && toggle()"
    />
    <button
      type="button"
      class="date-input-toggle btn"
      :aria-label="t('dateInput.open')"
      :aria-controls="calendarId"
      :aria-expanded="open"
      :disabled="disabled || readonly"
      @click="toggle"
    >
      <i class="bi bi-calendar3" aria-hidden="true"></i>
    </button>
    <div
      :id="calendarId"
      ref="calendar"
      popover="auto"
      class="date-calendar bg-body border rounded shadow p-3"
      :style="position"
      :aria-label="t('dateInput.calendar')"
      @keydown="keydown"
      @toggle="onToggle"
    >
      <div class="d-flex align-items-center gap-2 mb-3">
        <button
          type="button"
          class="btn btn-sm btn-outline-secondary"
          :aria-label="t('dateInput.previous')"
          @click="move(-1)"
        >
          <i class="bi bi-chevron-left" aria-hidden="true"></i>
        </button>
        <select
          v-if="mode === 'date'"
          v-model.number="month"
          class="form-select form-select-sm"
          :aria-label="t('dateInput.month')"
          form=""
        >
          <option v-for="(name, i) in monthNames" :key="name" :value="i + 1">{{ name }}</option>
        </select>
        <input
          v-model.number="year"
          type="number"
          min="1"
          max="9999"
          class="form-control form-control-sm date-calendar-year"
          :aria-label="t('dateInput.year')"
          form=""
        />
        <button
          type="button"
          class="btn btn-sm btn-outline-secondary"
          :aria-label="t('dateInput.next')"
          @click="move(1)"
        >
          <i class="bi bi-chevron-right" aria-hidden="true"></i>
        </button>
      </div>
      <div v-if="mode === 'month'" class="date-calendar-months">
        <button
          v-for="(name, i) in monthNames"
          :key="name"
          type="button"
          class="btn btn-sm"
          :class="{
            'btn-primary':
              model === `${String(year).padStart(4, '0')}-${String(i + 1).padStart(2, '0')}`,
          }"
          :disabled="!validYear"
          @click="selected(`${String(year).padStart(4, '0')}-${String(i + 1).padStart(2, '0')}`)"
        >
          {{ name }}
        </button>
      </div>
      <template v-else>
        <div class="date-calendar-grid small text-body-secondary text-center mb-2">
          <span v-for="name in weekdays" :key="name">{{ name }}</span>
        </div>
        <div class="date-calendar-grid">
          <template v-for="(day, index) in days" :key="index">
            <button
              v-if="day"
              type="button"
              class="btn btn-sm date-calendar-day"
              :class="{ 'btn-primary': day === model, 'border-primary': day === today() }"
              :aria-label="formatIsoDate(day)"
              :aria-pressed="day === model"
              :disabled="!allowed(day)"
              @click="selected(day)"
            >
              {{ Number(day.slice(8)) }}
            </button>
            <span v-else></span>
          </template>
        </div>
      </template>
      <div class="d-flex justify-content-between border-top pt-2 mt-2">
        <button
          type="button"
          class="btn btn-sm btn-link"
          :disabled="!allowed(mode === 'month' ? today().slice(0, 7) : today())"
          @click="selected(mode === 'month' ? today().slice(0, 7) : today())"
        >
          {{ t('dateInput.today') }}
        </button>
        <button
          v-if="!required && mode === 'date'"
          type="button"
          class="btn btn-sm btn-link"
          @click="selected('')"
        >
          {{ t('dateInput.clear') }}
        </button>
        <button type="button" class="btn btn-sm btn-link" @click="closeCalendar">
          {{ t('common.close') }}
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.date-input-text {
  padding-right: 2.75rem;
}
.date-input-toggle {
  position: absolute;
  right: 0.25rem;
  top: 0;
  height: 2.3rem;
  color: var(--bs-body-color);
}
.date-calendar {
  position: fixed;
  margin: 0;
  width: 320px;
  max-width: calc(100vw - 16px);
  color: var(--bs-body-color);
}
.date-calendar-year {
  min-width: 5rem;
}
.date-calendar-grid {
  display: grid;
  grid-template-columns: repeat(7, 1fr);
  gap: 0.125rem;
}
.date-calendar-months {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 0.25rem;
}
.date-calendar-day {
  aspect-ratio: 1;
  padding: 0.25rem;
}
.date-calendar .btn:not(.btn-primary):hover {
  background: rgba(var(--bs-primary-rgb), 0.1);
}
</style>
