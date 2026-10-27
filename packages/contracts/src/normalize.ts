/**
 * Lookup key of a name (STU-04/D08), identical to app_private.name_key in the
 * database: NFD, combining marks removed, đ/Đ -> d, lower case, trimmed and
 * single-spaced. Punctuation is kept. Used only to compare and search; the
 * backend recomputes keys and stays the authority.
 */
export function nameKey(value: string): string {
  return value
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[đĐ]/g, 'd')
    .toLowerCase()
    .trim()
    .replace(/\s+/g, ' ')
}

/**
 * Phone lookup key (STU-04), identical to app_private.phone_key: separators
 * `. - ( )` and spaces dropped, +84/0084 -> 0. Returns null when the value is
 * not a valid Vietnamese (0 + 9–10 digits) or foreign (+ and 8–15 digits) number.
 */
export function phoneKey(value: string): string | null {
  let phone = value.replace(/[\s.()-]/g, '')
  if (phone.startsWith('+84')) phone = `0${phone.slice(3)}`
  else if (phone.startsWith('0084')) phone = `0${phone.slice(4)}`
  return /^(0[0-9]{9,10}|\+[0-9]{8,15})$/.test(phone) ? phone : null
}
