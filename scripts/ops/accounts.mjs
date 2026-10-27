// Operations tool for accounts that the application must not manage (AUTH-06):
// creating Admin accounts, changing a type to/from Admin, enabling/disabling an
// Admin and issuing an Admin a temporary password. Every change is audited with
// source "ops" and the operator's name; no password or token is logged.
//
// Credentials come from the environment, never from Git:
//   SUPABASE_URL          project URL (local or the environment being operated)
//   SUPABASE_SECRET_KEY   backend secret key of that project
//   MLEDU_OPERATOR        person running the tool (recorded in audit)
//
// Usage:
//   node scripts/ops/accounts.mjs create --email a@b.c --name "Họ tên" --type admin
//   node scripts/ops/accounts.mjs temp-password --account <uuid>
//   node scripts/ops/accounts.mjs set --account <uuid> [--type admin|receptionist|user] [--enabled true|false]
import { randomInt } from 'node:crypto'
import { parseArgs } from 'node:util'

const { SUPABASE_URL: url, SUPABASE_SECRET_KEY: key, MLEDU_OPERATOR: operator } = process.env
if (!url || !key || !operator?.trim()) {
  console.error('Set SUPABASE_URL, SUPABASE_SECRET_KEY and MLEDU_OPERATOR.')
  process.exit(2)
}

const [command, ...rest] = process.argv.slice(2)
const { values } = parseArgs({
  args: rest,
  options: {
    email: { type: 'string' },
    name: { type: 'string' },
    type: { type: 'string' },
    account: { type: 'string' },
    enabled: { type: 'string' },
  },
})

const headers = {
  apikey: key,
  Authorization: `Bearer ${key}`,
  'Content-Type': 'application/json',
}

async function rpc(name, args) {
  const response = await fetch(`${url}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: { ...headers, 'Content-Profile': 'api' },
    body: JSON.stringify(args),
  })
  const body = await response.json().catch(() => null)
  if (!response.ok) throw new Error(`${name}: ${response.status} ${body?.message ?? ''}`)
  return body
}

async function authAdmin(method, path, body) {
  const response = await fetch(`${url}/auth/v1/admin${path}`, {
    method,
    headers,
    body: JSON.stringify(body),
  })
  if (!response.ok) {
    const error = await response.json().catch(() => null)
    throw new Error(`Auth ${path}: ${response.status} ${error?.error_code ?? ''}`)
  }
}

const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789'
const temporaryPassword = () =>
  Array.from({ length: 12 }, () => ALPHABET[randomInt(ALPHABET.length)]).join('')

switch (command) {
  case 'create': {
    const [prepared] = await rpc('ops_prepare_account_create', {
      p_operator: operator,
      p_email: values.email,
      p_full_name: values.name,
      p_account_type: values.type ?? 'admin',
    })
    const password = temporaryPassword()
    await authAdmin('POST', '/users', {
      id: prepared.account_id,
      email: values.email.trim().toLowerCase(),
      password,
      email_confirm: true,
      app_metadata: { mledu_command: prepared.command_id },
    })
    console.log(`Created account ${prepared.account_id}.`)
    console.log(`Temporary password (shown once, must be changed at first sign-in): ${password}`)
    break
  }
  case 'temp-password': {
    const commandId = await rpc('ops_prepare_temporary_password', {
      p_operator: operator,
      p_account_id: values.account,
    })
    const password = temporaryPassword()
    await authAdmin('PUT', `/users/${encodeURIComponent(values.account)}`, {
      password,
      app_metadata: { mledu_command: commandId },
    })
    console.log(`Temporary password (shown once): ${password}`)
    break
  }
  case 'set': {
    const account = await rpc('ops_set_account', {
      p_operator: operator,
      p_account_id: values.account,
      p_account_type: values.type ?? null,
      p_enabled: values.enabled === undefined ? null : values.enabled === 'true',
    })
    console.log(`${account.email}: ${account.accountType}, ${account.status}`)
    break
  }
  default:
    console.error('Commands: create | temp-password | set (see the header of this file).')
    process.exit(2)
}
