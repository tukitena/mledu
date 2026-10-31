import type { TestTemplateConfig } from '@mledu/contracts/assessments'

type Translate = (key: string, values?: Record<string, unknown>) => string

/** Scores keep their exact decimals; Vietnamese uses a decimal comma (8,25). */
export const formatScore = (value: number, locale: string) =>
  new Intl.NumberFormat(locale === 'vi' ? 'vi-VN' : 'en-GB', {
    maximumFractionDigits: 2,
    useGrouping: false,
  }).format(value)

/** One-line description of a configuration for lists and history. */
export function configSummary(config: TestTemplateConfig, t: Translate, locale: string): string {
  switch (config.scaleKind) {
    case 'numeric':
      return config.inputMode === 'direct'
        ? t('testTemplates.summary.numeric', { max: formatScore(config.maxScore, locale) })
        : t('testTemplates.summary.numericComponents', {
            max: formatScore(config.maxScore, locale),
            n: config.components.length,
          })
    case 'fraction':
      return config.inputMode === 'direct'
        ? t('testTemplates.summary.fraction', { n: config.totalQuestions })
        : t('testTemplates.summary.fractionComponents', {
            n: config.totalQuestions,
            parts: config.components.length,
          })
    case 'letter':
      return config.levels.map((level) => level.label).join(' · ')
    case 'ielts':
      return config.skills
        .map((skill) =>
          skill.inputMode === 'direct'
            ? skill.code
            : `${skill.code} (${
                skill.maxQuestions
                  ? t('testTemplates.summary.questions', { n: skill.maxQuestions })
                  : t('testTemplates.summary.detailed')
              })`,
        )
        .join(', ')
  }
}
