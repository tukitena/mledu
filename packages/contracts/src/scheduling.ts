import { z } from 'zod'
import { IsoDate, RowVersion } from './common'

export const Time = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/)
const times = <T extends { startTime: string; endTime: string }>(value: T) =>
  value.endTime > value.startTime
export const WeeklySlot = z
  .strictObject({
    weekday: z.number().int().min(1).max(7),
    startTime: Time,
    endTime: Time,
    roomId: z.uuid().nullable(),
  })
  .refine(times, { path: ['endTime'], message: 'End must be after start' })
export type WeeklySlot = z.infer<typeof WeeklySlot>
const SessionRef = { sessionId: z.uuid(), expectedVersion: RowVersion }
const SessionFields = { date: IsoDate, startTime: Time, endTime: Time, roomId: z.uuid().nullable() }
export const ScheduleChange = z.discriminatedUnion('op', [
  z.strictObject({
    op: z.literal('reopen'),
    expectedVersion: RowVersion,
    weekly: z
      .strictObject({ appliesOn: IsoDate, slots: z.array(WeeklySlot) })
      .nullable()
      .default(null),
    adjustments: z.array(z.strictObject({ sessionId: z.uuid(), ...SessionFields }).refine(times)),
  }),
  z.strictObject({ op: z.literal('weekly'), appliesOn: IsoDate, slots: z.array(WeeklySlot) }),
  z.strictObject({ op: z.literal('makeup'), ...SessionFields }).refine(times),
  z.strictObject({ op: z.literal('move'), ...SessionRef, ...SessionFields }).refine(times),
  z.strictObject({ op: z.literal('off'), ...SessionRef }),
  z.strictObject({ op: z.literal('resume'), ...SessionRef }),
  z.strictObject({
    op: z.literal('holiday'),
    date: IsoDate,
    name: z.string().trim().min(1).max(200),
  }),
  z.strictObject({ op: z.literal('remove_holiday'), date: IsoDate }),
])
export type ScheduleChange = z.infer<typeof ScheduleChange>
export const ConfirmScheduleChange = z.strictObject({
  change: ScheduleChange,
  token: z.string().regex(/^[a-f0-9]{32}$/),
})
export const ClassSession = z.object({
  id: z.uuid(),
  classId: z.uuid(),
  className: z.string(),
  kind: z.enum(['weekly', 'makeup']),
  date: IsoDate,
  startTime: Time,
  endTime: Time,
  startsAt: z.string(),
  endsAt: z.string(),
  roomId: z.uuid().nullable(),
  roomName: z.string().nullable(),
  siteName: z.string().nullable(),
  siteAddress: z.string().nullable(),
  status: z.enum(['scheduled', 'off', 'holiday', 'removed_schedule', 'removed_class']),
  isException: z.boolean(),
  rowVersion: RowVersion,
  attendanceVersion: z.number().int().min(0),
})
export type ClassSession = z.infer<typeof ClassSession>
export const StaffConflict = z.object({
  accountId: z.uuid(),
  fullName: z.string(),
  className: z.string(),
  sessionId: z.uuid(),
  startsAt: z.string(),
  endsAt: z.string(),
})
export const SchedulePreview = z.object({
  token: z.string(),
  sessions: z.array(ClassSession),
  warnings: z.array(StaffConflict),
})
export type SchedulePreview = z.infer<typeof SchedulePreview>
export const ClassSchedule = z.object({
  sessions: z.array(ClassSession),
  weekly: z.array(
    z.object({
      id: z.uuid(),
      appliesOn: IsoDate,
      slots: z.array(WeeklySlot),
      revision: RowVersion,
    }),
  ),
  holidays: z.array(z.object({ date: IsoDate, name: z.string() })),
  warnings: z.array(StaffConflict),
})
export type ClassSchedule = z.infer<typeof ClassSchedule>
