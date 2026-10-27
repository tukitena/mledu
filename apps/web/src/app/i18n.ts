import { watch } from 'vue'
import { createI18n } from 'vue-i18n'
import { en } from '../locales/en'
import { vi } from '../locales/vi'
import { readPreference, writePreference } from '../lib/storage'

/** UX-01: Vietnamese/English, kept per browser. */
export const LOCALES = ['vi', 'en'] as const
export type Locale = (typeof LOCALES)[number]

const STORAGE_KEY = 'mledu.locale'

export const i18n = createI18n({
  legacy: false,
  locale: readPreference<Locale>(STORAGE_KEY, LOCALES, 'vi'),
  fallbackLocale: 'vi',
  messages: { vi, en },
})

export function initLocale() {
  const apply = (locale: string) => {
    document.documentElement.lang = locale
    writePreference(STORAGE_KEY, locale)
  }
  apply(i18n.global.locale.value)
  watch(i18n.global.locale, apply)
}
