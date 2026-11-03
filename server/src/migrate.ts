// TEMPORARY. One-time copy of every account from the old database to the
// new EU one, then this file and the OLD_DB binding are removed.
//
// It reads rows from OLD_DB and writes them to DB in the same Worker, so no
// record ever passes through a person or a log. It answers only with counts
// and a SHA-256 of each table in both databases, to show nothing changed.
import type { D1Like, D1Statement, Env } from './d1.ts';
import { sha256, toHex, utf8 } from './util.ts';

/** Secret part of the path; the repository is private and the route goes
 * away after the copy. */
export const MIGRATE_PATH = '/__migrate/1f7f89b2de90d3cb30f3af60737107fbd2b79fa91b0d88af';

const TABLES: { name: string; columns: string[]; order: string }[] = [
  {
    name: 'users',
    columns: [
      'id', 'email', 'auth_hash', 'recovery_auth_hash', 'bundle', 'seq',
      'created_at', 'privacy_version', 'terms_version', 'consent_at',
    ],
    order: 'id',
  },
  {
    name: 'sessions',
    columns: ['token_hash', 'user_id', 'created_at', 'expires_at'],
    order: 'token_hash',
  },
  {
    name: 'records',
    columns: ['user_id', 'collection', 'id', 'blob', 'seq'],
    order: 'user_id, collection, id',
  },
  { name: 'meta', columns: ['key', 'value'], order: 'key' },
];

type Row = Record<string, string | number | null>;

async function rows(db: D1Like, t: (typeof TABLES)[number]): Promise<Row[]> {
  const { results } = await db
    .prepare(`SELECT ${t.columns.join(', ')} FROM ${t.name} ORDER BY ${t.order}`)
    .all<Row>();
  return results;
}

async function digest(list: Row[], columns: string[]): Promise<string> {
  const text = list.map((r) => JSON.stringify(columns.map((c) => r[c] ?? null))).join('\n');
  return toHex(await sha256(utf8(text)));
}

export async function migrate(env: Env & { OLD_DB?: D1Like }) {
  const from = env.OLD_DB;
  if (!from) return { error: 'no_old_db' };
  const report: Record<string, unknown> = {};
  for (const t of TABLES) {
    const list = await rows(from, t);
    const marks = t.columns.map(() => '?').join(', ');
    const statements: D1Statement[] = list.map((r) =>
      env.DB.prepare(
        `INSERT OR REPLACE INTO ${t.name} (${t.columns.join(', ')}) VALUES (${marks})`,
      ).bind(...t.columns.map((c) => r[c] ?? null)),
    );
    for (let i = 0; i < statements.length; i += 50) {
      await env.DB.batch(statements.slice(i, i + 50));
    }
    const copied = await rows(env.DB, t);
    const before = await digest(list, t.columns);
    const after = await digest(copied, t.columns);
    report[t.name] = { rows: list.length, copied: copied.length, same: before === after };
  }
  return report;
}
