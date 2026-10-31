<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { appliedTheme } from '../app/theme'

// Page footer: the centre's primary logo beside two rows of links (help, then
// designer and contact) over the wave background; the rows stack on phones.
const { t } = useI18n()
const year = new Intl.DateTimeFormat('en', {
  year: 'numeric',
  timeZone: 'Asia/Ho_Chi_Minh',
}).format(new Date())
const DESIGNER = {
  name: 'Đỗ Ngọc Tuấn Kiệt',
  handle: 'tukitena',
  profile: 'https://github.com/tukitena',
  email: 'dntk@gmail.com',
  phone: '0337045010',
}
const supportHref = `mailto:${DESIGNER.email}?subject=${encodeURIComponent('Hỗ trợ MLedu')}`
const logo = computed(() => (appliedTheme.value === 'dark' ? '/primary-dark.png' : '/primary.png'))
</script>

<template>
  <footer class="app-footer" data-testid="app-footer">
    <div class="footer-inner">
      <div class="footer-brand">
        <img :src="logo" :alt="t('footer.logoAlt')" width="1640" height="900" />
      </div>
      <div class="footer-links">
        <ul class="footer-row">
          <li class="text-body-secondary">
            {{ t('footer.copyright', { year }) }}
          </li>
          <li>
            <span
              class="footer-soon"
              :title="t('footer.comingSoon')"
              data-testid="footer-guide"
              aria-disabled="true"
              >{{ t('footer.guide') }}</span
            >
          </li>
          <li>
            <a :href="supportHref" data-testid="footer-support">{{ t('footer.support') }}</a>
          </li>
        </ul>
        <ul class="footer-row" data-testid="footer-credit">
          <li class="text-body-secondary">
            <span
              >{{ t('footer.designedBy') }}
              <a :href="DESIGNER.profile" target="_blank" rel="noopener noreferrer"
                >{{ DESIGNER.name }} ({{ DESIGNER.handle }})</a
              ></span
            >
          </li>
          <li class="text-body-secondary">
            <span
              >{{ t('footer.contact') }}
              <a :href="`mailto:${DESIGNER.email}`">{{ DESIGNER.email }}</a></span
            >
          </li>
          <li>
            <a
              :href="`tel:${DESIGNER.phone}`"
              :aria-label="`${t('footer.phone')} ${DESIGNER.phone}`"
              >{{ DESIGNER.phone }}</a
            >
          </li>
        </ul>
      </div>
    </div>
  </footer>
</template>
