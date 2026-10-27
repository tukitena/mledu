import { createApp } from 'vue'
import App from './App.vue'
import { i18n, initLocale } from './app/i18n'
import { router } from './app/router'
import { startProfileSync } from './app/session'
import { initTheme } from './app/theme'
import './styles/main.scss'

initTheme()
initLocale()
startProfileSync()

createApp(App).use(i18n).use(router).mount('#app')
