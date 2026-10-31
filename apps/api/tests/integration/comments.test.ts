import { ClassTest } from '@mledu/contracts/assessments'
import {
  CommentBatch,
  CommentBatchList,
  Comments,
  PublishCommentsResponse,
} from '@mledu/contracts/comments'
import { beforeAll, describe, expect, it } from 'vitest'
import { api, createReadyAccount, errorCode, json, signIn } from './support'

// Comments over HTTP (COMMENT-01-03, ACAD-01): request contract, independent
// publication, lock while published, batch archive/restore and current rights.
let admin: string
let receptionist: string
const unique = () => `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`
const day = (n: number) =>
  new Date(Date.now() + 7 * 3600_000 + n * 86_400_000).toISOString().slice(0, 10)

const post = (path: string, body: unknown, token = admin) =>
  api(path, { method: 'POST', token, body })
const put = (path: string, body: unknown, token = admin) =>
  api(path, { method: 'PUT', token, body })

async function fixture() {
  const klass = await post('/v1/classes', {
    name: `Nhận xét ${unique()}`,
    subjectId: '10000000-0000-4000-8000-000000000001',
    gradeId: '10000000-0000-4000-8000-000000000011',
    startDate: day(-10),
    endDate: day(30),
    note: null,
  })
  expect(klass.status).toBe(201)
  const classId = (await json<{ id: string }>(klass)).id
  const students: string[] = []
  for (const name of ['An', 'Bình']) {
    const created = await post('/v1/students', {
      fullName: `${name} ${unique()}`,
      parentName: null,
      parentPhones: [],
      studentPhones: [],
      birthDate: null,
      school: null,
      generalNote: null,
    })
    const id = (await json<{ id: string }>(created)).id
    expect(
      (
        await post(`/v1/classes/${classId}/students`, {
          studentId: id,
          joinDate: day(-5),
          leaveDate: null,
          note: null,
        })
      ).status,
    ).toBe(201)
    students.push(id)
  }
  return { classId, students: students as [string, string] }
}

beforeAll(async () => {
  ;[admin, receptionist] = await Promise.all([signIn('admin'), signIn('receptionist')])
})

describe('comments (COMMENT-01-03, ACAD-01)', () => {
  it('saves plain text on a test and publishes it apart from the score', async () => {
    const { classId, students } = await fixture()
    const [an, binh] = students
    const created = await post(`/v1/classes/${classId}/tests`, {
      name: 'Giữa kỳ',
      testOn: day(0),
      description: null,
      config: { scaleKind: 'numeric', inputMode: 'direct', maxScore: 10 },
      sourceTemplateVersionId: null,
    })
    const test = ClassTest.parse(await json(created))
    const path = `/v1/comments/test/${test.id}`

    const tooLong = await put(path, {
      items: [{ studentId: an, expectedVersion: null, body: 'a'.repeat(1001) }],
    })
    expect(tooLong.status).toBe(400)
    const saved = Comments.parse(
      await json(
        await put(path, {
          items: [{ studentId: an, expectedVersion: null, body: 'é'.repeat(1000) }],
        }),
      ),
    )
    const comment = saved.students.find((row) => row.studentId === an)!.comment!
    expect(comment.body).toHaveLength(1000)

    const published = PublishCommentsResponse.parse(
      await json(await post(`${path}/publication`, { studentId: null, publish: true })),
    )
    expect(published.changed).toBe(1)
    expect(published.missing.map((row) => row.studentId)).toEqual([binh])

    const results = await json<{ students: { studentId: string; result: unknown }[] }>(
      await api(`/v1/tests/${test.id}/results`, { token: admin }),
    )
    expect(results.students.every((row) => row.result === null)).toBe(true)

    const locked = await put(path, {
      items: [{ studentId: an, expectedVersion: comment.rowVersion + 1, body: 'Sửa' }],
    })
    expect(locked.status).toBe(409)
    expect(await errorCode(locked)).toBe('comment_published')
    const listed = ClassTest.parse(
      (
        await json<{ items: unknown[] }>(
          await api(`/v1/classes/${classId}/tests`, { token: admin }),
        )
      ).items[0],
    )
    expect(listed.commentCount).toBe(1)
  })

  it('archives a batch with its comments unpublished and restores it', async () => {
    const { classId, students } = await fixture()
    const [an] = students
    const batch = CommentBatch.parse(
      await json(await post(`/v1/classes/${classId}/comment-batches`, { name: 'Tháng 10' })),
    )
    const path = `/v1/comments/batch/${batch.id}`
    expect(
      (await put(path, { items: [{ studentId: an, expectedVersion: null, body: 'Tốt' }] })).status,
    ).toBe(200)
    expect((await post(`${path}/publication`, { studentId: an, publish: true })).status).toBe(200)

    const archived = CommentBatch.parse(
      await json(
        await post(`/v1/comment-batches/${batch.id}/archive`, {
          reason: 'Tạo nhầm',
          expectedVersion: batch.rowVersion,
        }),
      ),
    )
    expect(archived).toMatchObject({ deleted: true, publishedCount: 0, commentCount: 1 })
    const list = CommentBatchList.parse(
      await json(await api(`/v1/classes/${classId}/comment-batches`, { token: admin })),
    )
    expect(list.items).toHaveLength(0)

    const restored = CommentBatch.parse(
      await json(
        await post(`/v1/comment-batches/${batch.id}/restore`, {
          expectedVersion: archived.rowVersion,
        }),
      ),
    )
    expect(restored).toMatchObject({ deleted: false, publishedCount: 0, commentCount: 1 })
    expect((await api(`/v1/comments/nope/${batch.id}`, { token: admin })).status).toBe(404)
  })

  it('follows the current academic role', async () => {
    const { classId, students } = await fixture()
    expect(
      (await post(`/v1/classes/${classId}/comment-batches`, { name: 'Lễ tân' }, receptionist))
        .status,
    ).toBe(403)
    const batch = CommentBatch.parse(
      await json(await post(`/v1/classes/${classId}/comment-batches`, { name: 'Tuần 1' })),
    )
    const account = await createReadyAccount(admin, 'comments-assistant')
    const token = account.session.accessToken
    const path = `/v1/comments/batch/${batch.id}`
    const body = { items: [{ studentId: students[0], expectedVersion: null, body: 'Ổn' }] }
    expect((await put(path, body, token)).status).toBe(404)
    expect(
      (
        await post(`/v1/classes/${classId}/assignments`, {
          accountId: account.id,
          role: 'assistant',
          startDate: day(-1),
          endDate: day(20),
          subjectNote: null,
        })
      ).status,
    ).toBe(201)
    expect((await put(path, body, token)).status).toBe(200)
    expect(
      (await post(`${path}/publication`, { studentId: null, publish: true }, token)).status,
    ).toBe(403)
    expect(
      (
        await post(
          `/v1/comment-batches/${batch.id}/archive`,
          { reason: 'Không', expectedVersion: batch.rowVersion },
          token,
        )
      ).status,
    ).toBe(403)
  })

  it('archives a test with scores and comments unpublished, then restores it (TEST-06)', async () => {
    const { classId, students } = await fixture()
    const [an] = students
    const test = ClassTest.parse(
      await json(
        await post(`/v1/classes/${classId}/tests`, {
          name: 'Cuối kỳ',
          testOn: day(0),
          description: null,
          config: { scaleKind: 'numeric', inputMode: 'direct', maxScore: 10 },
          sourceTemplateVersionId: null,
        }),
      ),
    )
    expect(
      (
        await put(`/v1/tests/${test.id}/results`, {
          configId: test.configId,
          items: [{ studentId: an, expectedVersion: null, entry: { absent: false, score: 9 } }],
        })
      ).status,
    ).toBe(200)
    expect(
      (await post(`/v1/tests/${test.id}/results/publication`, { studentId: an, publish: true }))
        .status,
    ).toBe(200)
    const current = ClassTest.parse(await json(await api(`/v1/tests/${test.id}`, { token: admin })))
    expect(current.publishedCount).toBe(1)

    expect(
      (await post(`/v1/tests/${test.id}/archive`, { reason: 'x', expectedVersion: 0 })).status,
    ).toBe(400)
    const archived = ClassTest.parse(
      await json(
        await post(`/v1/tests/${test.id}/archive`, {
          reason: 'Nhập nhầm',
          expectedVersion: current.rowVersion,
        }),
      ),
    )
    expect(archived).toMatchObject({ deleted: true, publishedCount: 0, resultCount: 1 })
    const listed = await json<{ items: { id: string }[] }>(
      await api(`/v1/classes/${classId}/tests?includeArchived=true`, { token: admin }),
    )
    expect(listed.items.map((item) => item.id)).toContain(test.id)

    const restored = ClassTest.parse(
      await json(
        await post(`/v1/tests/${test.id}/restore`, { expectedVersion: archived.rowVersion }),
      ),
    )
    expect(restored).toMatchObject({ deleted: false, publishedCount: 0, resultCount: 1 })
    expect(
      (await post(`/v1/tests/${test.id}/restore`, { expectedVersion: restored.rowVersion })).status,
    ).toBe(409)
  })
})
