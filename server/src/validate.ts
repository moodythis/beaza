import { fromB64 } from './util.ts';

export const MAX_BODY = 256 * 1024;
export const MAX_BATCH = 100;
/** Records one account may hold. A heavy user makes about 2,000 a year;
 * without a cap one account could fill the shared database. */
export const MAX_RECORDS_PER_ACCOUNT = 20_000;
export const MAX_BLOB_CHARS = 16 * 1024;
/** version + nonce + tag + one 64-byte padding block (see beaza_crypto). */
export const MIN_BLOB_BYTES = 1 + 24 + 16 + 64;
/** A locked 32-byte data key: version + nonce + key + tag. Records are
 * padded, but locked keys are not, so they are smaller than any record. */
export const SEALED_KEY_BYTES = 1 + 24 + 32 + 16;

/** Thrown for any problem that should become a JSON error response. */
export class HttpError extends Error {
  status: number;
  code: string;
  extra: Record<string, unknown>;

  constructor(status: number, code: string, extra: Record<string, unknown> = {}) {
    super(code);
    this.status = status;
    this.code = code;
    this.extra = extra;
  }
}

const bad = (code: string) => new HttpError(400, code);

export function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

export function checkEmail(value: unknown): string {
  if (typeof value !== 'string') throw bad('bad_email');
  const email = value.trim().toLowerCase();
  if (email.length > 254 || !/^[^\s@]{1,64}@[^\s@]{1,190}\.[^\s@]{2,}$/.test(email)) {
    throw bad('bad_email');
  }
  return email;
}

/** A 32-byte key sent as base64url (43 characters). */
export function checkKey(value: unknown, code: string): Uint8Array {
  const bytes = typeof value === 'string' ? fromB64(value) : null;
  if (!bytes || bytes.length !== 32) throw bad(code);
  return bytes;
}

function checkB64(value: unknown, minBytes: number, maxChars: number): string {
  const bytes = typeof value === 'string' ? fromB64(value) : null;
  if (!bytes || bytes.length < minBytes || (value as string).length > maxChars) {
    throw bad('bad_bundle');
  }
  return value as string;
}

function checkInt(value: unknown, min: number, max: number): number {
  if (typeof value !== 'number' || !Number.isInteger(value) || value < min || value > max) {
    throw bad('bad_bundle');
  }
  return value;
}

export type Bundle = {
  v: 1;
  keyId: string;
  recovery: string;
  password?: {
    salt: string;
    kdf: { alg: 'argon2id'; m: number; t: number; p: number };
    key: string;
  };
};

/**
 * Checks the shape of a key bundle and returns a clean copy. The server
 * cannot open it; this only stops a buggy phone from storing something that
 * no phone could use later. The Argon2id floor matches the phone's own.
 */
export function checkBundle(value: unknown): Bundle {
  if (!isObject(value) || value.v !== 1) throw bad('bad_bundle');
  const keyId = value.keyId;
  if (typeof keyId !== 'string' || !/^[0-9a-f]{32}$/.test(keyId)) throw bad('bad_bundle');
  const bundle: Bundle = { v: 1, keyId, recovery: checkB64(value.recovery, SEALED_KEY_BYTES, 400) };

  const password = value.password;
  if (password !== undefined) {
    if (!isObject(password) || !isObject(password.kdf)) throw bad('bad_bundle');
    const kdf = password.kdf;
    if (kdf.alg !== 'argon2id') throw bad('bad_bundle');
    bundle.password = {
      salt: checkB64(password.salt, 16, 64),
      kdf: {
        alg: 'argon2id',
        m: checkInt(kdf.m, 19456, 262144),
        t: checkInt(kdf.t, 2, 10),
        p: checkInt(kdf.p, 1, 4),
      },
      key: checkB64(password.key, SEALED_KEY_BYTES, 400),
    };
  }
  return bundle;
}

export type IncomingRecord = { collection: string; id: string; blob: string };

export function checkRecords(value: unknown): IncomingRecord[] {
  if (!Array.isArray(value) || value.length < 1 || value.length > MAX_BATCH) {
    throw bad('bad_records');
  }
  return value.map((item) => {
    if (!isObject(item)) throw bad('bad_records');
    const { collection, id, blob } = item;
    if (typeof collection !== 'string' || !/^[a-z][a-z_]{0,31}$/.test(collection)) {
      throw bad('bad_records');
    }
    if (typeof id !== 'string' || !/^[A-Za-z0-9_-]{1,64}$/.test(id)) throw bad('bad_records');
    if (typeof blob !== 'string' || blob.length > MAX_BLOB_CHARS) throw bad('bad_records');
    const bytes = fromB64(blob);
    if (!bytes || bytes.length < MIN_BLOB_BYTES) throw bad('bad_records');
    return { collection, id, blob };
  });
}
