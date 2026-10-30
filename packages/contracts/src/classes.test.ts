import { describe, expect, it } from 'vitest'
import { CreateClassRequest, ListClassesQuery, UpdateClassRequest } from './classes'

const fields = {
  name: 'Lớp năm học',
  subjectId: '10000000-0000-4000-8000-000000000001',
  gradeId: '10000000-0000-4000-8000-000000000011',
  startDate: '2030-01-01',
  endDate: '2030-02-01',
  note: null,
}

describe('CLASS-03 optional school year', () => {
  it('accepts a standard year or no year independently of class dates', () => {
    for (const schoolYearStart of [null, 1000, 2026, 9998]) {
      expect(CreateClassRequest.safeParse({ ...fields, schoolYearStart }).success).toBe(true)
    }
    expect(CreateClassRequest.safeParse(fields).success).toBe(true)
    // Omitted on an older client update means preserve, explicit null means clear.
    expect(UpdateClassRequest.parse({ ...fields, expectedVersion: 1 })).not.toHaveProperty(
      'schoolYearStart',
    )
  })

  it('rejects malformed years on writes', () => {
    for (const schoolYearStart of [999, 9999, 2026.5, '2026', '2026–2027', '']) {
      expect(CreateClassRequest.safeParse({ ...fields, schoolYearStart }).success).toBe(false)
    }
  })

  it('distinguishes all, none and exact year filters and rejects invalid values', () => {
    expect(ListClassesQuery.parse({}).schoolYear).toBe('all')
    for (const schoolYear of ['all', 'none', '1000', '2026', '9998']) {
      expect(ListClassesQuery.parse({ schoolYear }).schoolYear).toBe(schoolYear)
    }
    for (const schoolYear of ['', 'null', '999', '9999', '02026', '2026.5', '2026–2027']) {
      expect(ListClassesQuery.safeParse({ schoolYear }).success).toBe(false)
    }
  })
})
