import { env } from 'cloudflare:workers'
import { beforeAll, describe, expect, it } from 'vitest'
import { api, createReadyAccount, errorCode, json, signIn } from './support'

// Real Worker + Supabase Storage (private `avatars` bucket) + PostgreSQL.

const fromBase64 = (value: string) => Uint8Array.from(atob(value), (char) => char.charCodeAt(0))
const PNG_1X1 = fromBase64(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
)
const WEBP_1X1 = fromBase64('UklGRhoAAABXRUJQVlA4TA0AAAAvAAAAEAcQERGIiP4HAA==')

let admin: string
beforeAll(async () => {
  admin = await signIn('admin')
})

interface Profile {
  avatarPath: string | null
  rowVersion: number
}

async function reserve(token: string, contentType: string, size: number) {
  const response = await api('/v1/me/avatar/uploads', {
    token,
    method: 'POST',
    body: { contentType, size },
  })
  return response
}

/** Reserves a path and uploads `bytes` to it with the signed URL, as the SPA does. */
async function upload(token: string, contentType: string, bytes: Uint8Array) {
  const reserved = await reserve(token, contentType, bytes.length)
  expect(reserved.status).toBe(201)
  const { path, uploadUrl } = await json<{ path: string; uploadUrl: string }>(reserved)
  const put = await fetch(uploadUrl, {
    method: 'PUT',
    headers: { 'Content-Type': contentType },
    body: bytes,
  })
  return { path, uploaded: put.ok }
}

const commit = (token: string, path: string, expectedVersion: number) =>
  api('/v1/me/avatar', { token, method: 'POST', body: { path, expectedVersion } })

/** Whether the file still exists in Storage (service role, test-only check). */
async function fileExists(path: string) {
  const response = await fetch(`${env.SUPABASE_URL}/storage/v1/object/avatars/${path}`, {
    headers: {
      apikey: env.SUPABASE_SECRET_KEY!,
      Authorization: `Bearer ${env.SUPABASE_SECRET_KEY}`,
    },
  })
  await response.body?.cancel()
  return response.ok
}

const profile = async (token: string) => json<Profile>(await api('/v1/me', { token }))

describe('avatar (AUTH-08, techstack §4.5)', () => {
  it('stores a checked image, serves it through the API and removes the replaced file', async () => {
    const account = await createReadyAccount(admin, 'avatar')
    const token = account.session.accessToken

    const first = await upload(token, 'image/png', PNG_1X1)
    expect(first.uploaded).toBe(true)
    expect(first.path.startsWith(`${account.id}/`)).toBe(true)
    const committed = await commit(token, first.path, account.rowVersion)
    expect(committed.status).toBe(200)
    const after = await json<Profile>(committed)
    expect(after.avatarPath).toBe(first.path)

    const served = await api('/v1/me/avatar', { token })
    expect(served.status).toBe(200)
    expect(served.headers.get('Content-Type')).toBe('image/png')
    expect(new Uint8Array(await served.arrayBuffer())).toEqual(PNG_1X1)

    const second = await upload(token, 'image/webp', WEBP_1X1)
    const replaced = await commit(token, second.path, after.rowVersion)
    expect(replaced.status).toBe(200)
    expect(await fileExists(first.path)).toBe(false)
    expect(await fileExists(second.path)).toBe(true)

    const cleared = await api('/v1/me/avatar', {
      token,
      method: 'DELETE',
      body: { expectedVersion: (await json<Profile>(replaced)).rowVersion },
    })
    expect((await json<Profile>(cleared)).avatarPath).toBeNull()
    expect(await fileExists(second.path)).toBe(false)
  })

  it('rejects a file whose bytes are not the declared image type, keeping the old avatar', async () => {
    const account = await createReadyAccount(admin, 'fake')
    const token = account.session.accessToken
    const good = await upload(token, 'image/png', PNG_1X1)
    const current = await json<Profile>(await commit(token, good.path, account.rowVersion))

    const text = new TextEncoder().encode('<script>alert(1)</script>'.repeat(4))
    const fake = await upload(token, 'image/png', text)
    expect(fake.uploaded).toBe(true)
    const response = await commit(token, fake.path, current.rowVersion)
    expect(response.status).toBe(400)
    expect(await errorCode(response)).toBe('avatar_invalid')
    expect(await profile(token)).toMatchObject({ avatarPath: good.path })
    expect(await fileExists(fake.path)).toBe(false)

    // A real WebP declared as PNG is rejected too: the extension must match.
    const mismatch = await upload(token, 'image/png', WEBP_1X1)
    expect((await commit(token, mismatch.path, current.rowVersion)).status).toBe(400)
  })

  it('refuses files above 5,000,000 bytes', async () => {
    const account = await createReadyAccount(admin, 'big')
    const token = account.session.accessToken
    const declared = await reserve(token, 'image/png', 5_000_001)
    expect(declared.status).toBe(400)

    // Declared small, actually too large: Storage refuses the bucket limit.
    const big = new Uint8Array(5_000_001)
    big.set(PNG_1X1)
    const reserved = await json<{ path: string; uploadUrl: string }>(
      await reserve(token, 'image/png', 1_000),
    )
    const put = await fetch(reserved.uploadUrl, {
      method: 'PUT',
      headers: { 'Content-Type': 'image/png' },
      body: big,
    })
    expect(put.ok).toBe(false)
    expect((await commit(token, reserved.path, account.rowVersion)).status).toBe(400)
  })

  it('lets nobody else commit, and blocks committing without the Worker check', async () => {
    const owner = await createReadyAccount(admin, 'owner')
    const other = await createReadyAccount(admin, 'other')
    const file = await upload(owner.session.accessToken, 'image/png', PNG_1X1)

    const stolen = await commit(other.session.accessToken, file.path, other.rowVersion)
    expect(stolen.status).toBe(400)

    // Direct Data API call with the owner's own JWT skips the content check.
    const direct = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/set_my_avatar`, {
      method: 'POST',
      headers: {
        apikey: env.SUPABASE_PUBLISHABLE_KEY,
        Authorization: `Bearer ${owner.session.accessToken}`,
        'Content-Type': 'application/json',
        'Content-Profile': 'api',
      },
      body: JSON.stringify({ p_path: file.path, p_expected_version: owner.rowVersion }),
    })
    expect(direct.ok).toBe(false)
    expect(await profile(owner.session.accessToken)).toMatchObject({ avatarPath: null })

    // Storage itself is closed to client JWTs.
    const read = await fetch(`${env.SUPABASE_URL}/storage/v1/object/avatars/${file.path}`, {
      headers: {
        apikey: env.SUPABASE_PUBLISHABLE_KEY,
        Authorization: `Bearer ${owner.session.accessToken}`,
      },
    })
    expect(read.ok).toBe(false)
    const write = await fetch(
      `${env.SUPABASE_URL}/storage/v1/object/avatars/${owner.id}/direct.png`,
      {
        method: 'POST',
        headers: {
          apikey: env.SUPABASE_PUBLISHABLE_KEY,
          Authorization: `Bearer ${owner.session.accessToken}`,
          'Content-Type': 'image/png',
        },
        body: PNG_1X1,
      },
    )
    expect(write.ok).toBe(false)
  })

  it('keeps exactly one of two concurrent changes and deletes the loser file only', async () => {
    const account = await createReadyAccount(admin, 'race')
    const token = account.session.accessToken
    const a = await upload(token, 'image/png', PNG_1X1)
    const b = await upload(token, 'image/webp', WEBP_1X1)

    const [ra, rb] = await Promise.all([
      commit(token, a.path, account.rowVersion),
      commit(token, b.path, account.rowVersion),
    ])
    const statuses = [ra.status, rb.status].sort()
    expect(statuses).toEqual([200, 409])

    const winner = ra.status === 200 ? a.path : b.path
    const loser = winner === a.path ? b.path : a.path
    expect(await profile(token)).toMatchObject({ avatarPath: winner })
    expect(await fileExists(winner)).toBe(true)
    expect(await fileExists(loser)).toBe(false)
  })
})
