import { z } from 'zod'
import { Reason } from './catalogs'
import { IsoDate, RowVersion } from './common'

/** STU-03: status is computed by the backend, never accepted as input. */
export const Participation = z.object({
  id: z.uuid(),
  classStudentId: z.uuid(),
  joinDate: IsoDate,
  leaveDate: IsoDate.nullable(),
  classEndDate: IsoDate,
  note: z.string().nullable(),
  status: z.enum(['not_started', 'active', 'ended', 'cancelled']),
  effectiveFrom: z.string().nullable(),
  effectiveUntil: z.string().nullable(),
  endedAt: z.string().nullable(),
  endKind: z.enum(['cancelled', 'record_deleted', 'student_deleted', 'class_deleted']).nullable(),
  endReason: z.string().nullable(),
  rowVersion: RowVersion,
})
export type Participation = z.infer<typeof Participation>
export const ClassStudent = z.object({
  id: z.uuid(),
  classId: z.uuid(),
  className: z.string(),
  classDeleted: z.boolean(),
  classAdminState: z.enum(['open', 'closed']),
  student: z.object({ id: z.uuid(), code: z.string(), fullName: z.string(), deleted: z.boolean() }),
  deleted: z.boolean(),
  deletedAt: z.string().nullable(),
  deletedReason: z.string().nullable(),
  createdAt: z.string(),
  participations: z.array(Participation),
  /** Note/first leave date only; never grants enrollment or lifecycle actions. */
  canEdit: z.boolean(),
  rowVersion: RowVersion,
})
export type ClassStudent = z.infer<typeof ClassStudent>
const Note = z.string().trim().max(1000).nullable()
export const EnrollStudentRequest = z
  .strictObject({
    studentId: z.uuid(),
    joinDate: IsoDate,
    leaveDate: IsoDate.nullable(),
    note: Note,
  })
  .refine((v) => !v.leaveDate || v.leaveDate > v.joinDate, {
    path: ['leaveDate'],
    message: 'Leave date must follow join date',
  })
export const SetLeaveDateRequest = z.strictObject({
  leaveDate: IsoDate,
  expectedVersion: RowVersion,
})
export const SetParticipationNoteRequest = z.strictObject({
  note: Note,
  expectedVersion: RowVersion,
})
export const ReasonVersionRequest = z.strictObject({ reason: Reason, expectedVersion: RowVersion })
export const VersionRequest = z.strictObject({ expectedVersion: RowVersion })
export const TransferStudentRequest = z.strictObject({
  targetClassId: z.uuid(),
  leaveDate: IsoDate.nullable(),
  joinDate: IsoDate,
  note: Note,
  expectedVersion: RowVersion,
})
export const ListClassStudentsQuery = z.object({
  includeDeleted: z
    .enum(['true', 'false'])
    .default('false')
    .transform((v) => v === 'true'),
})
export const ParticipationImpact = z.object({
  activeParticipations: z.number().int().nonnegative(),
  futureParticipations: z.number().int().nonnegative(),
})
export const StudentDeleteImpact = ParticipationImpact.extend({ classes: z.array(z.string()) })
export type StudentDeleteImpact = z.infer<typeof StudentDeleteImpact>
export const ClassLifecycleImpact = ParticipationImpact.extend({
  activeAssignments: z.number().int().nonnegative(),
})
export type ClassLifecycleImpact = z.infer<typeof ClassLifecycleImpact>
