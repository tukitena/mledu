// Fails when build output contains secrets or reference-template material.
// Runs after `npm run build` on a clean checkout (template/ is not in Git).
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs'
import { join, relative } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = fileURLToPath(new URL('../..', import.meta.url))
const outputs = ['apps/web/dist', 'apps/api/dist']

const rules = [
  { name: 'Supabase secret key', test: (text) => /sb_secret_[A-Za-z0-9_-]{8,}/.test(text) },
  {
    name: 'service_role JWT',
    test: (text) =>
      (text.match(/eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g) ?? []).some((jwt) => {
        try {
          const payload = JSON.parse(Buffer.from(jwt.split('.')[1], 'base64url').toString())
          return payload.role === 'service_role'
        } catch {
          return false
        }
      }),
  },
  { name: 'private key', test: (text) => /-----BEGIN [A-Z ]*PRIVATE KEY-----/.test(text) },
  // A path into template/ (bundled source, source-map entry or asset URL), not
  // the word "template" that Vue itself uses.
  {
    name: 'reference template path',
    test: (text) => /(^|[^A-Za-z0-9_-])template\/[A-Za-z0-9_.-]+/.test(text),
  },
]

function* files(dir) {
  for (const entry of readdirSync(dir)) {
    const path = join(dir, entry)
    if (statSync(path).isDirectory()) yield* files(path)
    else yield path
  }
}

const problems = []
for (const output of outputs) {
  const dir = join(root, output)
  if (!existsSync(dir)) {
    problems.push(`${output} is missing; run npm run build first`)
    continue
  }
  for (const file of files(dir)) {
    if (!/\.(js|mjs|css|html|json|map|txt)$/.test(file)) continue
    const text = readFileSync(file, 'utf8')
    for (const rule of rules) {
      if (rule.test(text)) problems.push(`${relative(root, file)}: ${rule.name}`)
    }
  }
}

if (problems.length) {
  console.error(`Build artifact check failed:\n  ${problems.join('\n  ')}`)
  process.exit(1)
}
console.log(`Build artifacts clean: ${outputs.join(', ')}`)
