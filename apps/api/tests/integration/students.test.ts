import { ErrorResponse } from '@mledu/contracts/common'
import { Student, StudentPage } from '@mledu/contracts/students'
import { beforeAll, describe, expect, it } from 'vitest'
import { api, errorCode, json, signIn } from './support'

// Student master records over HTTP (STU-04/01/02): duplicate rules hold under
// concurrent requests and conflicts name the other student by code.
let admin: string
let receptionist: string
let user: string
const unique = () => `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`
const digits = () => String(Math.floor(Math.random() * 1e8)).padStart(8, '0')

const fields = (fullName: string, parentPhones: string[] = []) => ({
  fullName,
  parentName: null,
  parentPhones,
  studentPhones: [],
  birthDate: null,
  school: null,
  generalNote: null,
})

beforeAll(async () => {
  ;[admin, receptionist, user] = await Promise.all([
    signIn('admin'),
    signIn('receptionist'),
    signIn('user'),
  ])
})

describe('students (STU-04)', () => {
  it('Receptionist creates; an unassigned User searches but cannot create', async () => {
    const name = `Học Sinh ${unique()}`
    const refused = await api('/v1/students', { token: user, method: 'POST', body: fields(name) })
    expect(refused.status).toBe(403)

    const created = await api('/v1/students', {
      token: receptionist,
      method: 'POST',
      body: fields(name, [`09${digits()}`]),
    })
    expect(created.status).toBe(201)
    const student = Student.parse(await json(created))
    expect(student.code).toMatch(/^HS\d{6,}$/)

    const search = await api(
      `/v1/students?search=${encodeURIComponent(name.toUpperCase().normalize('NFD').replace(/[̀-ͯ]/g, ''))}`,
      { token: user },
    )
    expect(StudentPage.parse(await json(search)).items.map((s) => s.id)).toEqual([student.id])

    const archived = await api('/v1/students?status=deleted', { token: user })
    expect(archived.status).toBe(403)
  })

  it('returns the code of the duplicate so staff can find it', async () => {
    const name = `Trùng Tên ${unique()}`
    const phone = `09${digits()}`
    const first = Student.parse(
      await json(
        await api('/v1/students', { token: admin, method: 'POST', body: fields(name, [phone]) }),
      ),
    )
    const formatted = `+84 ${phone.slice(1, 4)} ${phone.slice(4)}`
    const duplicate = await api('/v1/students', {
      token: admin,
      method: 'POST',
      body: fields(name.toLowerCase(), [formatted]),
    })
    expect(duplicate.status).toBe(409)
    const body = ErrorResponse.parse(await json(duplicate))
    expect(body.error.code).toBe('duplicate_student')
    expect(body.error.details).toEqual([{ path: 'student', message: first.code }])
  })

  it('serializes concurrent creations of the same name without parent phones', async () => {
    const name = `Đồng Thời ${unique()}`
    const responses = await Promise.all(
      [admin, receptionist, admin].map((token) =>
        api('/v1/students', { token, method: 'POST', body: fields(name) }),
      ),
    )
    expect(responses.map((r) => r.status).sort()).toEqual([201, 409, 409])
    for (const response of responses.filter((r) => r.status === 409)) {
      expect(await errorCode(response)).toBe('parent_phone_required')
    }
  })

  it('soft-deletes and restores with the same code', async () => {
    const name = `Lưu Trữ ${unique()}`
    const phone = `09${digits()}`
    const student = Student.parse(
      await json(
        await api('/v1/students', { token: admin, method: 'POST', body: fields(name, [phone]) }),
      ),
    )
    const deleted = Student.parse(
      await json(
        await api(`/v1/students/${student.id}/delete`, {
          token: receptionist,
          method: 'POST',
          body: { reason: 'Nghỉ học', expectedVersion: student.rowVersion },
        }),
      ),
    )
    expect(deleted.status).toBe('deleted')

    const again = await api('/v1/students', {
      token: admin,
      method: 'POST',
      body: fields(name, [phone]),
    })
    expect(await errorCode(again)).toBe('duplicate_student_archived')

    const restored = await api(`/v1/students/${student.id}/restore`, {
      token: receptionist,
      method: 'POST',
      body: { ...fields(name, [phone]), expectedVersion: deleted.rowVersion },
    })
    expect(restored.status).toBe(200)
    expect(Student.parse(await json(restored))).toMatchObject({
      code: student.code,
      status: 'active',
    })
  })
})
