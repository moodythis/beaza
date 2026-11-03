// Checks a Google ID token (Sign in with Google on the phone) without any
// library: the token is a JWT signed by Google with RS256, and Google
// publishes its public keys. The server keeps only the stable account id
// ("sub") and the verified email.

import { fromB64, utf8 } from './util.ts';
import { HttpError } from './validate.ts';

export type GoogleIdentity = { sub: string; email: string };

/** Fetches Google's current public keys (JWK set). */
export type GoogleKeys = () => Promise<JsonWebKey[]>;

const CERTS_URL = 'https://www.googleapis.com/oauth2/v3/certs';
const ISSUERS = new Set(['accounts.google.com', 'https://accounts.google.com']);
/** Phone and server clocks differ a little. */
const SKEW_MS = 5 * 60_000;

let cached: { keys: JsonWebKey[]; until: number } | undefined;

/** Google's keys, cached for as long as Google's response allows (at most a
 * day). Google rotates them every few days and publishes new ones early. */
export const fetchGoogleKeys: GoogleKeys = async () => {
  const now = Date.now();
  if (cached && cached.until > now) return cached.keys;
  const res = await fetch(CERTS_URL);
  if (!res.ok) throw new HttpError(503, 'google_unavailable');
  const body = (await res.json()) as { keys?: JsonWebKey[] };
  const maxAge = Number(/max-age=(\d+)/.exec(res.headers.get('cache-control') ?? '')?.[1] ?? 3600);
  cached = { keys: body.keys ?? [], until: now + Math.min(maxAge, 86_400) * 1000 };
  return cached.keys;
};

function part(text: string | undefined): Record<string, unknown> {
  const bytes = text === undefined ? null : fromB64(text);
  if (!bytes) throw new HttpError(400, 'bad_id_token');
  try {
    const value = JSON.parse(new TextDecoder().decode(bytes));
    if (value && typeof value === 'object' && !Array.isArray(value)) return value;
  } catch {
    // falls through
  }
  throw new HttpError(400, 'bad_id_token');
}

/**
 * Returns who the token belongs to, or throws:
 * - 503 `google_disabled` when no client id is configured,
 * - 400 `bad_id_token` when it is not a JWT,
 * - 401 `invalid_id_token` when the signature, issuer, audience, expiry or
 *   email verification is wrong.
 */
export async function verifyGoogleIdToken(
  token: unknown,
  clientId: string | undefined,
  now: number,
  keys: GoogleKeys = fetchGoogleKeys,
): Promise<GoogleIdentity> {
  if (!clientId) throw new HttpError(503, 'google_disabled');
  if (typeof token !== 'string' || token.length > 4096) throw new HttpError(400, 'bad_id_token');
  const [h, p, s, extra] = token.split('.');
  if (extra !== undefined || !h || !p || !s) throw new HttpError(400, 'bad_id_token');
  const header = part(h);
  const payload = part(p);
  const signature = fromB64(s);
  if (!signature || header.alg !== 'RS256' || typeof header.kid !== 'string') {
    throw new HttpError(401, 'invalid_id_token');
  }

  const jwk = (await keys()).find((k) => (k as { kid?: string }).kid === header.kid);
  if (!jwk) throw new HttpError(401, 'invalid_id_token');
  const key = await crypto.subtle.importKey(
    'jwk',
    { kty: jwk.kty, n: jwk.n, e: jwk.e, alg: 'RS256', ext: true },
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['verify'],
  );
  const ok = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, signature, utf8(`${h}.${p}`));
  if (!ok) throw new HttpError(401, 'invalid_id_token');

  const aud = payload.aud;
  const audiences = Array.isArray(aud) ? aud : [aud];
  const exp = typeof payload.exp === 'number' ? payload.exp * 1000 : 0;
  const iat = typeof payload.iat === 'number' ? payload.iat * 1000 : Infinity;
  const verified = payload.email_verified === true || payload.email_verified === 'true';
  if (
    !ISSUERS.has(String(payload.iss)) ||
    !audiences.includes(clientId) ||
    exp + SKEW_MS < now ||
    iat - SKEW_MS > now ||
    !verified ||
    typeof payload.sub !== 'string' ||
    payload.sub.length === 0 ||
    payload.sub.length > 255 ||
    typeof payload.email !== 'string'
  ) {
    throw new HttpError(401, 'invalid_id_token');
  }
  return { sub: payload.sub, email: payload.email.trim().toLowerCase() };
}
