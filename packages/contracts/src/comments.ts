import { z } from 'zod'
import { IsoDate, RowVersion } from './common'

/**
 * Comments (COMMENT-01-03) and their publication (ACAD-01). A comment is plain
 * text for one student on a test or in a comment batch of the class. Comments
 * are published on their own, independently of scores and other tests/batches.
 */

/** Characters counted as Unicode code points after NFC, never bytes (A.3). */
export const commentLength = (value: string) => [...value.normalize('NFC')].length
export const COMMENT_MAX = 1000

/** Plain text, 1–1,000 characters after trimming; longer text is refused, never cut. */
export const CommentBody = z
  .string()
  .trim()
  .min(1)
  .refine((value) => commentLength(value) <= COMMENT_MAX, { message: 'too_long' })

export const CommentTargetKind = z.enum(['test', 'batch'])
export type CommentTargetKind = z.infer<typeof CommentTargetKind>

const BatchName = z.string().trim().min(1).max(200)

export const CreateCommentBatchRequest = z.strictObject({ name: BatchName })
export type CreateCommentBatchRequest = z.input<typeof CreateCommentBatchRequest>
export const UpdateCommentBatchRequest = z.strictObject({
  name: BatchName,
  expectedVersion: RowVersion,
})
export type UpdateCommentBatchRequest = z.input<typeof UpdateCommentBatchRequest>

export const CommentBatch = z.object({
  id: z.uuid(),
  classId: z.uuid(),
  name: z.string(),
  /** Comments with text; shown before archiving (COMMENT-03). */
  commentCount: z.number().int().min(0),
  publishedCount: z.number().int().min(0),
  deleted: z.boolean(),
  deletedAt: z.string().nullable(),
  deletedReason: z.string().nullable(),
  createdAt: z.string(),
  createdByName: z.string(),
  updatedAt: z.string(),
  rowVersion: RowVersion,
})
export type CommentBatch = z.infer<typeof CommentBatch>

export const CommentBatchList = z.object({
  items: z.array(CommentBatch),
  /** Admin or a current teacher/assistant, in a class that is not deleted. */
  canEdit: z.boolean(),
  /** Admin or a current teacher: publish, archive and restore (ACAD-01, COMMENT-03). */
  canManage: z.boolean(),
})
export type CommentBatchList = z.infer<typeof CommentBatchList>

export const Comment = z.object({
  id: z.uuid(),
  body: z.string(),
  /** When the current text was first written; the history filter of COMMENT-02. */
  commentedAt: z.string(),
  published: z.boolean(),
  publishedAt: z.string().nullable(),
  publishedByName: z.string().nullable(),
  rowVersion: RowVersion,
  updatedAt: z.string(),
  updatedByName: z.string(),
})
export type Comment = z.infer<typeof Comment>

export const CommentRow = z.object({
  studentId: z.uuid(),
  code: z.string(),
  fullName: z.string(),
  comment: Comment.nullable(),
})
export type CommentRow = z.infer<typeof CommentRow>

export const Comments = z.object({
  target: z.object({
    kind: CommentTargetKind,
    id: z.uuid(),
    name: z.string(),
    testOn: IsoDate.nullable(),
    deleted: z.boolean(),
  }),
  /** Test: students of the test day. Batch: students in the class now. Plus holders of a comment. */
  students: z.array(CommentRow),
  canEdit: z.boolean(),
  canPublish: z.boolean(),
})
export type Comments = z.infer<typeof Comments>

export const SaveCommentsRequest = z.strictObject({
  items: z
    .array(
      z.strictObject({
        studentId: z.uuid(),
        /** null when the student has no comment in use. */
        expectedVersion: RowVersion.nullable(),
        /** null clears the comment. */
        body: CommentBody.nullable(),
      }),
    )
    .min(1)
    .max(1000),
})
export type SaveCommentsRequest = z.input<typeof SaveCommentsRequest>

export const PublishCommentsRequest = z.strictObject({
  /** null = every student of the test/batch. */
  studentId: z.uuid().nullable(),
  publish: z.boolean(),
})
export type PublishCommentsRequest = z.input<typeof PublishCommentsRequest>

export const PublishCommentsResponse = Comments.extend({
  changed: z.number().int().min(0),
  /** Class publish: students without a comment, left unpublished. */
  missing: z.array(z.object({ studentId: z.uuid(), fullName: z.string() })),
})
export type PublishCommentsResponse = z.infer<typeof PublishCommentsResponse>
