<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { RouterLink, RouterView, useRoute, useRouter } from 'vue-router'
import MyAvatar from '../components/MyAvatar.vue'
import PreferenceControls from '../components/PreferenceControls.vue'
import { appliedTheme, themeChoice } from './theme'
import { profile, signOut, workspace, workspaces } from './session'

const { t } = useI18n()
const route = useRoute()
const router = useRouter()
const sidebarOpen = ref(false)
const menuOpen = ref(false)
const sidebarCollapsed = ref(false)
const search = ref('')
const searchInput = ref<HTMLInputElement | null>(null)
const searchFocused = ref(false)
const compactHeaderMedia = window.matchMedia('(max-width: 767.98px)')
const compactHeader = ref(compactHeaderMedia.matches)
function updateCompactHeader() {
  compactHeader.value = compactHeaderMedia.matches
}
const searchResults = computed(() =>
  navItems.value.filter((item) =>
    item.label.toLocaleLowerCase().includes(search.value.toLocaleLowerCase().trim()),
  ),
)

function closeMenus() {
  sidebarOpen.value = false
  menuOpen.value = false
  searchFocused.value = false
}

function onKeydown(event: KeyboardEvent) {
  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'k') {
    event.preventDefault()
    searchInput.value?.focus()
  }
  if (event.key === 'Escape') closeMenus()
}

function openSearchResult() {
  const first = searchResults.value[0]
  if (first) void router.push({ name: first.name })
  searchFocused.value = false
  searchInput.value?.blur()
}

async function toggleFullscreen() {
  if (document.fullscreenElement) await document.exitFullscreen().catch(() => undefined)
  else await document.documentElement.requestFullscreen?.().catch(() => undefined)
}

function onSearchFocusOut(event: FocusEvent) {
  const form = event.currentTarget as HTMLElement
  if (!form.contains(event.relatedTarget as Node | null)) searchFocused.value = false
}

onMounted(() => {
  window.addEventListener('keydown', onKeydown)
  compactHeaderMedia.addEventListener('change', updateCompactHeader)
})
onBeforeUnmount(() => {
  window.removeEventListener('keydown', onKeydown)
  compactHeaderMedia.removeEventListener('change', updateCompactHeader)
})

// Function set of the selected workspace (A.2). Later phases add their pages here.
const navItems = computed(() => [
  { name: 'dashboard', icon: 'bi-speedometer2', label: t('nav.dashboard') },
  ...(workspace.value === 'admin'
    ? [{ name: 'accounts', icon: 'bi-people', label: t('nav.accounts') }]
    : []),
  { name: 'students', icon: 'bi-person-badge', label: t('nav.students') },
  ...(workspace.value === 'admin' || workspace.value === 'receptionist'
    ? [{ name: 'catalogs', icon: 'bi-collection', label: t('nav.catalogs') }]
    : []),
  { name: 'profile', icon: 'bi-person-circle', label: t('nav.profile') },
])

watch(
  () => route.fullPath,
  () => {
    closeMenus()
    search.value = ''
  },
)

// Leaving a workspace leaves its pages too.
watch(workspace, (current) => {
  if (route.meta.workspaces && (!current || !route.meta.workspaces.includes(current)))
    void router.push({ name: 'dashboard' })
})

async function onSignOut() {
  await signOut()
  await router.replace({ name: 'login' })
}
</script>

<template>
  <div v-if="profile" class="app-shell" :class="{ 'sidebar-collapsed': sidebarCollapsed }">
    <header class="app-header">
      <RouterLink class="app-brand" :to="{ name: 'dashboard' }">
        <span class="brand-mark" aria-hidden="true">M</span>
        <span>{{ t('app.name') }}</span>
      </RouterLink>
      <button
        type="button"
        class="header-icon sidebar-toggle d-lg-none"
        :aria-label="t('nav.menu')"
        :aria-expanded="sidebarOpen"
        aria-controls="app-sidebar"
        data-testid="mobile-menu"
        @click="sidebarOpen = !sidebarOpen"
      >
        <i class="bi bi-list" aria-hidden="true"></i>
      </button>
      <button
        type="button"
        class="header-icon sidebar-toggle d-none d-lg-inline-flex"
        :aria-label="t('nav.menu')"
        :aria-expanded="!sidebarCollapsed"
        aria-controls="app-sidebar"
        data-testid="desktop-menu"
        @click="sidebarCollapsed = !sidebarCollapsed"
      >
        <i class="bi bi-list" aria-hidden="true"></i>
      </button>

      <form
        class="header-search d-none d-lg-flex"
        role="search"
        @submit.prevent="openSearchResult"
        @focusout="onSearchFocusOut"
      >
        <input
          ref="searchInput"
          v-model="search"
          type="search"
          :placeholder="t('nav.searchPlaceholder')"
          :aria-label="t('nav.searchPages')"
          aria-controls="navigation-search-results"
          :aria-expanded="searchFocused"
          data-testid="nav-search"
          @focus="searchFocused = true"
        />
        <i class="bi bi-search" aria-hidden="true"></i>
        <div v-if="searchFocused" id="navigation-search-results" class="navigation-search-results">
          <RouterLink
            v-for="item in searchResults"
            :key="item.name"
            :to="{ name: item.name }"
            class="user-menu-item"
            @mousedown.prevent
            @click="searchFocused = false"
          >
            <i class="bi" :class="item.icon" aria-hidden="true"></i>{{ item.label }}
          </RouterLink>
          <p v-if="!searchResults.length" class="text-body-secondary m-0 px-3 py-2">
            {{ t('nav.noResults') }}
          </p>
        </div>
      </form>

      <div class="header-tools ms-auto ms-lg-0 d-flex align-items-center gap-1">
        <select
          v-if="workspaces.length > 1"
          v-model="workspace"
          class="form-select form-select-sm w-auto"
          :aria-label="t('nav.workspace')"
          data-testid="workspace-select"
        >
          <option v-for="item in workspaces" :key="item" :value="item">
            {{ t(`workspace.${item}`) }}
          </option>
        </select>
        <div v-if="!compactHeader"><PreferenceControls compact /></div>
        <button
          v-else
          type="button"
          class="header-icon quick-theme"
          :aria-label="t('prefs.theme')"
          data-testid="quick-theme"
          @click="themeChoice = appliedTheme === 'dark' ? 'light' : 'dark'"
        >
          <i
            class="bi"
            :class="appliedTheme === 'dark' ? 'bi-moon' : 'bi-sun'"
            aria-hidden="true"
          ></i>
        </button>
        <button
          type="button"
          class="header-icon d-none d-xl-inline-flex"
          :aria-label="t('nav.fullscreen')"
          @click="toggleFullscreen"
        >
          <i class="bi bi-arrows-fullscreen" aria-hidden="true"></i>
        </button>

        <div class="user-menu-wrap">
          <button
            type="button"
            class="btn user-menu-toggle"
            :aria-label="profile.fullName"
            :aria-expanded="menuOpen"
            data-testid="user-menu"
            @click="menuOpen = !menuOpen"
          >
            <MyAvatar :path="profile.avatarPath" :name="profile.fullName" :size="24" />
            <span class="d-none d-sm-inline">{{ profile.fullName }}</span>
            <i class="bi bi-chevron-down" aria-hidden="true"></i>
          </button>
          <div v-if="menuOpen" class="user-menu shadow">
            <div class="px-3 py-2 small text-body-secondary">
              {{ profile.email }}<br />{{ t(`accountType.${profile.accountType}`) }}
            </div>
            <div v-if="compactHeader" class="px-3 pb-2"><PreferenceControls /></div>
            <RouterLink class="user-menu-item" :to="{ name: 'profile' }">
              <i class="bi bi-person" aria-hidden="true"></i>{{ t('nav.profile') }}
            </RouterLink>
            <button type="button" class="user-menu-item" @click="onSignOut">
              <i class="bi bi-box-arrow-right" aria-hidden="true"></i>{{ t('nav.signOut') }}
            </button>
          </div>
        </div>
      </div>
    </header>

    <nav
      id="app-sidebar"
      class="app-sidebar"
      :class="{ show: sidebarOpen }"
      :aria-label="t('nav.mainNav')"
    >
      <div
        class="sidebar-workspace small text-body-secondary"
        :title="workspace ? t(`workspace.${workspace}`) : ''"
      >
        {{ workspace ? t(`workspace.${workspace}`) : '' }}
      </div>
      <ul class="nav flex-column sidebar-nav">
        <li v-for="item in navItems" :key="item.name" class="nav-item">
          <RouterLink
            class="nav-link"
            :to="{ name: item.name }"
            exact-active-class="active"
            :data-testid="`nav-${item.name}`"
            :title="item.label"
            :aria-label="item.label"
          >
            <i class="bi" :class="item.icon" aria-hidden="true"></i
            ><span class="nav-label">{{ item.label }}</span>
          </RouterLink>
        </li>
      </ul>
      <div class="sidebar-footer">
        <i class="bi bi-mortarboard" aria-hidden="true"></i>
        <span>{{ t('app.tagline') }}</span>
      </div>
    </nav>
    <div v-if="sidebarOpen" class="sidebar-backdrop d-lg-none" @click="sidebarOpen = false"></div>

    <main class="app-main">
      <RouterView />
    </main>
    <div v-if="menuOpen" class="menu-dismiss" @click="menuOpen = false"></div>
  </div>
</template>
