// Applies supabase/spike/gd0-auth-spike.sql to the LOCAL database so the GĐ 0
// spike tests can be re-run. Refuses non-local hosts. Not a migration.
import { readFileSync } from 'node:fs';
import pg from 'pg';
import { localConfig } from './config.ts';

const sql = readFileSync(new URL('../../supabase/spike/gd0-auth-spike.sql', import.meta.url), 'utf8');
const db = new pg.Client({ connectionString: localConfig().databaseUrl });
await db.connect();
try {
  const { rows } = await db.query("select to_regnamespace('spike_private') is not null as present");
  if (rows[0].present) {
    console.log('spike_private already exists; nothing applied.');
  } else {
    await db.query(`begin; ${sql}; commit;`);
    console.log('Applied the GĐ 0 Auth spike schema to the local database.');
  }
} finally {
  await db.end();
}
