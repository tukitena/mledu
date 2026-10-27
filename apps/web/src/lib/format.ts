/**
 * Business dates are calendar days (`YYYY-MM-DD`, Asia/Ho_Chi_Minh). They are
 * formatted as UTC so the browser's own time zone never shifts the day.
 */
export function formatIsoDate(value: string | null | undefined, locale: string): string {
  if (!value) return ''
  return new Intl.DateTimeFormat(locale === 'vi' ? 'vi-VN' : 'en-GB', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    timeZone: 'UTC',
  }).format(new Date(`${value}T00:00:00Z`))
}
