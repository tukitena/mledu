import { z } from 'zod'
import { ClassSession } from './scheduling'

export const AttendanceStudent = z.object({
  studentId: z.uuid(),
  code: z.string(),
  fullName: z.string(),
  present: z.boolean().nullable(),
  note: z.string().nullable(),
})
export const Attendance = z.object({
  session: ClassSession,
  students: z.array(AttendanceStudent),
  fingerprint: z.string(),
})
export type Attendance = z.infer<typeof Attendance>
export const SaveAttendance = z.strictObject({
  fingerprint: z.string().regex(/^[a-f0-9]{32}$/),
  students: z.array(
    z.strictObject({
      studentId: z.uuid(),
      present: z.boolean(),
      note: z.string().max(1000).nullable(),
    }),
  ),
})
