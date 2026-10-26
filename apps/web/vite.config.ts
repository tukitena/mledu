import vue from '@vitejs/plugin-vue'
import { defineConfig } from 'vitest/config'

export default defineConfig({
  plugins: [vue()],
  css: {
    preprocessorOptions: {
      scss: {
        // Bootstrap 5.3 still uses @import and global Sass functions.
        quietDeps: true,
        silenceDeprecations: ['import', 'global-builtin', 'color-functions', 'if-function'],
      },
    },
  },
  build: {
    outDir: 'dist',
    // Maps are generated for debugging but not referenced from the deployed bundle.
    sourcemap: 'hidden',
  },
  test: {
    include: ['src/**/*.test.ts'],
  },
})
