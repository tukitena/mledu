import {
  ChangeTestConfigRequest,
  ClassTest,
  ClassTestDetail,
  ClassTestList,
  CreateTestRequest,
  CreateTestTemplateRequest,
  SaveTestResultsRequest,
  SetShowComponentsRequest,
  TestResults,
  UpdateTestRequest,
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

/**
 * Tests of a class (TEST-05). Every RPC re-checks the current account, the
 * class and the caller's assignment (Admin, teacher or assistant; display
 * option Admin or teacher). Receptionists have no academic access.
 */
export const classTestRoutes = new Hono<AppEnv>()
  .use(requireSession())

  .get('/:classId/tests', async (c) =>
    c.json(
      rpcResult(
        ClassTestList,
        await c.get('db').rpc('list_class_tests', { p_class_id: uuidParam(c, 'classId') }),
      ),
    ),
  )

  // Templates that may be copied into a test of this class (not archived).
  .get('/:classId/test-templates', async (c) =>
    c.json(
      rpcResult(
        z.array(TestTemplate),
        await c
          .get('db')
          .rpc('list_test_template_choices', { p_class_id: uuidParam(c, 'classId') }),
      ),
    ),
  )

  .post('/:classId/tests', async (c) => {
    const body = await parseJson(c, CreateTestRequest)
    const test = rpcResult(
      ClassTest,
      await c.get('db').rpc('create_test', {
        p_class_id: uuidParam(c, 'classId'),
        p_name: body.name,
        p_test_on: body.testOn,
        p_description: nullable(body.description),
        p_config: body.config,
        p_source_template_version_id: nullable(body.sourceTemplateVersionId),
      }),
    )
    return c.json(test, 201)
  })

export const testRoutes = new Hono<AppEnv>()
  .use(requireSession())

  .get('/:id', async (c) =>
    c.json(
      rpcResult(ClassTestDetail, await c.get('db').rpc('get_test', { p_id: uuidParam(c, 'id') })),
    ),
  )

  .put('/:id', async (c) => {
    const body = await parseJson(c, UpdateTestRequest)
    return c.json(
      rpcResult(
        ClassTest,
        await c.get('db').rpc('update_test', {
          p_id: uuidParam(c, 'id'),
          p_name: body.name,
          p_test_on: body.testOn,
          p_description: nullable(body.description),
          p_expected_version: body.expectedVersion,
        }),
      ),
    )
  })

  .put('/:id/config', async (c) => {
    const body = await parseJson(c, ChangeTestConfigRequest)
    return c.json(
      rpcResult(
        ClassTest,
        await c.get('db').rpc('change_test_config', {
          p_id: uuidParam(c, 'id'),
          p_config: body.config,
          p_source_template_version_id: nullable(body.sourceTemplateVersionId),
          p_expected_version: body.expectedVersion,
        }),
      ),
    )
  })

  .put('/:id/show-components', async (c) => {
    const body = await parseJson(c, SetShowComponentsRequest)
    return c.json(
      rpcResult(
        ClassTest,
        await c.get('db').rpc('set_test_show_components', {
          p_id: uuidParam(c, 'id'),
          p_show: body.showComponents,
          p_expected_version: body.expectedVersion,
        }),
      ),
    )
  })

  // Entry grid of one test (TEST-01/04/05).
  .get('/:id/results', async (c) =>
    c.json(
      rpcResult(
        TestResults,
        await c.get('db').rpc('get_test_results', { p_test_id: uuidParam(c, 'id') }),
      ),
    ),
  )

  // Changed rows only; one transaction and one audit for the whole save.
  .put('/:id/results', async (c) => {
    const body = await parseJson(c, SaveTestResultsRequest)
    return c.json(
      rpcResult(
        TestResults,
        await c.get('db').rpc('save_test_results', {
          p_test_id: uuidParam(c, 'id'),
          p_config_id: body.configId,
          p_items: body.items,
        }),
      ),
    )
  })
