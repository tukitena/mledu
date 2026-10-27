import { z } from 'zod'
import { RowVersion } from './common'

/**
 * Shared catalogs: subjects/grades (CAT-01, Admin writes), sites and rooms
 * (SCHED-02/03/05, Admin and Receptionist write). Archiving keeps the record
 * and its identifier; a name matching an archived record is restored instead.
 */
export const CatalogKind = z.enum(['subject', 'grade'])
export type CatalogKind = z.infer<typeof CatalogKind>

/** URL segment of each catalog kind: /v1/catalogs/subjects, /v1/catalogs/grades. */
export const CATALOG_PATHS = { subject: 'subjects', grade: 'grades' } as const satisfies Record<
  CatalogKind,
  string
>

const Archivable = {
  archived: z.boolean(),
  deletedAt: z.string().nullable(),
  deletedReason: z.string().nullable(),
  rowVersion: RowVersion,
}

export const CatalogEntry = z.object({
  id: z.uuid(),
  kind: CatalogKind,
  name: z.string(),
  ...Archivable,
})
export type CatalogEntry = z.infer<typeof CatalogEntry>

export const Site = z.object({
  id: z.uuid(),
  name: z.string(),
  address: z.string(),
  activeRoomCount: z.number().int().min(0),
  ...Archivable,
})
export type Site = z.infer<typeof Site>

export const Room = z.object({
  id: z.uuid(),
  siteId: z.uuid(),
  siteName: z.string(),
  siteArchived: z.boolean(),
  name: z.string(),
  ...Archivable,
})
export type Room = z.infer<typeof Room>

/** `?includeArchived=true` lists archived records too (management pages only). */
export const ListCatalogQuery = z.object({
  includeArchived: z
    .enum(['true', 'false'])
    .optional()
    .transform((value) => value === 'true'),
})
export const ListRoomsQuery = ListCatalogQuery.extend({ siteId: z.uuid().optional() })

/** Subject/grade names: 1–100 characters after trimming (CAT-01). */
export const CatalogName = z.string().trim().min(1).max(100)
/** Site and room names: 1–200 characters; site address 1–500 (SCHED-05). */
export const PlaceName = z.string().trim().min(1).max(200)
export const SiteAddress = z.string().trim().min(1).max(500)
/** Reason required by every archive/soft delete (C.1.1). */
export const Reason = z.string().trim().min(1).max(1000)

export const CreateCatalogEntryRequest = z.strictObject({ name: CatalogName })
export const RenameCatalogEntryRequest = z.strictObject({
  name: CatalogName,
  expectedVersion: RowVersion,
})

export const CreateSiteRequest = z.strictObject({ name: PlaceName, address: SiteAddress })
export const UpdateSiteRequest = CreateSiteRequest.extend({ expectedVersion: RowVersion })

export const CreateRoomRequest = z.strictObject({ siteId: z.uuid(), name: PlaceName })
export const UpdateRoomRequest = CreateRoomRequest.extend({ expectedVersion: RowVersion })

export const ArchiveRequest = z.strictObject({ reason: Reason, expectedVersion: RowVersion })
export type ArchiveRequest = z.infer<typeof ArchiveRequest>
