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
