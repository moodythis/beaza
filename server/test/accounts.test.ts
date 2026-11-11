import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { randomBytes, toB64 } from '../src/util.ts';
import { newAccountFields, Server, signUp } from './harness.ts';

const MINUTE = 60_000;
const DAY = 24 * 60 * MINUTE;

describe('health and basics', () => {
  it('answers a health check', async () => {
    const s = new Server();
    const res = await s.call('GET', '/v1/health');
    assert.equal(res.status, 200);
    assert.deepEqual(res.body, { ok: true });
  });

  it('never caches and has no CORS headers (the app is not a web page)', async () => {
    const res = await new Server().call('GET', '/v1/health');
    assert.equal(res.headers.get('cache-control'), 'no-store');
    assert.equal(res.headers.get('access-control-allow-origin'), null);
  });

  it('unknown routes are 404', async () => {
    const res = await new Server().call('GET', '/v1/nothing');
    assert.equal(res.status, 404);
  });

  it('refuses a huge body', async () => {
    const s = new Server();
    const res = await s.call('POST', '/v1/register', { email: 'a@b.co', pad: 'x'.repeat(300_000) });
    assert.equal(res.status, 413);
  });

  it('refuses bodies that are not a JSON object', async () => {
    const s = new Server();
    const res = await s.call('POST', '/v1/kdf', [1, 2, 3]);
    assert.equal(res.status, 400);
    assert.equal(res.body.error, 'bad_json');
  });
});

describe('register', () => {
  it('creates an account and returns a session', async () => {
    const s = new Server();
    const res = await s.call('POST', '/v1/register', newAccountFields());
    assert.equal(res.status, 200);
    assert.match(res.body.token, /^[A-Za-z0-9_-]{43}$/);
  });

  it('the same email twice is refused, whatever the letter case', async () => {
    const s = new Server();
    await signUp(s, 'Sara@Example.com');
    const again = await s.call('POST', '/v1/register', newAccountFields('  sara@example.COM '));
    assert.equal(again.status, 409);
    assert.equal(again.body.error, 'email_taken');
  });

  it('bad email, bad keys and bad bundles are refused', async () => {
    const s = new Server();
    const ok = newAccountFields();
    const cases: [string, object][] = [
      ['bad_email', { ...ok, email: 'not-an-email' }],
      ['bad_auth_key', { ...ok, authKey: 'short' }],
      ['bad_auth_key', { ...ok, authKey: toB64(randomBytes(31)) }],
      ['bad_recovery_auth_key', { ...ok, recoveryAuthKey: 12 }],
      ['bad_bundle', { ...ok, bundle: { ...ok.bundle, v: 2 } }],
      ['bad_bundle', { ...ok, bundle: { ...ok.bundle, keyId: 'zz' } }],
      ['bad_bundle', { ...ok, bundle: { ...ok.bundle, password: undefined } }],
    ];
    for (const [code, body] of cases) {
      const res = await s.call('POST', '/v1/register', body);
      assert.equal(res.status, 400, code);
      assert.equal(res.body.error, code);
    }
  });

  it('a locked data key is 73 bytes; anything shorter is refused', async () => {
    const s = new Server();
    const ok = newAccountFields();
    const short = { ...ok, bundle: { ...ok.bundle, recovery: toB64(randomBytes(72)) } };
    assert.equal((await s.call('POST', '/v1/register', short)).body.error, 'bad_bundle');
    assert.equal((await s.call('POST', '/v1/register', ok)).status, 200);
  });

  it('a weak Argon2id setting in the bundle is refused', async () => {
    const s = new Server();
    const ok = newAccountFields();
    const weak = { ...ok, bundle: { ...ok.bundle, password: { ...ok.bundle.password, kdf: { alg: 'argon2id', m: 8, t: 1, p: 1 } } } };
    const res = await s.call('POST', '/v1/register', weak);
    assert.equal(res.body.error, 'bad_bundle');
  });
});

describe('kdf (salt and setting for log-in)', () => {
  it('returns the real salt and setting of an account', async () => {
    const s = new Server();
    const { account } = await signUp(s);
    const res = await s.call('POST', '/v1/kdf', { email: 'USER@example.com' });
    assert.equal(res.body.salt, account.bundle.password.salt);
    assert.deepEqual(res.body.kdf, account.bundle.password.kdf);
  });

  it('an unknown email gets a steady made-up answer of the same shape', async () => {
    const s = new Server();
    const real = await signUp(s);
    const a = await s.call('POST', '/v1/kdf', { email: 'nobody@example.com' });
    const b = await s.call('POST', '/v1/kdf', { email: 'nobody@example.com' });
    const other = await s.call('POST', '/v1/kdf', { email: 'someone@example.com' });
    assert.equal(a.status, 200);
    assert.deepEqual(a.body, b.body);
    assert.notEqual(a.body.salt, other.body.salt);
    assert.deepEqual(Object.keys(a.body).sort(), ['kdf', 'salt']);
    assert.equal(a.body.salt.length, real.account.bundle.password.salt.length);
  });
});

describe('log in', () => {
  it('right key: session and the key bundle', async () => {
    const s = new Server();
    const { account } = await signUp(s);
    const res = await s.call('POST', '/v1/login', { email: account.email, authKey: account.authKey });
    assert.equal(res.status, 200);
    assert.deepEqual(res.body.bundle, account.bundle);
    const records = await s.call('GET', '/v1/records', undefined, res.body.token);
    assert.equal(records.status, 200);
  });

  it('wrong key and unknown email give the same answer', async () => {
    const s = new Server();
    const { account } = await signUp(s);
    const wrong = await s.call('POST', '/v1/login', { email: account.email, authKey: toB64(randomBytes(32)) });
    const unknown = await s.call('POST', '/v1/login', { email: 'nobody@example.com', authKey: account.authKey });
    assert.equal(wrong.status, 401);
    assert.deepEqual(wrong.body, unknown.body);
    assert.equal(wrong.body.error, 'invalid_credentials');
  });

  it('the recovery key cannot be used as the password key, or the reverse', async () => {
    const s = new Server();
    const { account } = await signUp(s);
    const asLogin = await s.call('POST', '/v1/login', { email: account.email, authKey: account.recoveryAuthKey });
    const asRecovery = await s.call('POST', '/v1/recover', { email: account.email, recoveryAuthKey: account.authKey });
    assert.equal(asLogin.status, 401);
    assert.equal(asRecovery.status, 401);
  });

  it('stops after 10 wrong tries, even for the right key, and opens again later', async () => {
    const s = new Server();
    const { account } = await signUp(s);
    const wrong = { email: account.email, authKey: toB64(randomBytes(32)) };
    for (let i = 0; i < 10; i++) {
      assert.equal((await s.call('POST', '/v1/login', wrong)).status, 401);
    }
    const blocked = await s.call('POST', '/v1/login', { email: account.email, authKey: account.authKey });
    assert.equal(blocked.status, 429);
    assert.equal(blocked.body.error, 'rate_limited');
    assert.ok(blocked.body.retryAfterSeconds > 0 && blocked.body.retryAfterSeconds <= 900);

    s.advance(16 * MINUTE);
    const later = await s.call('POST', '/v1/login', { email: account.email, authKey: account.authKey });
    assert.equal(later.status, 200);
  });

  it('a right log-in clears the wrong-try count', async () => {
    const s = new Server();
    const { account } = await signUp(s);
    const wrong = { email: account.email, authKey: toB64(randomBytes(32)) };
    for (let i = 0; i < 9; i++) await s.call('POST', '/v1/login', wrong);
    assert.equal((await s.call('POST', '/v1/login', { email: account.email, authKey: account.authKey })).status, 200);
    for (let i = 0; i < 9; i++) assert.equal((await s.call('POST', '/v1/login', wrong)).status, 401);
  });

  it('one address guessing at many accounts is stopped too', async () => {
    const s = new Server();
    let last = 0;
    for (let i = 0; i < 41; i++) {
      const res = await s.call('POST', '/v1/login', { email: `u${i}@example.com`, authKey: toB64(randomBytes(32)) }, undefined, '198.51.100.9');
      last = res.status;
    }
    assert.equal(last, 429);
    // Another address is not affected.
    const other = await s.call('POST', '/v1/login', { email: 'u1@example.com', authKey: toB64(randomBytes(32)) }, undefined, '198.51.100.10');
    assert.equal(other.status, 401);
  });
});

describe('recover (forgot the password)', () => {
  it('the recovery key logs in and returns the bundle', async () => {
    const s = new Server();
    const { account } = await signUp(s);
    const res = await s.call('POST', '/v1/recover', { email: account.email, recoveryAuthKey: account.recoveryAuthKey });
    assert.equal(res.status, 200);
    assert.deepEqual(res.body.bundle, account.bundle);
  });

  it('allows only 5 wrong tries an hour', async () => {
    const s = new Server();
    const { account } = await signUp(s);
    const wrong = { email: account.email, recoveryAuthKey: toB64(randomBytes(32)) };
    for (let i = 0; i < 5; i++) assert.equal((await s.call('POST', '/v1/recover', wrong)).status, 401);
    const blocked = await s.call('POST', '/v1/recover', { email: account.email, recoveryAuthKey: account.recoveryAuthKey });
    assert.equal(blocked.status, 429);
    s.advance(61 * MINUTE);
    assert.equal((await s.call('POST', '/v1/recover', { email: account.email, recoveryAuthKey: account.recoveryAuthKey })).status, 200);
  });
});

describe('change password and recovery key', () => {
  it('new password works, old one stops, other phones are logged out', async () => {
    const s = new Server();
    const { account, token: phoneA } = await signUp(s);
    const phoneB = (await s.call('POST', '/v1/login', { email: account.email, authKey: account.authKey })).body.token;

    const next = newAccountFields(account.email);
    const bundle = { ...account.bundle, password: next.bundle.password };
    // A session alone is not enough, and neither is a wrong key.
    const bare = await s.call('POST', '/v1/password', { authKey: next.authKey, bundle }, phoneA);
    assert.equal(bare.status, 400);
    assert.equal(bare.body.error, 'proof_required');
    const wrong = await s.call('POST', '/v1/password', { authKey: next.authKey, bundle, currentAuthKey: next.authKey }, phoneA);
    assert.equal(wrong.status, 401);
    assert.equal((await s.call('POST', '/v1/login', { email: account.email, authKey: account.authKey })).status, 200);
    const res = await s.call('POST', '/v1/password', { authKey: next.authKey, bundle, currentAuthKey: account.authKey }, phoneA);
    assert.equal(res.status, 200);

    assert.equal((await s.call('POST', '/v1/login', { email: account.email, authKey: account.authKey })).status, 401);
    const fresh = await s.call('POST', '/v1/login', { email: account.email, authKey: next.authKey });
    assert.equal(fresh.status, 200);
    assert.deepEqual(fresh.body.bundle, bundle);
    assert.equal((await s.call('GET', '/v1/records', undefined, phoneA)).status, 200);
    assert.equal((await s.call('GET', '/v1/records', undefined, phoneB)).status, 401);
    // The recovery key is untouched.
    assert.equal((await s.call('POST', '/v1/recover', { email: account.email, recoveryAuthKey: account.recoveryAuthKey })).status, 200);
  });

  it('refuses a bundle for a different data key (it would orphan every record)', async () => {
    const s = new Server();
    const { account, token } = await signUp(s);
    const other = newAccountFields();
    const res = await s.call('POST', '/v1/password', { authKey: other.authKey, bundle: other.bundle, currentAuthKey: account.authKey }, token);
    assert.equal(res.status, 400);
    assert.equal(res.body.error, 'key_changed');
    assert.equal((await s.call('POST', '/v1/login', { email: account.email, authKey: account.authKey })).status, 200);
  });

  it('needs a session', async () => {
    const s = new Server();
    const { account } = await signUp(s);
    const res = await s.call('POST', '/v1/password', { authKey: account.authKey, bundle: account.bundle });
    assert.equal(res.status, 401);
  });

  it('a new recovery key replaces the old one', async () => {
    const s = new Server();
    const { account, token } = await signUp(s);
    const fresh = toB64(randomBytes(32));
    const bundle = { ...account.bundle, recovery: toB64(randomBytes(73)) };
    // A stolen session cannot set its own recovery key.
    assert.equal((await s.call('POST', '/v1/recovery-key', { recoveryAuthKey: fresh, bundle }, token)).status, 400);
    const res = await s.call(
      'POST', '/v1/recovery-key',
      { recoveryAuthKey: fresh, bundle, currentRecoveryAuthKey: account.recoveryAuthKey }, token,
    );
    assert.equal(res.status, 200);
    assert.equal((await s.call('POST', '/v1/recover', { email: account.email, recoveryAuthKey: account.recoveryAuthKey })).status, 401);
    const ok = await s.call('POST', '/v1/recover', { email: account.email, recoveryAuthKey: fresh });
    assert.equal(ok.status, 200);
    assert.equal(ok.body.bundle.recovery, bundle.recovery);
  });
});

describe('a stolen session cannot change the keys', () => {
  it('after a recovery log-in the new password is set with the recovery proof; wrong proofs are limited', async () => {
    const s = new Server();
    const { account } = await signUp(s);
    const session = (await s.call('POST', '/v1/recover', { email: account.email, recoveryAuthKey: account.recoveryAuthKey })).body.token;
    const next = newAccountFields(account.email);
    const bundle = { ...account.bundle, password: next.bundle.password };
    const ok = await s.call(
      'POST', '/v1/password',
      { authKey: next.authKey, bundle, currentRecoveryAuthKey: account.recoveryAuthKey }, session,
    );
    assert.equal(ok.status, 200);

    for (let i = 0; i < 10; i++) {
      const bad = await s.call('POST', '/v1/password', { authKey: next.authKey, bundle, currentAuthKey: account.authKey }, session);
      assert.equal(bad.status, 401);
    }
    const limited = await s.call('POST', '/v1/password', { authKey: next.authKey, bundle, currentAuthKey: next.authKey }, session);
    assert.equal(limited.status, 429);
  });
});

describe('sessions', () => {
  it('log out ends only that session', async () => {
    const s = new Server();
    const { account, token } = await signUp(s);
    const other = (await s.call('POST', '/v1/login', { email: account.email, authKey: account.authKey })).body.token;
    assert.equal((await s.call('POST', '/v1/logout', {}, token)).status, 200);
    assert.equal((await s.call('GET', '/v1/records', undefined, token)).status, 401);
    assert.equal((await s.call('GET', '/v1/records', undefined, other)).status, 200);
  });

  it('a session ends after 60 days', async () => {
    const s = new Server();
    const { token } = await signUp(s);
    s.advance(59 * DAY);
    assert.equal((await s.call('GET', '/v1/records', undefined, token)).status, 200);
    s.advance(2 * DAY);
    assert.equal((await s.call('GET', '/v1/records', undefined, token)).status, 401);
  });

  it('bad or missing tokens are 401', async () => {
    const s = new Server();
    await signUp(s);
    for (const token of [undefined, 'nope', toB64(randomBytes(32))]) {
      assert.equal((await s.call('GET', '/v1/records', undefined, token)).status, 401);
    }
  });

  it('keeps at most 20 sessions per account', async () => {
    const s = new Server();
    const { account, token: first } = await signUp(s);
    for (let i = 0; i < 25; i++) {
      s.advance(1000);
      await s.call('POST', '/v1/login', { email: account.email, authKey: account.authKey });
    }
    const count = s.d1.db.prepare('SELECT COUNT(*) AS n FROM sessions').get() as { n: number };
    assert.equal(count.n, 20);
    assert.equal((await s.call('GET', '/v1/records', undefined, first)).status, 401);
  });
});

describe('delete account', () => {
  it('removes everything and frees the email', async () => {
    const s = new Server();
    const { account, token } = await signUp(s);
    const res = await s.call('POST', '/v1/account/delete', { authKey: account.authKey }, token);
    assert.equal(res.status, 200);
    for (const table of ['users', 'sessions', 'records']) {
      const row = s.d1.db.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get() as { n: number };
      assert.equal(row.n, 0, table);
    }
    assert.equal((await s.call('POST', '/v1/register', newAccountFields(account.email))).status, 200);
  });

  it('needs the password key as well as the session', async () => {
    const s = new Server();
    const { token } = await signUp(s);
    const res = await s.call('POST', '/v1/account/delete', { authKey: toB64(randomBytes(32)) }, token);
    assert.equal(res.status, 401);
  });
});
