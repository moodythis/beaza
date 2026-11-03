import { readFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
import { handle } from '../src/app.ts';
import type { D1Like, D1Statement, Value } from '../src/d1.ts';
import { PRIVACY_VERSION, TERMS_VERSION } from '../src/legal.ts';
import { randomBytes, toB64 } from '../src/util.ts';

// ---- a D1 look-alike on Node's built-in SQLite ----

class Statement implements D1Statement {
  db: DatabaseSync;
  sql: string;
  args: Value[];

  constructor(db: DatabaseSync, sql: string, args: Value[] = []) {
    this.db = db;
    this.sql = sql;
    this.args = args;
  }
  bind(...values: Value[]) {
    return new Statement(this.db, this.sql, values);
  }
  async first<T>() {
    return (this.db.prepare(this.sql).get(...this.args) as T | undefined) ?? null;
  }
  async all<T>() {
    return { results: this.db.prepare(this.sql).all(...this.args) as T[] };
  }
  async run() {
    return this.db.prepare(this.sql).run(...this.args);
  }
}

export class TestD1 implements D1Like {
  db = new DatabaseSync(':memory:');

  constructor() {
    for (const file of ['0001_init.sql', '0002_consent.sql', '0003_google.sql', '0004_devices.sql']) {
      this.db.exec(readFileSync(new URL(`../migrations/${file}`, import.meta.url), 'utf8'));
    }
  }
  prepare(sql: string) {
    return new Statement(this.db, sql);
  }
  async batch(statements: D1Statement[]) {
    this.db.exec('BEGIN');
    try {
      const out = [];
      for (const s of statements) out.push(await s.run());
      this.db.exec('COMMIT');
      return out;
    } catch (error) {
      this.db.exec('ROLLBACK');
      throw error;
    }
  }
  /** Everything stored, as one string, to check what is (not) in it. */
  dump(): string {
    const tables = ['users', 'sessions', 'records', 'attempts', 'meta'];
    return tables
      .map((t) => JSON.stringify(this.db.prepare(`SELECT * FROM ${t}`).all()))
      .join('\n');
  }
}

// ---- a pretend phone ----

export class Server {
  d1 = new TestD1();
  time = Date.UTC(2026, 10, 3, 12, 0, 0);
  /** Set to turn on Google sign-in (see test/google.test.ts). */
  googleClientId?: string;
  googleKeys?: () => Promise<JsonWebKey[]>;

  advance(ms: number) {
    this.time += ms;
  }

  async call(
    method: string,
    path: string,
    body?: unknown,
    token?: string,
    ip = '203.0.113.7',
  ): Promise<{ status: number; body: any; headers: Headers }> {
    const request = new Request(`https://sync.example${path}`, {
      method,
      headers: {
        'cf-connecting-ip': ip,
        ...(token ? { authorization: `Bearer ${token}` } : {}),
        ...(body === undefined ? {} : { 'content-type': 'application/json' }),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const response = await handle(
      request,
      { DB: this.d1, GOOGLE_CLIENT_ID: this.googleClientId },
      { now: () => this.time, log: () => {}, googleKeys: this.googleKeys },
    );
    return { status: response.status, body: await response.json(), headers: response.headers };
  }
}

/** What the phone would send for an email account. The server cannot tell
 * these random bytes from real encrypted keys, which is the point. */
export function newAccountFields(email = 'user@example.com') {
  const keyId = Array.from(randomBytes(16), (b) => b.toString(16).padStart(2, '0')).join('');
  const authKey = toB64(randomBytes(32));
  const recoveryAuthKey = toB64(randomBytes(32));
  const bundle = {
    v: 1,
    keyId,
    recovery: toB64(randomBytes(73)),
    password: {
      salt: toB64(randomBytes(16)),
      kdf: { alg: 'argon2id', m: 19456, t: 2, p: 1 },
      key: toB64(randomBytes(73)),
    },
  };
  const consent = { privacy: PRIVACY_VERSION, terms: TERMS_VERSION, adult: true };
  return { email, authKey, recoveryAuthKey, bundle, consent };
}

export type Account = ReturnType<typeof newAccountFields>;

export async function signUp(server: Server, email = 'user@example.com') {
  const account = newAccountFields(email);
  const res = await server.call('POST', '/v1/register', account);
  if (res.status !== 200) throw new Error(`sign-up failed: ${JSON.stringify(res.body)}`);
  return { account, token: res.body.token as string };
}

export function sealedLike(size = 105 + 64) {
  return toB64(randomBytes(size));
}
