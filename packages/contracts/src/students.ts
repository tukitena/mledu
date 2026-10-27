import { z } from 'zod'
import { Reason } from './catalogs'
import { IsoDate, RowVersion } from './common'

/**
 * Student master records (STU-04/01/02). Every internal account searches the
 * whole centre; Admin and Receptionist create, edit, soft-delete and restore.
 */
export const StudentStatus = z.enum(['active', 'deleted'])
export type StudentStatus = z.infer<typeof StudentStatus>

export const Student = z.object({
  id: z.uuid(),
  /** Stable code (XLS-05), kept through export/import and restore. */
  code: z.string(),
  fullName: z.string(),
  parentName: z.string().nullable(),
  /** Normalized phone keys in entered order. */
  parentPhones: z.array(z.string()),
  studentPhones: z.array(z.string()),
  birthDate: IsoDate.nullable(),
  school: z.string().nullable(),
  generalNote: z.string().nullable(),
  status: StudentStatus,
  deletedAt: z.string().nullable(),
  deletedReason: z.string().nullable(),
  createdAt: z.string(),
  rowVersion: RowVersion,
})
export type Student = z.infer<typeof Student>

export const StudentPage = z.object({
  items: z.array(Student),
  page: z.number().int().min(1),
  pageSize: z.number().int().min(1),
  total: z.number().int().min(0),
})
export type StudentPage = z.infer<typeof StudentPage>

/** GET /v1/students — name (accents ignored), phone or code. */
export const ListStudentsQuery = z.object({
  search: z.string().trim().max(200).optional(),
  status: StudentStatus.default('active'),
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(20),
})
export type ListStudentsQuery = z.infer<typeof ListStudentsQuery>

const Phones = z.array(z.string().trim().max(32)).max(10)
const OptionalText = (max: number) => z.string().trim().max(max).nullable()

/** Full editable record; only the name is required (STU-04, C.1.1). */
export const StudentFields = z.strictObject({
  fullName: z.string().trim().min(1).max(200),
  parentName: OptionalText(200),
  parentPhones: Phones,
  studentPhones: Phones,
  birthDate: IsoDate.nullable(),
  school: OptionalText(200),
  generalNote: OptionalText(1000),
})
export type StudentFields = z.infer<typeof StudentFields>

/** POST /v1/students */
export const CreateStudentRequest = StudentFields
/** PUT /v1/students/:id */
export const UpdateStudentRequest = StudentFields.extend({ expectedVersion: RowVersion })
export type UpdateStudentRequest = z.infer<typeof UpdateStudentRequest>
/** POST /v1/students/:id/restore — conflicting data is corrected in the same request (STU-02). */
export const RestoreStudentRequest = UpdateStudentRequest
/** POST /v1/students/:id/delete (STU-01) */
export const SoftDeleteStudentRequest = z.strictObject({
  reason: Reason,
  expectedVersion: RowVersion,
})
