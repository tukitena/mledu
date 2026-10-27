import { z } from 'zod'

/** Prefix of every versioned API route. */
export const API_VERSION = 'v1'

/** Header that carries the request ID in both directions. */
export const REQUEST_ID_HEADER = 'X-Request-Id'

/** Account type stored on the account profile (AUTH-07). Class roles are separate. */
export const AccountType = z.enum(['admin', 'receptionist', 'user'])
export type AccountType = z.infer<typeof AccountType>

/**
 * Function sets shown by the SPA. Admin may switch between all three (A.2);
 * the choice is presentation only and never authorizes anything on the API.
 */
export type Workspace = AccountType

export const workspacesFor = (accountType: AccountType): Workspace[] =>
  accountType === 'admin' ? ['admin', 'receptionist', 'user'] : [accountType]

/** Optimistic concurrency token of a record (row_version). */
export const RowVersion = z.number().int().min(1)

/** Calendar date `YYYY-MM-DD` (business dates use Asia/Ho_Chi_Minh). */
export const IsoDate = z.iso.date()

/**
 * Stable machine-readable error codes. UI text is chosen by the client from the
 * code; `message` is a short English fallback for logs and developers.
 */
export const ErrorCode = z.enum([
  'bad_request',
  'validation_failed',
  'unauthenticated',
  'session_invalid',
  'account_disabled',
  'password_change_required',
  /** Session opened from an email link; it may only reset the password (AUTH-02). */
  'password_reset_required',
  /** Reset link expired, already used or replaced (AUTH-02). */
  'reset_link_invalid',
  /** New password equals the current one. */
  'password_unchanged',
  'forbidden',
  /** Admin accounts are managed only through the operations tool (AUTH-06). */
  'admin_account_forbidden',
  /** Email already belongs to an account, including soft-deleted ones (AUTH-04/07). */
  'email_taken',
  /** The account is not in a state that allows this operation. */
  'invalid_state',
  /** Uploaded avatar missing, not a JPG/PNG/WebP image or too large (AUTH-08). */
  'avatar_invalid',
  /** Name (lookup key) already used by an active record of the same catalog. */
  'duplicate_name',
  /** Name matches an archived record; restore that record instead (CAT-01, SCHED-05). */
  'archived_duplicate',
  /** Rooms cannot be created in, moved to or restored into an archived site (SCHED-05). */
  'site_archived',
  /**
   * Same name key and a shared parent phone as an existing student (STU-04).
   * `details` lists the other students as {path: 'student', message: code}.
   */
  'duplicate_student',
  /** As duplicate_student, but every match is archived: restore it instead (STU-04). */
  'duplicate_student_archived',
  /** Another student has the same name key; at least one parent phone is needed (STU-04). */
  'parent_phone_required',
  /** CLASS-03: after the class has activity its opening date is locked and its end date stays ≥ today. */
  'class_dates_locked',
  /** CLASS-01: assignment dates must lie within the class dates. */
  'outside_class_dates',
  /** CLASS-01: only enabled, non-deleted User/Admin accounts can be assigned. */
  'account_not_assignable',
  /** CLASS-01/02: the person already has an assignment in this class for part of that period. */
  'assignment_overlap',
  /** CLASS-01: a started assignment keeps its role and start date; its end date stays ≥ today. */
  'assignment_locked',
  /** AUTH-04/07: an assignment is in effect; `details` lists the classes ({path: 'class'}). */
  'assignment_in_effect',
  'participation_overlap',
  'participation_dates_locked',
  'participations_outside_dates',
  'student_deleted',
  'class_closed',
  'class_ended',
  'not_found',
  'method_not_allowed',
  'version_conflict',
  'conflict',
  'payload_too_large',
  'rate_limited',
  'dependency_unavailable',
  'internal_error',
])
export type ErrorCode = z.infer<typeof ErrorCode>

export const ErrorResponse = z.object({
  error: z.object({
    code: ErrorCode,
    message: z.string(),
    requestId: z.string(),
    /** Field-level problems for `validation_failed`; never contains secrets. */
    details: z.array(z.object({ path: z.string(), message: z.string() })).optional(),
  }),
})
export type ErrorResponse = z.infer<typeof ErrorResponse>

export const PageQuery = z.object({
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(20),
})
export type PageQuery = z.infer<typeof PageQuery>

export const pageOf = <T extends z.ZodType>(item: T) =>
  z.object({
    items: z.array(item),
    page: z.number().int().min(1),
    pageSize: z.number().int().min(1),
    total: z.number().int().min(0),
  })

export const HealthResponse = z.object({
  status: z.literal('ok'),
  service: z.literal('mledu-api'),
  version: z.string(),
  environment: z.enum(['local', 'test', 'staging', 'production']),
  time: z.iso.datetime({ offset: true }),
})
export type HealthResponse = z.infer<typeof HealthResponse>

export const ReadinessResponse = z.object({
  status: z.enum(['ok', 'degraded']),
  checks: z.object({ database: z.enum(['ok', 'unavailable']) }),
})
export type ReadinessResponse = z.infer<typeof ReadinessResponse>
