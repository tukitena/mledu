import { createApp } from 'vue'
import App from './App.vue'
import { router } from './app/router'
import './styles/main.scss'

createApp(App).use(router).mount('#app')
