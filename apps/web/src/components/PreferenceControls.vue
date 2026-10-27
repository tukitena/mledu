<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import { LOCALES } from '../app/i18n'
import { appliedTheme, THEMES, themeChoice } from '../app/theme'

defineProps<{ compact?: boolean }>()

const { locale, t } = useI18n()
const languageNames: Record<string, string> = { vi: 'Tiếng Việt', en: 'English' }
</script>

<template>
  <div class="preference-controls d-flex align-items-center gap-2" :class="{ compact }">
    <div class="preference-choice">
      <span v-if="compact" class="preference-symbol" aria-hidden="true">{{
        locale.toUpperCase()
      }}</span>
      <select
        v-model="locale"
        class="form-select form-select-sm w-auto"
        :aria-label="t('prefs.language')"
        data-testid="locale-select"
      >
        <option v-for="code in LOCALES" :key="code" :value="code">{{ languageNames[code] }}</option>
      </select>
    </div>
    <div class="preference-choice">
      <i
        v-if="compact"
        class="bi preference-symbol"
        :class="
          themeChoice === 'system' ? 'bi-display' : appliedTheme === 'dark' ? 'bi-moon' : 'bi-sun'
        "
        aria-hidden="true"
      ></i>
      <select
        v-model="themeChoice"
        class="form-select form-select-sm w-auto"
        :aria-label="t('prefs.theme')"
        data-testid="theme-select"
      >
        <option v-for="theme in THEMES" :key="theme" :value="theme">
          {{ t(`prefs.themes.${theme}`) }}
        </option>
      </select>
    </div>
  </div>
</template>
