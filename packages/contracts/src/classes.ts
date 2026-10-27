import { z } from 'zod'
import { Reason } from './catalogs'
import { AccountType, IsoDate, RowVersion } from './common'

/**
 * Classes (CLASS-03) and dated teacher/assistant assignments (CLASS-01/02).
 * Admin/Receptionist manage; a User sees the classes it currently teaches.
 */
export const ClassRole = z.enum(['teacher', 'assistant'])
export type ClassRole = z.infer<typeof ClassRole>

/** Catalog entry referenced by a class; archived entries keep their name (CAT-01). */
export const CatalogRef = z.object({ id: z.uuid(), name: z.string(), archived: z.boolean() })

export const ClassSummary = z.object({
  id: z.uuid(),
  name: z.string(),
  subject: CatalogRef,
  grade: CatalogRef,
  startDate: IsoDate,
  endDate: IsoDate,
  note: z.string().nullable(),
  /** CLASS-05 administrative state. */
  adminState: z.enum(['open', 'closed']),
  /** Position of today relative to the class dates (Asia/Ho_Chi_Minh). */
  period: z.enum(['upcoming', 'running', 'ended']),
  deleted: z.boolean(),
  deletedAt: z.string().nullable(),
  deletedReason: z.string().nullable(),
  /** Staff whose assignment is in effect right now. */
  currentStaff: z.array(z.object({ accountId: z.uuid(), fullName: z.string(), role: ClassRole })),
  rowVersion: RowVersion,
})
export type ClassSummary = z.infer<typeof ClassSummary>

/** GET /v1/classes/:id — also the caller's current role in the class, if any. */
export const ClassDetail = ClassSummary.extend({ myRole: ClassRole.nullable() })
export type ClassDetail = z.infer<typeof ClassDetail>

export const ClassPage = z.object({
  items: z.array(ClassSummary),
  page: z.number().int().min(1),
  pageSize: z.number().int().min(1),
  total: z.number().int().min(0),
})
export type ClassPage = z.infer<typeof ClassPage>

/** GET /v1/classes — `deleted=true` lists soft-deleted classes (Admin/Receptionist). */
export const ListClassesQuery = z.object({
  search: z.string().trim().max(200).optional(),
  deleted: z
    .enum(['true', 'false'])
    .optional()
    .transform((value) => value === 'true'),
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(20),
})

export const ClassFields = z.strictObject({
  name: z.string().trim().min(1).max(200),
  subjectId: z.uuid(),
  gradeId: z.uuid(),
  startDate: IsoDate,
  endDate: IsoDate,
  note: z.string().trim().max(1000).nullable(),
})
export type ClassFields = z.infer<typeof ClassFields>

/** POST /v1/classes */
export const CreateClassRequest = ClassFields
/** PUT /v1/classes/:id */
export const UpdateClassRequest = ClassFields.extend({ expectedVersion: RowVersion })

export const AssignmentStatus = z.enum(['not_started', 'active', 'expired', 'ended', 'cancelled'])
export type AssignmentStatus = z.infer<typeof AssignmentStatus>

export const Assignment = z.object({
  id: z.uuid(),
  classId: z.uuid(),
  accountId: z.uuid(),
  fullName: z.string(),
  email: z.string(),
  role: ClassRole,
  startDate: IsoDate,
  endDate: IsoDate,
  subjectNote: z.string().nullable(),
  status: AssignmentStatus,
  endedAt: z.string().nullable(),
  endKind: z
    .enum(['ended_early', 'cancelled', 'cancelled_account_deleted', 'cancelled_account_type'])
    .nullable(),
  endReason: z.string().nullable(),
  rowVersion: RowVersion,
})
export type Assignment = z.infer<typeof Assignment>

/** GET /v1/assignments/assignable-accounts */
export const AssignableAccount = z.object({
  id: z.uuid(),
  fullName: z.string(),
  email: z.string(),
  accountType: AccountType,
})
export type AssignableAccount = z.infer<typeof AssignableAccount>

const AssignmentFields = {
  role: ClassRole,
  startDate: IsoDate,
  endDate: IsoDate,
  /** Optional teaching speciality, at most 200 characters (CLASS-01). */
  subjectNote: z.string().trim().max(200).nullable(),
}

/** POST /v1/classes/:id/assignments */
export const CreateAssignmentRequest = z.strictObject({ accountId: z.uuid(), ...AssignmentFields })
/** PUT /v1/assignments/:id */
export const UpdateAssignmentRequest = z.strictObject({
  ...AssignmentFields,
  expectedVersion: RowVersion,
})
/** POST /v1/assignments/:id/end — ends now, or cancels when not started yet. */
export const EndAssignmentRequest = z.strictObject({ reason: Reason, expectedVersion: RowVersion })
