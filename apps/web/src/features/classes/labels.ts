import type { AssignmentStatus, ClassSummary } from '@mledu/contracts/classes'

/** Badge colours shared by the class pages (Metis status palette). */
export const periodBadge: Record<ClassSummary['period'], string> = {
  upcoming: 'bg-info',
  running: 'bg-success',
  ended: 'bg-secondary',
}

export const assignmentBadge: Record<AssignmentStatus, string> = {
  not_started: 'bg-info',
  active: 'bg-success',
  expired: 'bg-secondary',
  ended: 'bg-warning',
  cancelled: 'bg-secondary',
}
