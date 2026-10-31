import { ArchiveRequest, ListCatalogQuery } from '@mledu/contracts/catalogs'
import {
  CommentBatch,
  CommentBatchList,
  Comments,
  CommentTargetKind,
  CreateCommentBatchRequest,
  PublishCommentsRequest,
  PublishCommentsResponse,
  SaveCommentsRequest,
  UpdateCommentBatchRequest,
} from '@mledu/contracts/comments'
import { VersionedRequest } from '@mledu/contracts/accounts'
import type { Context } from 'hono'
import { Hono } from 'hono'
import type { AppEnv } from '../../env'
import { AppError } from '../../lib/errors'
import { rpcResult } from '../../lib/rpc'
import { nullable } from '../../lib/supabase'
import { parseJson, parseQuery, uuidParam } from '../../lib/validation'
import { requireSession } from '../../middleware/session'

/**
 * Comment batches of a class (COMMENT-02/03). Every RPC re-checks the current
 * account and assignment: Admin, teacher or assistant write; Admin or teacher
 * archive/restore. Receptionists have no academic access.
 */
export const commentBatchClassRoutes = new Hono<AppEnv>()
  .use(requireSession())

  .get('/:classId/comment-batches', async (c) => {
    const { includeArchived } = parseQuery(c, ListCatalogQuery)
    return c.json(
      rpcResult(
        CommentBatchList,
        await c.get('db').rpc('list_comment_batches', {
          p_class_id: uuidParam(c, 'classId'),
          p_include_archived: includeArchived,
        }),
      ),
    )
  })

  .post('/:classId/comment-batches', async (c) => {
    const body = await parseJson(c, CreateCommentBatchRequest)
    const batch = rpcResult(
      CommentBatch,
      await c.get('db').rpc('create_comment_batch', {
        p_class_id: uuidParam(c, 'classId'),
        p_name: body.name,
      }),
    )
    return c.json(batch, 201)
  })

export const commentBatchRoutes = new Hono<AppEnv>()
  .use(requireSession())

  .put('/:id', async (c) => {
    const body = await parseJson(c, UpdateCommentBatchRequest)
    return c.json(
      rpcResult(
        CommentBatch,
        await c.get('db').rpc('update_comment_batch', {
          p_id: uuidParam(c, 'id'),
          p_name: body.name,
          p_expected_version: body.expectedVersion,
        }),
      ),
    )
  })

  // Unpublishes the batch's comments in the same transaction (COMMENT-03).
  .post('/:id/archive', async (c) => {
    const body = await parseJson(c, ArchiveRequest)
    return c.json(
      rpcResult(
        CommentBatch,
        await c.get('db').rpc('archive_comment_batch', {
          p_id: uuidParam(c, 'id'),
          p_reason: body.reason,
          p_expected_version: body.expectedVersion,
        }),
      ),
    )
  })

  .post('/:id/restore', async (c) => {
    const { expectedVersion } = await parseJson(c, VersionedRequest)
    return c.json(
      rpcResult(
        CommentBatch,
        await c.get('db').rpc('restore_comment_batch', {
          p_id: uuidParam(c, 'id'),
          p_expected_version: expectedVersion,
        }),
      ),
    )
  })

/** Target of a comment grid: /v1/comments/test/:id or /v1/comments/batch/:id. */
function target(c: Context<AppEnv>) {
  const kind = CommentTargetKind.safeParse(c.req.param('kind'))
  if (!kind.success) throw new AppError(404, 'not_found', 'not_found')
  return { p_kind: kind.data, p_id: uuidParam(c, 'id') }
}

/** Comments of one test or batch (COMMENT-01) and their publication (ACAD-01). */
export const commentRoutes = new Hono<AppEnv>()
  .use(requireSession())

  .get('/:kind/:id', async (c) =>
    c.json(rpcResult(Comments, await c.get('db').rpc('get_comments', target(c)))),
  )

  // Changed rows only; one transaction and one audit for the whole save.
  .put('/:kind/:id', async (c) => {
    const body = await parseJson(c, SaveCommentsRequest)
    return c.json(
      rpcResult(
        Comments,
        await c.get('db').rpc('save_comments', { ...target(c), p_items: body.items }),
      ),
    )
  })

  .post('/:kind/:id/publication', async (c) => {
    const body = await parseJson(c, PublishCommentsRequest)
    return c.json(
      rpcResult(
        PublishCommentsResponse,
        await c.get('db').rpc('publish_comments', {
          ...target(c),
          p_student_id: nullable(body.studentId),
          p_publish: body.publish,
        }),
      ),
    )
  })
