import { CatalogEntry, Room, Site } from '@mledu/contracts/catalogs'
import { beforeAll, describe, expect, it } from 'vitest'
import { api, errorCode, json, signIn } from './support'

// Catalogs over HTTP (CAT-01, SCHED-02/03/05): permissions are enforced by the
// API/RPC even when the request is sent directly, not only hidden in the UI.
let admin: string
let receptionist: string
let user: string
const unique = () => `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`

beforeAll(async () => {
  ;[admin, receptionist, user] = await Promise.all([
    signIn('admin'),
    signIn('receptionist'),
    signIn('user'),
  ])
})

describe('subjects and grades (CAT-01)', () => {
  it('only Admin writes; everyone reads active entries', async () => {
    const name = `Môn ${unique()}`
    for (const token of [receptionist, user]) {
      const refused = await api('/v1/catalogs/subjects', { token, method: 'POST', body: { name } })
      expect(refused.status).toBe(403)
      expect(await errorCode(refused)).toBe('forbidden')
    }

    const created = await api('/v1/catalogs/subjects', {
      token: admin,
      method: 'POST',
      body: { name },
    })
    expect(created.status).toBe(201)
    const entry = CatalogEntry.parse(await json(created))

    const listed = await api('/v1/catalogs/subjects', { token: user })
    expect(listed.status).toBe(200)
    expect(((await json<unknown[]>(listed)) as CatalogEntry[]).map((e) => e.id)).toContain(entry.id)

    const archived = await api(`/v1/catalogs/subjects/${entry.id}/archive`, {
      token: admin,
      method: 'POST',
      body: { reason: 'Thử lưu trữ', expectedVersion: entry.rowVersion },
    })
    expect(CatalogEntry.parse(await json(archived)).archived).toBe(true)

    // An archived name is restored, not created again.
    const again = await api('/v1/catalogs/subjects', {
      token: admin,
      method: 'POST',
      body: { name: name.toUpperCase() },
    })
    expect(again.status).toBe(409)
    expect(await errorCode(again)).toBe('archived_duplicate')

    const hidden = await api('/v1/catalogs/subjects?includeArchived=true', { token: user })
    expect(hidden.status).toBe(403)
  })

  it('rejects unknown kinds and malformed bodies before the database', async () => {
    expect((await api('/v1/catalogs/teachers', { token: admin })).status).toBe(404)
    const tooLong = await api('/v1/catalogs/grades', {
      token: admin,
      method: 'POST',
      body: { name: 'x'.repeat(101) },
    })
    expect(tooLong.status).toBe(400)
    expect(await errorCode(tooLong)).toBe('validation_failed')
  })
})

describe('sites and rooms (SCHED-02/03/05)', () => {
  it('Receptionist manages a third site and its rooms without code changes', async () => {
    const created = await api('/v1/sites', {
      token: receptionist,
      method: 'POST',
      body: { name: `Tòa ${unique()}`, address: '9 Đường Thử nghiệm' },
    })
    expect(created.status).toBe(201)
    const site = Site.parse(await json(created))

    const room = await api('/v1/rooms', {
      token: receptionist,
      method: 'POST',
      body: { siteId: site.id, name: 'P101' },
    })
    expect(room.status).toBe(201)
    expect(Room.parse(await json(room)).siteName).toBe(site.name)

    const duplicate = await api('/v1/rooms', {
      token: receptionist,
      method: 'POST',
      body: { siteId: site.id, name: 'p101' },
    })
    expect(await errorCode(duplicate)).toBe('duplicate_name')

    const rooms = (
      await json<Room[]>(await api(`/v1/rooms?siteId=${site.id}`, { token: user }))
    ).map((r) => Room.parse(r))
    expect(rooms).toHaveLength(1)

    const archived = await api(`/v1/sites/${site.id}/archive`, {
      token: receptionist,
      method: 'POST',
      body: { reason: 'Ngừng sử dụng', expectedVersion: site.rowVersion },
    })
    expect(Site.parse(await json(archived)).activeRoomCount).toBe(0)
  })

  it('refuses teachers and assistants on every write', async () => {
    const site = await api('/v1/sites', {
      token: user,
      method: 'POST',
      body: { name: `Tòa ${unique()}`, address: 'Không được tạo' },
    })
    expect(site.status).toBe(403)
    const room = await api('/v1/rooms', {
      token: user,
      method: 'POST',
      body: { siteId: '11000000-0000-4000-8000-000000000001', name: `P${unique()}` },
    })
    expect(room.status).toBe(403)
  })

  it('serializes concurrent creations of the same name', async () => {
    const name = `Tòa ${unique()}`
    const responses = await Promise.all(
      [admin, receptionist, admin].map((token) =>
        api('/v1/sites', { token, method: 'POST', body: { name, address: 'Đồng thời' } }),
      ),
    )
    const statuses = responses.map((r) => r.status).sort()
    expect(statuses).toEqual([201, 409, 409])
  })
})
