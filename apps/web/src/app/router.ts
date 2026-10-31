import type { Workspace } from '@mledu/contracts/common'
import { createRouter, createWebHistory } from 'vue-router'
import { loadProfile, profile, workspace, workspaces } from './session'

declare module 'vue-router' {
  interface RouteMeta {
    /** Reachable without signing in. */
    public?: boolean
    /** Signed-in users are sent on to the app. */
    guestOnly?: boolean
    /** Sidebar entry highlighted for a page that has none of its own. */
    navParent?: string
    /**
     * Workspaces whose function set includes the page; the first one the account
     * may use is selected when the current workspace does not offer it.
     */
    workspaces?: Workspace[]
  }
}

export const router = createRouter({
  history: createWebHistory(),
  routes: [
    {
      path: '/login',
      name: 'login',
      component: () => import('../features/auth/LoginPage.vue'),
      meta: { public: true, guestOnly: true },
    },
    {
      path: '/forgot-password',
      name: 'forgot-password',
      component: () => import('../features/auth/ForgotPasswordPage.vue'),
      meta: { public: true, guestOnly: true },
    },
    {
      path: '/reset-password',
      name: 'reset-password',
      component: () => import('../features/auth/ResetPasswordPage.vue'),
      meta: { public: true },
    },
    {
      path: '/change-password',
      name: 'change-password',
      component: () => import('../features/auth/ChangePasswordPage.vue'),
    },
    {
      path: '/',
      component: () => import('./AppShell.vue'),
      children: [
        {
          path: '',
          name: 'dashboard',
          component: () => import('../features/dashboard/DashboardPage.vue'),
        },
        {
          path: 'profile',
          name: 'profile',
          component: () => import('../features/profile/ProfilePage.vue'),
        },
        {
          path: 'admin/accounts',
          name: 'accounts',
          component: () => import('../features/accounts/AccountsPage.vue'),
          meta: { workspaces: ['admin'] },
        },
        {
          path: 'students',
          name: 'students',
          component: () => import('../features/students/StudentsPage.vue'),
        },
        {
          path: 'classes',
          name: 'classes',
          component: () => import('../features/classes/ClassesPage.vue'),
        },
        {
          path: 'classes/:id',
          name: 'class-detail',
          component: () => import('../features/classes/ClassDetailPage.vue'),
          meta: { navParent: 'classes' },
        },
        {
          path: 'admin/test-templates',
          name: 'test-templates',
          component: () => import('../features/assessments/TestTemplatesPage.vue'),
          meta: { workspaces: ['admin'] },
        },
        {
          path: 'catalogs',
          name: 'catalogs',
          component: () => import('../features/catalogs/CatalogsPage.vue'),
          meta: { workspaces: ['admin', 'receptionist'] },
        },
      ],
    },
    {
      path: '/:pathMatch(.*)*',
      name: 'not-found',
      component: () => import('./NotFoundPage.vue'),
      meta: { public: true },
    },
  ],
})

let profileLoaded = false

// Navigation follows the current profile; the API still checks every request.
router.beforeEach(async (to) => {
  if (!profileLoaded) {
    await loadProfile().catch(() => null)
    profileLoaded = true
  }
  const current = profile.value
  if (to.meta.public) {
    if (to.meta.guestOnly && current)
      return { name: current.mustChangePassword ? 'change-password' : 'dashboard' }
    return true
  }
  if (!current)
    return { name: 'login', query: to.fullPath === '/' ? {} : { redirect: to.fullPath } }
  if (current.mustChangePassword && to.name !== 'change-password')
    return { name: 'change-password' }
  const allowed = to.meta.workspaces?.filter((item) => workspaces.value.includes(item))
  if (allowed) {
    if (!allowed.length) return { name: 'dashboard' }
    if (!workspace.value || !allowed.includes(workspace.value)) workspace.value = allowed[0]!
  }
  return true
})
