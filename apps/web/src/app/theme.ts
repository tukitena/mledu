import { ref, watch } from 'vue'
import { readPreference, writePreference } from '../lib/storage'

/** UX-01: light/dark/system, kept per browser. `system` follows the OS live. */
export const THEMES = ['light', 'dark', 'system'] as const
export type ThemeChoice = (typeof THEMES)[number]

const STORAGE_KEY = 'mledu.theme'
const media = window.matchMedia('(prefers-color-scheme: dark)')

export const themeChoice = ref<ThemeChoice>(readPreference(STORAGE_KEY, THEMES, 'system'))
export const appliedTheme = ref<'light' | 'dark'>('light')

function apply() {
  appliedTheme.value =
    themeChoice.value === 'system' ? (media.matches ? 'dark' : 'light') : themeChoice.value
  document.documentElement.setAttribute('data-bs-theme', appliedTheme.value)
}

export function initTheme() {
  apply()
  media.addEventListener('change', apply)
  watch(themeChoice, (value) => {
    writePreference(STORAGE_KEY, value)
    apply()
  })
}
