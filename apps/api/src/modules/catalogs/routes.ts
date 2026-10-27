import {
  ArchiveRequest,
  CATALOG_PATHS,
  CatalogEntry,
  CreateCatalogEntryRequest,
  CreateRoomRequest,
  CreateSiteRequest,
  ListCatalogQuery,
  ListRoomsQuery,
  RenameCatalogEntryRequest,
  Room,
  Site,
  UpdateRoomRequest,
  UpdateSiteRequest,
  type CatalogKind,
} from '@mledu/contracts/catalogs'
import { VersionedRequest } from '@mledu/contracts/accounts'
import { Hono, type Context } from 'hono'
import { z } from 'zod'
import type { AppEnv } from '../../env'
import { AppError } from '../../lib/errors'
import { rpcResult } from '../../lib/rpc'
import { nullable } from '../../lib/supabase'
import { parseJson, parseQuery, uuidParam } from '../../lib/validation'
import { requireSession } from '../../middleware/session'

/**
 * Shared catalogs (CAT-01, SCHED-02/03/05). Every RPC re-checks the caller:
 * subjects/grades are written by Admin only, sites/rooms by Admin and
 * Receptionist; every internal account reads active records.
 */
const KINDS = Object.fromEntries(
  Object.entries(CATALOG_PATHS).map(([kind, path]) => [path, kind as CatalogKind]),
) as Record<string, CatalogKind>

function catalogKind(c: Context<AppEnv>): CatalogKind {
  const kind = KINDS[c.req.param('kind') ?? '']
  if (!kind) throw new AppError(404, 'not_found', 'not_found')
  return kind
}

export const catalogRoutes = new Hono<AppEnv>()
  .use(requireSession())

  .get('/:kind', async (c) => {
    const { includeArchived } = parseQuery(c, ListCatalogQuery)
    return c.json(
      rpcResult(
        z.array(CatalogEntry),
        await c.get('db').rpc('list_catalog_entries', {
          p_kind: catalogKind(c),
          p_include_archived: includeArchived,
        }),
      ),
    )
  })

  .post('/:kind', async (c) => {
    const kind = catalogKind(c)
    const { name } = await parseJson(c, CreateCatalogEntryRequest)
    const entry = rpcResult(
      CatalogEntry,
      await c.get('db').rpc('create_catalog_entry', { p_kind: kind, p_name: name }),
    )
    return c.json(entry, 201)
  })

  .patch('/:kind/:id', async (c) => {
    catalogKind(c)
    const body = await parseJson(c, RenameCatalogEntryRequest)
    return c.json(
      rpcResult(
        CatalogEntry,
        await c.get('db').rpc('rename_catalog_entry', {
          p_id: uuidParam(c, 'id'),
          p_name: body.name,
          p_expected_version: body.expectedVersion,
        }),
      ),
    )
  })

  .post('/:kind/:id/archive', async (c) => {
    catalogKind(c)
    const body = await parseJson(c, ArchiveRequest)
    return c.json(
      rpcResult(
        CatalogEntry,
        await c.get('db').rpc('archive_catalog_entry', {
          p_id: uuidParam(c, 'id'),
          p_reason: body.reason,
          p_expected_version: body.expectedVersion,
        }),
      ),
    )
  })

  .post('/:kind/:id/restore', async (c) => {
    catalogKind(c)
    const { expectedVersion } = await parseJson(c, VersionedRequest)
    return c.json(
      rpcResult(
        CatalogEntry,
        await c.get('db').rpc('restore_catalog_entry', {
          p_id: uuidParam(c, 'id'),
          p_expected_version: expectedVersion,
        }),
      ),
    )
  })

export const siteRoutes = new Hono<AppEnv>()
  .use(requireSession())

  .get('/', async (c) => {
    const { includeArchived } = parseQuery(c, ListCatalogQuery)
    return c.json(
      rpcResult(
        z.array(Site),
        await c.get('db').rpc('list_sites', { p_include_archived: includeArchived }),
      ),
    )
  })

  .post('/', async (c) => {
    const body = await parseJson(c, CreateSiteRequest)
    const site = rpcResult(
      Site,
      await c.get('db').rpc('create_site', { p_name: body.name, p_address: body.address }),
    )
    return c.json(site, 201)
  })

  .patch('/:id', async (c) => {
    const body = await parseJson(c, UpdateSiteRequest)
    return c.json(
      rpcResult(
        Site,
        await c.get('db').rpc('update_site', {
          p_id: uuidParam(c, 'id'),
          p_name: body.name,
          p_address: body.address,
          p_expected_version: body.expectedVersion,
        }),
      ),
    )
  })

  // SCHED-05: also archives every room of the site in the same command.
  .post('/:id/archive', async (c) => {
    const body = await parseJson(c, ArchiveRequest)
    return c.json(
      rpcResult(
        Site,
        await c.get('db').rpc('archive_site', {
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
        Site,
        await c.get('db').rpc('restore_site', {
          p_id: uuidParam(c, 'id'),
          p_expected_version: expectedVersion,
        }),
      ),
    )
  })

export const roomRoutes = new Hono<AppEnv>()
  .use(requireSession())

  .get('/', async (c) => {
    const query = parseQuery(c, ListRoomsQuery)
    return c.json(
      rpcResult(
        z.array(Room),
        await c.get('db').rpc('list_rooms', {
          p_site_id: nullable(query.siteId),
          p_include_archived: query.includeArchived,
        }),
      ),
    )
  })

  .post('/', async (c) => {
    const body = await parseJson(c, CreateRoomRequest)
    const room = rpcResult(
      Room,
      await c.get('db').rpc('create_room', { p_site_id: body.siteId, p_name: body.name }),
    )
    return c.json(room, 201)
  })

  .patch('/:id', async (c) => {
    const body = await parseJson(c, UpdateRoomRequest)
    return c.json(
      rpcResult(
        Room,
        await c.get('db').rpc('update_room', {
          p_id: uuidParam(c, 'id'),
          p_site_id: body.siteId,
          p_name: body.name,
          p_expected_version: body.expectedVersion,
        }),
      ),
    )
  })

  .post('/:id/archive', async (c) => {
    const body = await parseJson(c, ArchiveRequest)
    return c.json(
      rpcResult(
        Room,
        await c.get('db').rpc('archive_room', {
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
        Room,
        await c.get('db').rpc('restore_room', {
          p_id: uuidParam(c, 'id'),
          p_expected_version: expectedVersion,
        }),
      ),
    )
  })
