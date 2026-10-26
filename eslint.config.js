import js from '@eslint/js'
import prettier from 'eslint-config-prettier'
import vue from 'eslint-plugin-vue'
import globals from 'globals'
import tseslint from 'typescript-eslint'

export default tseslint.config(
  {
    ignores: [
      '**/dist/**',
      '**/coverage/**',
      '**/.wrangler/**',
      '**/generated/**',
      'playwright-report/**',
      'test-results/**',
      'template/**',
      '.agents/**',
    ],
  },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  ...vue.configs['flat/recommended'],
  {
    files: ['**/*.vue'],
    languageOptions: { parserOptions: { parser: tseslint.parser } },
  },
  {
    files: ['apps/web/**/*.{ts,vue}'],
    languageOptions: { globals: globals.browser },
  },
  {
    files: ['scripts/**/*.mjs', '*.config.{js,ts}', '**/vite.config.ts', '**/vitest.config.ts'],
    languageOptions: { globals: globals.node },
  },
  {
    rules: {
      // Never let reference UI leak into the application (techstack §2).
      'no-restricted-imports': [
        'error',
        { patterns: [{ group: ['**/template/**'], message: 'template/ is reference only.' }] },
      ],
      '@typescript-eslint/consistent-type-imports': 'error',
      // Ambient declaration merging (e.g. Cloudflare.Env) needs `declare global { namespace }`.
      '@typescript-eslint/no-namespace': ['error', { allowDeclarations: true }],
    },
  },
  prettier,
)
