import { z } from 'zod'
import { IsoDate, RowVersion } from './common'
import { nameKey } from './normalize'

/**
 * Shared test templates (TEST-02, techstack §4.6). One library for the whole
 * centre, managed by Admin only. A template holds a typed grading configuration
 * (TEST-01/04): numeric, fraction, letter or IELTS. Editing adds an immutable
 * version; tests copy a version and never follow later edits.
 *
 * These schemas mirror app_private.test_template_config; the database stays the
 * authority and returns the normalized configuration (codes, totals, IELTS order).
 */
export const ScaleKind = z.enum(['numeric', 'fraction', 'letter', 'ielts'])
export type ScaleKind = z.infer<typeof ScaleKind>

export const IeltsSkill = z.enum(['L', 'R', 'W', 'S'])
export type IeltsSkill = z.infer<typeof IeltsSkill>
export const IELTS_SKILLS = IeltsSkill.options

/** Fixed IELTS formula of TEST-01; attached by the backend, never chosen by a template. */
export const IELTS_FORMULA_VERSION = 'mledu-ielts-v1'

/** Fixed criteria of the formula (TEST-01): Writing Task 1/Task 2 and Speaking. */
export const IELTS_CRITERIA = {
  W: ['t1_ta', 't1_cc', 't1_lr', 't1_gra', 't2_tr', 't2_cc', 't2_lr', 't2_gra'],
  S: ['fc', 'lr', 'gra', 'pronunciation'],
} as const

/** roundBand(x) = floor(2x + 0.5) / 2 (TEST-01). The backend is the authority; the UI only previews. */
export const roundBand = (value: number) => Math.floor(2 * value + 0.5) / 2

/** Limits from TEST-02/04. */
export const MAX_COMPONENTS = 50
export const MAX_LETTER_LEVELS = 20

/** Default letter set offered when a letter template is created (TEST-02). */
export const DEFAULT_LETTER_LEVELS = ['Chưa đạt', 'Đạt', 'Tốt', 'Xuất sắc'] as const

/** Positive score with at most two decimals (TEST-01); never rounded. */
export const MaxScore = z
  .number()
  .positive()
  .refine((value) => /^\d+(\.\d{1,2})?$/.test(value.toString()), { message: 'too_many_decimals' })

export const QuestionCount = z.number().int().min(1).max(2_147_483_647)

const ComponentName = z.string().trim().min(1).max(200)
const LevelLabel = z.string().trim().min(1).max(100)
const ItemCode = z.string().regex(/^[cl][1-9][0-9]?$/)

const toCents = (value: number) => Math.round(value * 100)

/** Positional codes (c1…, l1…) and unique names by lookup key. */
function checkItems(
  items: { code?: string | undefined; name: string }[],
  prefix: 'c' | 'l',
  ctx: z.RefinementCtx,
  key: 'components' | 'levels',
) {
  const seen = new Set<string>()
  items.forEach((item, index) => {
    if (item.code !== undefined && item.code !== `${prefix}${index + 1}`)
      ctx.addIssue({ code: 'custom', path: [key, index, 'code'], message: 'invalid_code' })
    const itemKey = nameKey(item.name)
    if (seen.has(itemKey))
      ctx.addIssue({ code: 'custom', path: [key, index, 'name'], message: 'duplicate_name' })
    seen.add(itemKey)
  })
}

/**
 * Builds the configuration union from the field schemas that differ between a
 * client request (codes, totals and formula optional) and a stored version.
 */
function configSchemas<
  Code extends z.ZodType<string | undefined>,
  Score extends z.ZodType<number | undefined>,
  Count extends z.ZodType<number | undefined>,
  Formula extends z.ZodType<typeof IELTS_FORMULA_VERSION | undefined>,
>({
  code,
  totalScore,
  totalCount,
  formulaVersion,
}: {
  code: Code
  totalScore: Score
  totalCount: Count
  formulaVersion: Formula
}) {
  const NumericComponent = z.strictObject({ code, name: ComponentName, maxScore: MaxScore })
  const FractionComponent = z.strictObject({
    code,
    name: ComponentName,
    totalQuestions: QuestionCount,
  })

  const numericComponents = z
    .strictObject({
      scaleKind: z.literal('numeric'),
      inputMode: z.literal('components'),
      maxScore: totalScore,
      showComponents: z.boolean(),
      components: z.array(NumericComponent).min(1).max(MAX_COMPONENTS),
    })
    .superRefine((value, ctx) => {
      checkItems(value.components, 'c', ctx, 'components')
      const sum = value.components.reduce((total, item) => total + toCents(item.maxScore), 0)
      // Generic fields are opaque here; their exported types stay exact.
      const declared = (value as { maxScore?: number }).maxScore
      if (declared !== undefined && toCents(declared) !== sum)
        ctx.addIssue({ code: 'custom', path: ['maxScore'], message: 'total_mismatch' })
    })

  const fractionComponents = z
    .strictObject({
      scaleKind: z.literal('fraction'),
      inputMode: z.literal('components'),
      totalQuestions: totalCount,
      showComponents: z.boolean(),
      components: z.array(FractionComponent).min(1).max(MAX_COMPONENTS),
    })
    .superRefine((value, ctx) => {
      checkItems(value.components, 'c', ctx, 'components')
      const sum = value.components.reduce((total, item) => total + item.totalQuestions, 0)
      const declared = (value as { totalQuestions?: number }).totalQuestions
      if (sum > 2_147_483_647 || (declared !== undefined && declared !== sum))
        ctx.addIssue({ code: 'custom', path: ['totalQuestions'], message: 'total_mismatch' })
    })

  const Numeric = z.discriminatedUnion('inputMode', [
    z.strictObject({
      scaleKind: z.literal('numeric'),
      inputMode: z.literal('direct'),
      maxScore: MaxScore,
    }),
    numericComponents,
  ])
  const Fraction = z.discriminatedUnion('inputMode', [
    z.strictObject({
      scaleKind: z.literal('fraction'),
      inputMode: z.literal('direct'),
      totalQuestions: QuestionCount,
    }),
    fractionComponents,
  ])

  const Letter = z
    .strictObject({
      scaleKind: z.literal('letter'),
      inputMode: z.literal('direct'),
      levels: z
        .array(z.strictObject({ code, label: LevelLabel }))
        .min(1)
        .max(MAX_LETTER_LEVELS),
    })
    .superRefine((value, ctx) =>
      checkItems(
        (value.levels as { code?: string; label: string }[]).map((level) => ({
          code: level.code,
          name: level.label,
        })),
        'l',
        ctx,
        'levels',
      ),
    )

  // L/R detailed keep a maximum number of questions; W/S criteria are fixed by
  // the formula version, so no other per-skill setting exists.
  const Skill = z
    .strictObject({
      code: IeltsSkill,
      inputMode: z.enum(['direct', 'detailed']),
      maxQuestions: QuestionCount.optional(),
    })
    .superRefine((value, ctx) => {
      const needsCount =
        (value.code === 'L' || value.code === 'R') && value.inputMode === 'detailed'
      if (needsCount !== (value.maxQuestions !== undefined))
        ctx.addIssue({ code: 'custom', path: ['maxQuestions'], message: 'invalid_for_skill' })
    })

  const Ielts = z
    .strictObject({
      scaleKind: z.literal('ielts'),
      formulaVersion,
      showComponents: z.boolean(),
      skills: z.array(Skill).min(1).max(4),
    })
    .superRefine((value, ctx) => {
      const codes = value.skills.map((skill) => skill.code)
      if (new Set(codes).size !== codes.length)
        ctx.addIssue({ code: 'custom', path: ['skills'], message: 'duplicate_skill' })
    })

  return z.discriminatedUnion('scaleKind', [Numeric, Fraction, Letter, Ielts])
}

/** Configuration as sent by the client (codes and totals optional). */
export const TestTemplateConfigInput = configSchemas({
  code: ItemCode.optional(),
  totalScore: MaxScore.optional(),
  totalCount: QuestionCount.optional(),
  formulaVersion: z.literal(IELTS_FORMULA_VERSION).optional(),
})
export type TestTemplateConfigInput = z.infer<typeof TestTemplateConfigInput>

/** Normalized configuration as stored in a version. */
export const TestTemplateConfig = configSchemas({
  code: ItemCode,
  totalScore: MaxScore,
  totalCount: QuestionCount,
  formulaVersion: z.literal(IELTS_FORMULA_VERSION),
})
export type TestTemplateConfig = z.infer<typeof TestTemplateConfig>

const TemplateName = z.string().trim().min(1).max(200)
/** Optional plain text; empty becomes null (C.1.1, 5,000 characters). */
const Description = z
  .string()
  .trim()
  .max(5000)
  .nullable()
  .transform((value) => value || null)

export const CreateTestTemplateRequest = z.strictObject({
  name: TemplateName,
  description: Description,
  config: TestTemplateConfigInput,
})
export type CreateTestTemplateRequest = z.input<typeof CreateTestTemplateRequest>

export const UpdateTestTemplateRequest = CreateTestTemplateRequest.extend({
  expectedVersion: RowVersion,
})
export type UpdateTestTemplateRequest = z.input<typeof UpdateTestTemplateRequest>

export const TestTemplate = z.object({
  id: z.uuid(),
  currentVersionId: z.uuid(),
  /** Revision of the current version; starts at 1 and grows with every edit. */
  revision: z.number().int().min(1),
  name: z.string(),
  description: z.string().nullable(),
  config: TestTemplateConfig,
  archived: z.boolean(),
  deletedAt: z.string().nullable(),
  deletedReason: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
  rowVersion: RowVersion,
})
export type TestTemplate = z.infer<typeof TestTemplate>

export const TestTemplateVersion = z.object({
  id: z.uuid(),
  templateId: z.uuid(),
  revision: z.number().int().min(1),
  name: z.string(),
  description: z.string().nullable(),
  config: TestTemplateConfig,
  createdAt: z.string(),
  createdByName: z.string(),
})
export type TestTemplateVersion = z.infer<typeof TestTemplateVersion>

/**
 * Tests of a class (TEST-05). The grading configuration is a snapshot of the
 * test: written from scratch or copied from one exact template version and
 * adjusted. It has the same shape as a template configuration; showComponents
 * is the test's display option (TEST-04), kept outside the snapshot.
 */
export const GradingConfigInput = TestTemplateConfigInput
export type GradingConfigInput = TestTemplateConfigInput
export const GradingConfig = TestTemplateConfig
export type GradingConfig = TestTemplateConfig

/** True when the display option has something to show (components or a detailed IELTS skill). */
export const hasDetails = (config: GradingConfigInput) =>
  ('inputMode' in config && config.inputMode === 'components') ||
  (config.scaleKind === 'ielts' && config.skills.some((skill) => skill.inputMode === 'detailed'))

const TestName = z.string().trim().min(1).max(200)

const TestInfo = {
  name: TestName,
  testOn: IsoDate,
  description: Description,
}

export const CreateTestRequest = z.strictObject({
  ...TestInfo,
  config: GradingConfigInput,
  /** Template version that was copied, or null for a configuration from scratch. */
  sourceTemplateVersionId: z.uuid().nullable(),
})
export type CreateTestRequest = z.input<typeof CreateTestRequest>

export const UpdateTestRequest = z.strictObject({ ...TestInfo, expectedVersion: RowVersion })
export type UpdateTestRequest = z.input<typeof UpdateTestRequest>

export const SetShowComponentsRequest = z.strictObject({
  showComponents: z.boolean(),
  expectedVersion: RowVersion,
})
export type SetShowComponentsRequest = z.input<typeof SetShowComponentsRequest>

/** Template version a snapshot was copied from (provenance only). */
export const TestSource = z.object({
  templateId: z.uuid(),
  templateVersionId: z.uuid(),
  revision: z.number().int().min(1),
  name: z.string(),
  templateArchived: z.boolean(),
})
export type TestSource = z.infer<typeof TestSource>

export const ClassTest = z.object({
  id: z.uuid(),
  classId: z.uuid(),
  name: z.string(),
  testOn: IsoDate,
  description: z.string().nullable(),
  showComponents: z.boolean(),
  /** Snapshot used by results and Excel (XLS-06); fixed when the test is created. */
  configId: z.uuid(),
  config: GradingConfig,
  source: TestSource.nullable(),
  /** Results in use (not cleared). */
  resultCount: z.number().int().min(0),
  /** Results currently published (ACAD-01). */
  publishedCount: z.number().int().min(0),
  /** Comments with text on this test (COMMENT-01). */
  commentCount: z.number().int().min(0),
  publishedCommentCount: z.number().int().min(0),
  /** TEST-06: archived with a reason; scores and comments are kept unpublished. */
  deleted: z.boolean(),
  deletedAt: z.string().nullable(),
  deletedReason: z.string().nullable(),
  createdAt: z.string(),
  createdByName: z.string(),
  updatedAt: z.string(),
  rowVersion: RowVersion,
})
export type ClassTest = z.infer<typeof ClassTest>

export const ClassTestList = z.object({
  items: z.array(ClassTest),
  /** Admin or a current teacher/assistant, in a class that is not deleted. */
  canEdit: z.boolean(),
  /** Admin or a current teacher (TEST-04); assistants cannot change the display option. */
  canChangeDisplay: z.boolean(),
  /** Admin or a current teacher (TEST-06): archive and restore whole tests. */
  canArchive: z.boolean(),
})
export type ClassTestList = z.infer<typeof ClassTestList>

/**
 * Results of a test per student (TEST-01/04/05). One result per student and
 * test. Absent is its own state. By component, the total is computed by the
 * database from the values entered; a missing component is not 0.
 */

/** Score of the test or a component: 0 or more, at most two decimals (TEST-01). */
export const ScoreValue = z
  .number()
  .min(0)
  .refine((value) => /^\d+(\.\d{1,2})?$/.test(value.toString()), { message: 'too_many_decimals' })
export const AnswerCount = z.number().int().min(0).max(2_147_483_647)
const AnswerCountInput = AnswerCount.nullable()

/** IELTS band typed by a user: 0 to 9 in steps of 0.5, never corrected (TEST-01). */
export const Band = z
  .number()
  .min(0)
  .max(9)
  .refine((value) => Number.isInteger(value * 2), { message: 'band_step' })

/**
 * Inputs of one IELTS skill, by the mode of the test: direct {band}; L/R in
 * detail {correctAnswers, band}; W/S in detail {criteria}. Computed bands are
 * never sent. null or a missing key is not entered.
 */
export const IeltsSkillEntry = z.union([
  z.strictObject({ band: Band.nullable().optional(), correctAnswers: AnswerCountInput.optional() }),
  z.strictObject({ criteria: z.record(z.string().regex(/^[a-z0-9_]{2,13}$/), Band.nullable()) }),
])
export type IeltsSkillEntry = z.infer<typeof IeltsSkillEntry>

/** Values for one student; which keys apply depends on the test configuration. */
export const ResultEntry = z.union([
  z.strictObject({ absent: z.literal(true) }),
  z.strictObject({ absent: z.literal(false), score: ScoreValue }),
  z.strictObject({ absent: z.literal(false), correctAnswers: AnswerCount }),
  z.strictObject({ absent: z.literal(false), level: z.string().regex(/^l\d{1,2}$/) }),
  z.strictObject({
    absent: z.literal(false),
    /** Component code (c1…) → value; a missing or null code is not entered. */
    components: z.record(
      z.string().regex(/^c\d{1,2}$/),
      z.union([ScoreValue, AnswerCount]).nullable(),
    ),
  }),
  z.strictObject({
    absent: z.literal(false),
    skills: z.partialRecord(IeltsSkill, IeltsSkillEntry.nullable()),
  }),
])
export type ResultEntry = z.infer<typeof ResultEntry>

export const SaveTestResultsRequest = z.strictObject({
  /** Snapshot the values were entered on; another one is a version conflict. */
  configId: z.uuid(),
  items: z
    .array(
      z.strictObject({
        studentId: z.uuid(),
        /** null when the student has no result in use (none yet, or cleared). */
        expectedVersion: RowVersion.nullable(),
        /** null clears the result. */
        entry: ResultEntry.nullable(),
      }),
    )
    .min(1)
    .max(1000),
})
export type SaveTestResultsRequest = z.input<typeof SaveTestResultsRequest>

export const IeltsSkillResult = z.object({
  correctAnswers: z.number().int().nullable(),
  /** Band typed by the user (direct, or L/R in detail). */
  inputBand: z.number().nullable(),
  /** Band in use: typed, or computed from the criteria for W/S in detail. */
  band: z.number().nullable(),
  task1Band: z.number().nullable(),
  task2Band: z.number().nullable(),
  criteria: z.record(z.string(), z.number()),
})
export type IeltsSkillResult = z.infer<typeof IeltsSkillResult>

export const TestResult = z.object({
  id: z.uuid(),
  absent: z.boolean(),
  /** Numeric: direct score, or total of the components entered so far. */
  score: z.number().nullable(),
  /** Fraction: direct answers, or sum of the components entered so far. */
  correctAnswers: z.number().int().nullable(),
  level: z.string().nullable(),
  components: z.record(z.string(), z.number()),
  /** IELTS inputs and computed bands per skill entered; null for other scales or Absent. */
  ielts: z.partialRecord(IeltsSkill, IeltsSkillResult).nullable(),
  /** Computed by the backend, only with four skills and four bands (TEST-01). */
  overallBand: z.number().nullable(),
  /** Absent, or every value of the configuration entered. */
  complete: z.boolean(),
  /** ACAD-01: a published result is locked until it is unpublished. */
  published: z.boolean(),
  publishedAt: z.string().nullable(),
  publishedByName: z.string().nullable(),
  rowVersion: RowVersion,
  updatedAt: z.string(),
  updatedByName: z.string(),
})
export type TestResult = z.infer<typeof TestResult>

export const TestResultRow = z.object({
  studentId: z.uuid(),
  code: z.string(),
  fullName: z.string(),
  result: TestResult.nullable(),
})
export type TestResultRow = z.infer<typeof TestResultRow>

export const TestResults = z.object({
  test: ClassTest,
  /** Students whose participation meets the test day, or who hold a result. */
  students: z.array(TestResultRow),
  canEdit: z.boolean(),
  /** Admin or a current teacher (ACAD-01); assistants enter results but never publish. */
  canPublish: z.boolean(),
})
export type TestResults = z.infer<typeof TestResults>

/**
 * Publish or unpublish results of one test (ACAD-01): one student, or the whole
 * class when studentId is null. Only complete results (or Absent) are published.
 */
export const PublishTestResultsRequest = z.strictObject({
  studentId: z.uuid().nullable(),
  publish: z.boolean(),
})
export type PublishTestResultsRequest = z.input<typeof PublishTestResultsRequest>

export const PublishTestResultsResponse = TestResults.extend({
  /** Results whose publication changed. */
  changed: z.number().int().min(0),
  /** Publishing the class: students skipped because their result is missing or incomplete. */
  missing: z.array(z.object({ studentId: z.uuid(), fullName: z.string() })),
})
export type PublishTestResultsResponse = z.infer<typeof PublishTestResultsResponse>
