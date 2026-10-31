import { z } from 'zod'
import { RowVersion } from './common'
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
