import { expect, it } from 'vitest'
import { ScheduleChange, ConfirmScheduleChange } from './scheduling'

const slot = { weekday: 1, startTime: '09:00', endTime: '10:00', roomId: null }
it('validates typed weekly slots and dates without accepting privileged fields', () => {
  const value = { op: 'weekly', appliesOn: '2026-11-01', slots: [slot] }
  expect(ScheduleChange.safeParse(value).success).toBe(true)
  for (const bad of [
    { ...value, appliesOn: '2026-02-30' },
    { ...value, slots: [{ ...slot, weekday: 8 }] },
    { ...value, slots: [{ ...slot, endTime: '08:00' }] },
    { ...value, slots: [{ ...slot, startTime: '24:00' }] },
    { ...value, actorId: '00000000-0000-4000-8000-000000000001' },
  ])
    expect(ScheduleChange.safeParse(bad).success).toBe(false)
})
it('requires the reviewed fingerprint and a version for editing a session', () => {
  expect(
    ScheduleChange.safeParse({ op: 'off', sessionId: '00000000-0000-4000-8000-000000000001' })
      .success,
  ).toBe(false)
  expect(
    ConfirmScheduleChange.safeParse({ change: { op: 'holiday', date: '2026-11-01', name: 'Lễ' } })
      .success,
  ).toBe(false)
})
