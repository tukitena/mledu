/** UX-01: calendar dates always display dd-mm-yyyy, independently of browser locale/time zone. */
export function formatIsoDate(value: string | null | undefined): string {
  if (!value) return ''
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value)
  return match ? `${match[3]}-${match[2]}-${match[1]}` : value
}

/** Reject impossible dates instead of allowing Date to roll them into the next month. */
export function parseDisplayDate(value: string): string | null {
  const match = /^(\d{2})-(\d{2})-([0-9]{4})$/.exec(value)
  if (!match || match[3] === '0000') return null
  const iso = `${match[3]}-${match[2]}-${match[1]}`
  const date = new Date(`${iso}T00:00:00Z`)
  return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === iso ? iso : null
}

export function formatMonth(value: string, locale: string): string {
  const month = Number(value.slice(5, 7))
  if (locale === 'vi') return `Tháng ${month} ${value.slice(0, 4)}`
  return new Intl.DateTimeFormat('en-GB', {
    month: 'long',
    year: 'numeric',
    timeZone: 'UTC',
  }).format(new Date(`${value}-01T00:00:00Z`))
}

/** Precise instants use the business timezone, never the viewer's device timezone. */
export function formatInstant(value: string | null | undefined): string {
  if (!value) return ''
  const parts = new Intl.DateTimeFormat('en-GB', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
    timeZone: 'Asia/Ho_Chi_Minh',
  }).formatToParts(new Date(value))
  const part = (type: Intl.DateTimeFormatPartTypes) => parts.find((p) => p.type === type)?.value
  return `${part('day')}-${part('month')}-${part('year')} ${part('hour')}:${part('minute')}`
}

/** The school year is a label, independent of operational class dates. */
export function formatSchoolYear(start: number | null): string {
  return start === null ? '' : `${start}–${start + 1}`
}
