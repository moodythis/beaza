import type { D1Like, Env } from './d1.ts';
import {
  hmacSha256,
  randomBytes,
  safeEqual,
  sha256,
  toB64,
  toHex,
  utf8,
} from './util.ts';
import {
  checkBundle,
  checkEmail,
  checkKey,
  checkRecords,
  HttpError,
  isObject,
  MAX_BODY,
} from './validate.ts';
import type { Bundle } from './validate.ts';
import { legalPage, PRIVACY_VERSION, TERMS_VERSION } from './legal.ts';

const MINUTE = 60_000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;
const SESSION_LIFE = 60 * DAY;
const MAX_SESSIONS = 20;

/** The setting the phone uses when it makes a new account. */
const DEFAULT_KDF = { alg: 'argon2id', m: 19456, t: 2, p: 1 };

export type Options = {
  /** Milliseconds since 1970. Tests set it to move time. */
  now?: () => number;
  /** One line per request: route and status only, never a body or query. */
  log?: (line: string) => void;
};

type Ctx = {
  db: D1Like;
  request: Request;
  now: number;
  ip: string;
  pepper: () => Promise<Uint8Array>;
};

type UserRow = {
  id: string;
  auth_hash: string;
  recovery_auth_hash: string;
  bundle: string;
};

export async function handle(
  request: Request,
  env: Env,
  options: Options = {},
): Promise<Response> {
  const url = new URL(request.url);
  const route = `${request.method} ${url.pathname}`;
  if (route === 'GET /privacy' || route === 'GET /terms') {
    (options.log ?? console.log)(JSON.stringify({ route, status: 200 }));
    const kind = url.pathname === '/privacy' ? 'privacy' : 'terms';
    return new Response(legalPage(kind, env.PRIVACY_CONTACT), {
      headers: {
        'content-type': 'text/html; charset=utf-8',
        'cache-control': 'public, max-age=300',
        'x-content-type-options': 'nosniff',
        'content-security-policy': "default-src 'none'; style-src 'unsafe-inline'",
      },
    });
  }
  let response: Response;
  try {
    let cachedPepper: Uint8Array | undefined;
    const ctx: Ctx = {
      db: env.DB,
      request,
      now: (options.now ?? Date.now)(),
      ip: request.headers.get('cf-connecting-ip') ?? 'unknown',
      pepper: async () => (cachedPepper ??= await loadPepper(env.DB)),
    };
    response = json(200, await dispatch(route, url, ctx));
  } catch (error) {
    if (error instanceof HttpError) {
      response = json(error.status, { error: error.code, ...error.extra });
    } else {
      response = json(500, { error: 'server_error' });
      (options.log ?? console.log)(
        JSON.stringify({ route, error: error instanceof Error ? error.message : 'unknown' }),
      );
    }
  }
  (options.log ?? console.log)(JSON.stringify({ route, status: response.status }));
  return response;
}

async function dispatch(route: string, url: URL, ctx: Ctx): Promise<Record<string, unknown>> {
  switch (route) {
    case 'GET /v1/health':
      return { ok: true };
    case 'POST /v1/register':
      return register(ctx);
    case 'POST /v1/kdf':
      return kdf(ctx);
    case 'POST /v1/login':
      return login(ctx, 'login');
    case 'POST /v1/recover':
      return login(ctx, 'recover');
    case 'POST /v1/password':
      return changePassword(ctx);
    case 'POST /v1/recovery-key':
      return changeRecoveryKey(ctx);
    case 'POST /v1/records':
      return pushRecords(ctx);
    case 'GET /v1/records':
      return pullRecords(ctx, url);
    case 'POST /v1/logout':
      return logout(ctx);
    case 'GET /v1/account':
      return accountInfo(ctx);
    case 'POST /v1/account/delete':
      return deleteAccount(ctx);
    default:
      throw new HttpError(404, 'not_found');
  }
}

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json',
      'cache-control': 'no-store',
      'x-content-type-options': 'nosniff',
    },
  });
}

async function readJson(request: Request): Promise<Record<string, unknown>> {
  if (Number(request.headers.get('content-length') ?? 0) > MAX_BODY) {
    throw new HttpError(413, 'too_large');
  }
  const text = await request.text();
  if (text.length > MAX_BODY) throw new HttpError(413, 'too_large');
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    throw new HttpError(400, 'bad_json');
  }
  if (!isObject(value)) throw new HttpError(400, 'bad_json');
  return value;
}

// ---- secrets kept by the server itself ----

/** A random value made on first use and kept in the database. It keys the
 * hashes below, so the attempts table holds no emails or addresses. */
async function loadPepper(db: D1Like): Promise<Uint8Array> {
  const read = () =>
    db.prepare("SELECT value FROM meta WHERE key = 'pepper'").first<{ value: string }>();
  let row = await read();
  if (!row) {
    await db
      .prepare("INSERT OR IGNORE INTO meta (key, value) VALUES ('pepper', ?)")
      .bind(toHex(randomBytes(32)))
      .run();
    row = await read();
  }
  return utf8(row!.value);
}

async function keyedHash(ctx: Ctx, text: string): Promise<string> {
  return toHex(await hmacSha256(await ctx.pepper(), `key:${text}`)).slice(0, 32);
}

/** What the server stores to check a key: a hash that includes the user id,
 * so two users with the same key would still store different hashes. */
async function storedHash(label: 'auth' | 'recovery', userId: string, key: Uint8Array) {
  return toHex(await sha256(utf8(`beaza/v1/${label}/${userId}/`), key));
}

// ---- wrong-guess limits ----

async function assertNotLimited(ctx: Ctx, key: string, max: number, windowMs: number) {
  const row = await ctx.db
    .prepare('SELECT count, window_start FROM attempts WHERE key = ?')
    .bind(key)
    .first<{ count: number; window_start: number }>();
  if (row && ctx.now - row.window_start < windowMs && row.count >= max) {
    throw new HttpError(429, 'rate_limited', {
      retryAfterSeconds: Math.ceil((row.window_start + windowMs - ctx.now) / 1000),
    });
  }
}

async function recordAttempt(ctx: Ctx, key: string, windowMs: number) {
  await ctx.db
    .prepare(
      `INSERT INTO attempts (key, count, window_start) VALUES (?1, 1, ?2)
       ON CONFLICT (key) DO UPDATE SET
         count = CASE WHEN ?2 - window_start >= ?3 THEN 1 ELSE count + 1 END,
         window_start = CASE WHEN ?2 - window_start >= ?3 THEN ?2 ELSE window_start END`,
    )
    .bind(key, ctx.now, windowMs)
    .run();
}

// ---- sessions ----

async function createSession(ctx: Ctx, userId: string): Promise<string> {
  const token = toB64(randomBytes(32));
  const tokenHash = toHex(await sha256(utf8(token)));
  await ctx.db
    .prepare('INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, ?, ?)')
    .bind(tokenHash, userId, ctx.now, ctx.now + SESSION_LIFE)
    .run();
  // Keep the newest sessions only, and drop the expired ones.
  await ctx.db
    .prepare(
      `DELETE FROM sessions WHERE user_id = ?1 AND (expires_at <= ?2 OR token_hash NOT IN
         (SELECT token_hash FROM sessions WHERE user_id = ?1 ORDER BY created_at DESC LIMIT ?3))`,
    )
    .bind(userId, ctx.now, MAX_SESSIONS)
    .run();
  return token;
}

async function authenticate(ctx: Ctx): Promise<{ userId: string; tokenHash: string }> {
  const match = /^Bearer ([A-Za-z0-9_-]{43})$/.exec(ctx.request.headers.get('authorization') ?? '');
  if (!match) throw new HttpError(401, 'unauthorized');
  const tokenHash = toHex(await sha256(utf8(match[1])));
  const row = await ctx.db
    .prepare('SELECT user_id, expires_at FROM sessions WHERE token_hash = ?')
    .bind(tokenHash)
    .first<{ user_id: string; expires_at: number }>();
  if (!row || row.expires_at <= ctx.now) throw new HttpError(401, 'unauthorized');
  return { userId: row.user_id, tokenHash };
}

// ---- accounts ----

async function register(ctx: Ctx) {
  const ipKey = `register:${await keyedHash(ctx, ctx.ip)}`;
  await assertNotLimited(ctx, ipKey, 20, HOUR);
  await recordAttempt(ctx, ipKey, HOUR);

  const body = await readJson(ctx.request);
  const email = checkEmail(body.email);
  const authKey = checkKey(body.authKey, 'bad_auth_key');
  const recoveryAuthKey = checkKey(body.recoveryAuthKey, 'bad_recovery_auth_key');
  const bundle = checkBundle(body.bundle);
  if (!bundle.password) throw new HttpError(400, 'bad_bundle');
  const consent = checkConsent(body.consent);

  const taken = await ctx.db.prepare('SELECT id FROM users WHERE email = ?').bind(email).first();
  if (taken) throw new HttpError(409, 'email_taken');

  const id = toHex(randomBytes(16));
  try {
    await ctx.db
      .prepare(
        `INSERT INTO users (id, email, auth_hash, recovery_auth_hash, bundle, seq, created_at,
                            privacy_version, terms_version, consent_at)
         VALUES (?, ?, ?, ?, ?, 0, ?, ?, ?, ?)`,
      )
      .bind(
        id,
        email,
        await storedHash('auth', id, authKey),
        await storedHash('recovery', id, recoveryAuthKey),
        JSON.stringify(bundle),
        ctx.now,
        consent.privacy,
        consent.terms,
        ctx.now,
      )
      .run();
  } catch (error) {
    if (/UNIQUE constraint failed/i.test(String(error))) throw new HttpError(409, 'email_taken');
    throw error;
  }
  return { token: await createSession(ctx, id) };
}

/** Sign-up needs three separate, explicit statements: consent to the current
 * privacy notice, acceptance of the current terms, and being 18 or over.
 * Refusing anything else keeps the record meaningful (GDPR Art. 7(1)). */
function checkConsent(value: unknown): { privacy: string; terms: string } {
  if (
    !isObject(value) ||
    value.adult !== true ||
    typeof value.privacy !== 'string' ||
    typeof value.terms !== 'string'
  ) {
    throw new HttpError(400, 'consent_required');
  }
  if (value.privacy !== PRIVACY_VERSION || value.terms !== TERMS_VERSION) {
    throw new HttpError(400, 'documents_outdated', {
      privacy: PRIVACY_VERSION,
      terms: TERMS_VERSION,
    });
  }
  return { privacy: value.privacy, terms: value.terms };
}

/** Tells a phone which salt and Argon2id setting to use for an email. For an
 * email with no account it returns a made-up but always the same answer, so
 * this call does not reveal who has an account. */
async function kdf(ctx: Ctx) {
  const email = checkEmail((await readJson(ctx.request)).email);
  const row = await ctx.db
    .prepare('SELECT bundle FROM users WHERE email = ?')
    .bind(email)
    .first<{ bundle: string }>();
  const stored = row ? (JSON.parse(row.bundle) as Bundle).password : undefined;
  if (stored) return { salt: stored.salt, kdf: stored.kdf };
  const fake = (await hmacSha256(await ctx.pepper(), `kdf-salt:${email}`)).slice(0, 16);
  return { salt: toB64(fake), kdf: DEFAULT_KDF };
}

/** Log in with the password key, or recover with the recovery key. Both
 * return a session and the key bundle, which only the right key can open. */
async function login(ctx: Ctx, kind: 'login' | 'recover') {
  const [perEmail, perIp, windowMs] = kind === 'login' ? [10, 40, 15 * MINUTE] : [5, 20, HOUR];
  const body = await readJson(ctx.request);
  const email = checkEmail(body.email);
  const key = checkKey(
    kind === 'login' ? body.authKey : body.recoveryAuthKey,
    kind === 'login' ? 'bad_auth_key' : 'bad_recovery_auth_key',
  );

  const emailKey = `${kind}:email:${await keyedHash(ctx, email)}`;
  const ipKey = `${kind}:ip:${await keyedHash(ctx, ctx.ip)}`;
  await assertNotLimited(ctx, emailKey, perEmail, windowMs);
  await assertNotLimited(ctx, ipKey, perIp, windowMs);

  const user = await ctx.db
    .prepare('SELECT id, auth_hash, recovery_auth_hash, bundle FROM users WHERE email = ?')
    .bind(email)
    .first<UserRow>();
  // Do the same work for an unknown email so timing does not give it away.
  const label = kind === 'login' ? 'auth' : 'recovery';
  const computed = await storedHash(label, user?.id ?? '0'.repeat(32), key);
  const expected = user ? (kind === 'login' ? user.auth_hash : user.recovery_auth_hash) : '';
  if (!user || !safeEqual(computed, expected)) {
    await recordAttempt(ctx, emailKey, windowMs);
    await recordAttempt(ctx, ipKey, windowMs);
    throw new HttpError(401, 'invalid_credentials');
  }
  await ctx.db.prepare('DELETE FROM attempts WHERE key = ?').bind(emailKey).run();
  return { token: await createSession(ctx, user.id), bundle: JSON.parse(user.bundle) };
}

/** The new bundle must lock the same data key (same keyId): swapping the data
 * key would leave every stored record unreadable. */
async function sameDataKey(ctx: Ctx, userId: string, bundle: Bundle) {
  const row = await ctx.db
    .prepare('SELECT bundle FROM users WHERE id = ?')
    .bind(userId)
    .first<{ bundle: string }>();
  if (!row || (JSON.parse(row.bundle) as Bundle).keyId !== bundle.keyId) {
    throw new HttpError(400, 'key_changed');
  }
}

async function changePassword(ctx: Ctx) {
  const { userId, tokenHash } = await authenticate(ctx);
  const body = await readJson(ctx.request);
  const authKey = checkKey(body.authKey, 'bad_auth_key');
  const bundle = checkBundle(body.bundle);
  if (!bundle.password) throw new HttpError(400, 'bad_bundle');
  await sameDataKey(ctx, userId, bundle);

  await ctx.db.batch([
    ctx.db
      .prepare('UPDATE users SET auth_hash = ?, bundle = ? WHERE id = ?')
      .bind(await storedHash('auth', userId, authKey), JSON.stringify(bundle), userId),
    // Every other phone has to log in again with the new password.
    ctx.db
      .prepare('DELETE FROM sessions WHERE user_id = ? AND token_hash != ?')
      .bind(userId, tokenHash),
  ]);
  return { ok: true };
}

async function changeRecoveryKey(ctx: Ctx) {
  const { userId } = await authenticate(ctx);
  const body = await readJson(ctx.request);
  const recoveryAuthKey = checkKey(body.recoveryAuthKey, 'bad_recovery_auth_key');
  const bundle = checkBundle(body.bundle);
  await sameDataKey(ctx, userId, bundle);
  await ctx.db
    .prepare('UPDATE users SET recovery_auth_hash = ?, bundle = ? WHERE id = ?')
    .bind(await storedHash('recovery', userId, recoveryAuthKey), JSON.stringify(bundle), userId)
    .run();
  return { ok: true };
}

/** Everything the server holds about the person that can be shown in
 * readable form (GDPR Art. 15; Bahrain PDPL right of access). The records
 * themselves are encrypted; only their number is meaningful here. */
async function accountInfo(ctx: Ctx) {
  const { userId } = await authenticate(ctx);
  const user = await ctx.db
    .prepare(
      'SELECT email, created_at, privacy_version, terms_version, consent_at FROM users WHERE id = ?',
    )
    .bind(userId)
    .first<{
      email: string;
      created_at: number;
      privacy_version: string | null;
      terms_version: string | null;
      consent_at: number | null;
    }>();
  if (!user) throw new HttpError(401, 'unauthorized');
  const records = await ctx.db
    .prepare('SELECT COUNT(*) AS n FROM records WHERE user_id = ?')
    .bind(userId)
    .first<{ n: number }>();
  const sessions = await ctx.db
    .prepare('SELECT COUNT(*) AS n FROM sessions WHERE user_id = ? AND expires_at > ?')
    .bind(userId, ctx.now)
    .first<{ n: number }>();
  return {
    email: user.email,
    createdAt: user.created_at,
    consent: { privacy: user.privacy_version, terms: user.terms_version, at: user.consent_at },
    encryptedRecords: records?.n ?? 0,
    activeSessions: sessions?.n ?? 0,
    current: { privacy: PRIVACY_VERSION, terms: TERMS_VERSION },
  };
}

async function logout(ctx: Ctx) {
  const { tokenHash } = await authenticate(ctx);
  await ctx.db.prepare('DELETE FROM sessions WHERE token_hash = ?').bind(tokenHash).run();
  return { ok: true };
}

async function deleteAccount(ctx: Ctx) {
  const { userId } = await authenticate(ctx);
  const authKey = checkKey((await readJson(ctx.request)).authKey, 'bad_auth_key');
  const user = await ctx.db
    .prepare('SELECT auth_hash FROM users WHERE id = ?')
    .bind(userId)
    .first<{ auth_hash: string }>();
  if (!user || !safeEqual(await storedHash('auth', userId, authKey), user.auth_hash)) {
    throw new HttpError(401, 'invalid_credentials');
  }
  await ctx.db.batch([
    ctx.db.prepare('DELETE FROM records WHERE user_id = ?').bind(userId),
    ctx.db.prepare('DELETE FROM sessions WHERE user_id = ?').bind(userId),
    ctx.db.prepare('DELETE FROM users WHERE id = ?').bind(userId),
  ]);
  return { ok: true };
}

// ---- records ----

/** Stores or replaces records. Each gets the next seq number. The numbers are
 * given inside one transaction, so a phone that pulls "after seq N" can never
 * miss a record that was committed later with a smaller number. */
async function pushRecords(ctx: Ctx) {
  const { userId } = await authenticate(ctx);
  const records = checkRecords((await readJson(ctx.request)).records);
  const n = records.length;
  await ctx.db.batch([
    ctx.db.prepare('UPDATE users SET seq = seq + ? WHERE id = ?').bind(n, userId),
    ...records.map((r, i) =>
      ctx.db
        .prepare(
          `INSERT INTO records (user_id, collection, id, blob, seq)
           VALUES (?, ?, ?, ?, (SELECT seq FROM users WHERE id = ?) - ? + ?)
           ON CONFLICT (user_id, collection, id)
           DO UPDATE SET blob = excluded.blob, seq = excluded.seq`,
        )
        .bind(userId, r.collection, r.id, r.blob, userId, n, i + 1),
    ),
  ]);
  const row = await ctx.db
    .prepare('SELECT seq FROM users WHERE id = ?')
    .bind(userId)
    .first<{ seq: number }>();
  return { seq: row?.seq ?? 0 };
}

async function pullRecords(ctx: Ctx, url: URL) {
  const { userId } = await authenticate(ctx);
  const since = Number(url.searchParams.get('since') ?? 0);
  const limit = Number(url.searchParams.get('limit') ?? 200);
  if (!Number.isInteger(since) || since < 0 || !Number.isInteger(limit) || limit < 1) {
    throw new HttpError(400, 'bad_query');
  }
  const take = Math.min(limit, 500);
  const { results } = await ctx.db
    .prepare(
      `SELECT collection, id, blob, seq FROM records
       WHERE user_id = ? AND seq > ? ORDER BY seq ASC LIMIT ?`,
    )
    .bind(userId, since, take + 1)
    .all<{ collection: string; id: string; blob: string; seq: number }>();
  const records = results.slice(0, take);
  return {
    records,
    nextSince: records.length > 0 ? records[records.length - 1].seq : since,
    more: results.length > take,
  };
}
