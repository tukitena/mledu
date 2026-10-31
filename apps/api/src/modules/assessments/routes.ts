import {
  CreateTestTemplateRequest,
  TestTemplate,
  TestTemplateVersion,
  UpdateTestTemplateRequest,
} from '@mledu/contracts/assessments'
import { VersionedRequest } from '@mledu/contracts/accounts'
import { ArchiveRequest, ListCatalogQuery } from '@mledu/contracts/catalogs'
import { Hono } from 'hono'
import { z } from 'zod'
import type { AppEnv } from '../../env'
import { rpcResult } from '../../lib/rpc'
import { nullable } from '../../lib/supabase'
import { parseJson, parseQuery, uuidParam } from '../../lib/validation'
import { requireSession } from '../../middleware/session'

/**
 * Shared test template library (TEST-02). Every RPC re-checks that the caller
 * is a current Admin; edits add an immutable version in the same transaction
 * as their history and audit.
 */
export const testTemplateRoutes = new Hono<AppEnv>()
  .use(requireSession())

  .get('/', async (c) => {
    const { includeArchived } = parseQuery(c, ListCatalogQuery)
    return c.json(
      rpcResult(
        z.array(TestTemplate),
        await c.get('db').rpc('list_test_templates', { p_include_archived: includeArchived }),
      ),
    )
  })

  .get('/:id/versions', async (c) =>
    c.json(
      rpcResult(
        z.array(TestTemplateVersion),
        await c.get('db').rpc('list_test_template_versions', { p_id: uuidParam(c, 'id') }),
      ),
    ),
  )

  .post('/', async (c) => {
    const body = await parseJson(c, CreateTestTemplateRequest)
    const template = rpcResult(
      TestTemplate,
      await c.get('db').rpc('create_test_template', {
        p_name: body.name,
        p_description: nullable(body.description),
        p_config: body.config,
      }),
    )
    return c.json(template, 201)
  })

  .put('/:id', async (c) => {
    const body = await parseJson(c, UpdateTestTemplateRequest)
    return c.json(
      rpcResult(
        TestTemplate,
        await c.get('db').rpc('update_test_template', {
          p_id: uuidParam(c, 'id'),
          p_name: body.name,
          p_description: nullable(body.description),
          p_config: body.config,
          p_expected_version: body.expectedVersion,
        }),
      ),
    )
  })

  .post('/:id/archive', async (c) => {
    const body = await parseJson(c, ArchiveRequest)
    return c.json(
      rpcResult(
        TestTemplate,
        await c.get('db').rpc('archive_test_template', {
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
        TestTemplate,
        await c.get('db').rpc('restore_test_template', {
          p_id: uuidParam(c, 'id'),
          p_expected_version: expectedVersion,
        }),
      ),
    )
  })
