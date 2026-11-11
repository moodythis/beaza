import assert from 'node:assert/strict';
import { before, describe, it } from 'node:test';
import { randomBytes, toB64, utf8 } from '../src/util.ts';
import { newAccountFields, sealedLike, Server, signUp } from './harness.ts';

const CLIENT = 'beaza-web.apps.googleusercontent.com';
let keyPair: CryptoKeyPair;
let publicJwk: JsonWebKey;

before(async () => {
  keyPair = (await crypto.subtle.generateKey(
    {
      name: 'RSASSA-PKCS1-v1_5',
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: 'SHA-256',
    },
    true,
    ['sign', 'verify'],
  )) as CryptoKeyPair;
  publicJwk = { ...(await crypto.subtle.exportKey('jwk', keyPair.publicKey)), kid: 'k1' } as JsonWebKey;
});

const b64json = (value: unknown) => toB64(utf8(JSON.stringify(value)));

/** A Google-style ID token signed with the test key. */
async function idToken(server: Server, claims: Record<string, unknown> = {}, kid = 'k1') {
  const now = Math.floor(server.time / 1000);
  const head = b64json({ alg: 'RS256', kid, typ: 'JWT' });
  const body = b64json({
    iss: 'https://accounts.google.com',
    aud: CLIENT,
    sub: '1234567890',
    email: 'Person@Gmail.com',
    email_verified: true,
    iat: now,
    exp: now + 3600,
    ...claims,
  });
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', keyPair.privateKey, utf8(`${head}.${body}`));
  return `${head}.${body}.${toB64(new Uint8Array(sig))}`;
}

function googleServer() {
  const s = new Server();
  s.googleClientId = CLIENT;
  s.googleKeys = async () => [publicJwk];
  return s;
}

/** What the phone sends for a Google account: no password lock. */
function googleFields() {
  const { recoveryAuthKey, bundle, consent } = newAccountFields();
  const { password: _, ...noPassword } = bundle;
  return { recoveryAuthKey, bundle: noPassword, consent };
}

async function googleSignUp(s: Server) {
  const fields = googleFields();
  const res = await s.call('POST', '/v1/google/register', { idToken: await idToken(s), ...fields });
  assert.equal(res.status, 200, JSON.stringify(res.body));
  return { ...fields, token: res.body.token as string };
}

describe('Google accounts', () => {
  it('are off until a client id is configured', async () => {
    const s = new Server();
    const res = await s.call('POST', '/v1/google/check', { idToken: 'x.y.z' });
    assert.equal(res.status, 503);
    assert.equal(res.body.error, 'google_disabled');
  });

  it('check, sign up, then log in on another phone with the recovery key', async () => {
    const s = googleServer();
    const before = await s.call('POST', '/v1/google/check', { idToken: await idToken(s) });
    assert.deepEqual(before.body, { exists: false, email: 'person@gmail.com', password: false, linked: false });

    const account = await googleSignUp(s);
    const info = await s.call('GET', '/v1/account', undefined, account.token);
    assert.equal(info.body.email, 'person@gmail.com');

    const after = await s.call('POST', '/v1/google/check', { idToken: await idToken(s) });
    assert.equal(after.body.exists, true);

    const login = await s.call('POST', '/v1/google/login', {
      idToken: await idToken(s),
      recoveryAuthKey: account.recoveryAuthKey,
    });
    assert.equal(login.status, 200);
    assert.deepEqual(login.body.bundle, account.bundle);
    assert.ok(login.body.token);
  });

  it('log-in needs the right recovery key, and wrong ones are limited', async () => {
    const s = googleServer();
    await googleSignUp(s);
    for (let i = 0; i < 10; i++) {
      const res = await s.call('POST', '/v1/google/login', {
        idToken: await idToken(s),
        recoveryAuthKey: toB64(randomBytes(32)),
      });
      assert.equal(res.status, 401);
    }
    const limited = await s.call('POST', '/v1/google/login', {
      idToken: await idToken(s),
      recoveryAuthKey: toB64(randomBytes(32)),
    });
    assert.equal(limited.status, 429);
  });

  it('an unknown Google account gets no_account', async () => {
    const s = googleServer();
    const res = await s.call('POST', '/v1/google/login', {
      idToken: await idToken(s),
      recoveryAuthKey: toB64(randomBytes(32)),
    });
    assert.equal(res.status, 404);
    assert.equal(res.body.error, 'no_account');
  });

  it('an email account with the same Gmail is found, and linked after the password', async () => {
    const s = googleServer();
    const { account, token } = await signUp(s, 'person@gmail.com');
    const check = await s.call('POST', '/v1/google/check', { idToken: await idToken(s) });
    assert.deepEqual(check.body, { exists: true, email: 'person@gmail.com', password: true, linked: false });

    const wrong = await s.call('POST', '/v1/google/login', {
      idToken: await idToken(s),
      authKey: toB64(randomBytes(32)),
    });
    assert.equal(wrong.status, 401);

    const login = await s.call('POST', '/v1/google/login', {
      idToken: await idToken(s),
      authKey: account.authKey,
    });
    assert.equal(login.status, 200);
    assert.deepEqual(login.body.bundle, account.bundle);

    // Linked: the recovery key works through Google too, and the password
    // still works on its own.
    const byRecovery = await s.call('POST', '/v1/google/login', {
      idToken: await idToken(s),
      recoveryAuthKey: account.recoveryAuthKey,
    });
    assert.equal(byRecovery.status, 200);
    const plain = await s.call('POST', '/v1/login', { email: account.email, authKey: account.authKey });
    assert.equal(plain.status, 200);

    // Deleting it can now be confirmed with Google.
    const del = await s.call('POST', '/v1/account/delete', { idToken: await idToken(s) }, token);
    assert.equal(del.status, 200);
  });

  it('an email account already linked to another Google account is not taken over', async () => {
    const s = googleServer();
    const { account } = await signUp(s, 'person@gmail.com');
    await s.call('POST', '/v1/google/login', {
      idToken: await idToken(s, { sub: 'first' }),
      authKey: account.authKey,
    });
    const other = await s.call('POST', '/v1/google/check', { idToken: await idToken(s, { sub: 'second' }) });
    assert.equal(other.body.exists, false);
    const login = await s.call('POST', '/v1/google/login', {
      idToken: await idToken(s, { sub: 'second' }),
      authKey: account.authKey,
    });
    assert.equal(login.status, 404);
  });

  it('a remembered phone logs in again with Google alone', async () => {
    const s = googleServer();
    const { account } = await signUp(s, 'person@gmail.com');
    const first = await s.call('POST', '/v1/google/login', {
      idToken: await idToken(s),
      authKey: account.authKey,
      remember: true,
    });
    const deviceKey = first.body.deviceKey as string;
    assert.ok(deviceKey);

    const again = await s.call('POST', '/v1/google/login', { idToken: await idToken(s), deviceKey });
    assert.equal(again.status, 200);
    assert.ok(again.body.token);
    assert.equal(again.body.deviceKey, undefined, 'no new key for a device log-in');

    // A made-up device key, or the right one with another Google account, fails.
    const madeUp = await s.call('POST', '/v1/google/login', {
      idToken: await idToken(s),
      deviceKey: toB64(randomBytes(32)),
    });
    assert.equal(madeUp.status, 401);
    const otherGoogle = await s.call('POST', '/v1/google/login', {
      idToken: await idToken(s, { sub: 'someone-else' }),
      deviceKey,
    });
    assert.equal(otherGoogle.status, 404);
  });

  it('a device key alone does not link an email account to Google', async () => {
    const s = googleServer();
    await signUp(s, 'person@gmail.com');
    const res = await s.call('POST', '/v1/google/login', {
      idToken: await idToken(s),
      deviceKey: toB64(randomBytes(32)),
    });
    assert.equal(res.status, 401);
    const check = await s.call('POST', '/v1/google/check', { idToken: await idToken(s) });
    assert.equal(check.body.password, true, 'still unlinked');
  });

  it('sign-up can remember the phone, and deleting the account forgets it', async () => {
    const s = googleServer();
    const fields = googleFields();
    const res = await s.call('POST', '/v1/google/register', {
      idToken: await idToken(s), ...fields, remember: true,
    });
    const deviceKey = res.body.deviceKey as string;
    assert.ok(deviceKey);
    await s.call('POST', '/v1/account/delete', { idToken: await idToken(s) }, res.body.token);
    const after = await s.call('POST', '/v1/google/login', { idToken: await idToken(s), deviceKey });
    assert.equal(after.status, 404);
  });

  it('a Google account has no password: password log-in never works', async () => {
    const s = googleServer();
    await googleSignUp(s);
    const res = await s.call('POST', '/v1/login', {
      email: 'person@gmail.com',
      authKey: toB64(randomBytes(32)),
    });
    assert.equal(res.status, 401);
  });

  it('refuses a bundle with a password lock, and an email that already has an account', async () => {
    const s = googleServer();
    const withPassword = newAccountFields();
    const res = await s.call('POST', '/v1/google/register', {
      idToken: await idToken(s),
      recoveryAuthKey: withPassword.recoveryAuthKey,
      bundle: withPassword.bundle,
      consent: withPassword.consent,
    });
    assert.equal(res.body.error, 'bad_bundle');

    await signUp(s, 'person@gmail.com');
    const taken = await s.call('POST', '/v1/google/register', { idToken: await idToken(s), ...googleFields() });
    assert.equal(taken.status, 409);
    assert.equal(taken.body.error, 'email_taken');
  });

  it('sign-up needs the same consent as email accounts', async () => {
    const s = googleServer();
    const { consent: _, ...noConsent } = googleFields();
    const res = await s.call('POST', '/v1/google/register', { idToken: await idToken(s), ...noConsent });
    assert.equal(res.body.error, 'consent_required');
  });

  for (const [name, claims, kid] of [
    ['another app', { aud: 'other.apps.googleusercontent.com' }, 'k1'],
    ['another issuer', { iss: 'https://evil.example' }, 'k1'],
    ['an expired token', { exp: Math.floor(Date.UTC(2026, 10, 3, 10) / 1000) }, 'k1'],
    ['an unverified email', { email_verified: false }, 'k1'],
    ['an unknown key', {}, 'k9'],
  ] as const) {
    it(`refuses ${name}`, async () => {
      const s = googleServer();
      const res = await s.call('POST', '/v1/google/check', { idToken: await idToken(s, claims, kid) });
      assert.equal(res.status, 401);
      assert.equal(res.body.error, 'invalid_id_token');
    });
  }

  it('refuses a token whose payload was changed after signing', async () => {
    const s = googleServer();
    const [h, , sig] = (await idToken(s)).split('.');
    const forged = b64json({
      iss: 'https://accounts.google.com', aud: CLIENT, sub: 'someone-else', email: 'x@gmail.com',
      email_verified: true, iat: Math.floor(s.time / 1000), exp: Math.floor(s.time / 1000) + 3600,
    });
    const res = await s.call('POST', '/v1/google/check', { idToken: `${h}.${forged}.${sig}` });
    assert.equal(res.body.error, 'invalid_id_token');
  });

  it('deleting a Google account needs a token for that same Google account', async () => {
    const s = googleServer();
    const account = await googleSignUp(s);
    const other = await s.call(
      'POST', '/v1/account/delete', { idToken: await idToken(s, { sub: '999' }) }, account.token,
    );
    assert.equal(other.status, 401);
    const ok = await s.call('POST', '/v1/account/delete', { idToken: await idToken(s) }, account.token);
    assert.equal(ok.status, 200);
    const check = await s.call('POST', '/v1/google/check', { idToken: await idToken(s) });
    assert.equal(check.body.exists, false);
  });

  it('someone took my email first: Google proves it is mine and I get it back', async () => {
    const s = googleServer();
    // A stranger signs up with the address (sign-up by email checks nothing)
    // and stores something.
    const squatter = await signUp(s, 'person@gmail.com');
    await s.call('POST', '/v1/records', { records: [{ collection: 'txn', id: 'a1', blob: sealedLike() }] }, squatter.token);

    const check = await s.call('POST', '/v1/google/check', { idToken: await idToken(s) });
    assert.equal(check.body.exists, true);
    assert.equal(check.body.linked, false);

    // Without `replace` nothing changes.
    const fields = googleFields();
    const plain = await s.call('POST', '/v1/google/register', { idToken: await idToken(s), ...fields });
    assert.equal(plain.status, 409);

    const mine = await s.call('POST', '/v1/google/register', { idToken: await idToken(s), ...fields, replace: true });
    assert.equal(mine.status, 200, JSON.stringify(mine.body));
    // The stranger is out: session, password and records are gone.
    assert.equal((await s.call('GET', '/v1/records', undefined, squatter.token)).status, 401);
    assert.equal(
      (await s.call('POST', '/v1/login', { email: 'person@gmail.com', authKey: squatter.account.authKey })).status,
      401,
    );
    assert.equal((await s.call('GET', '/v1/records', undefined, mine.body.token)).body.records.length, 0);
    const after = await s.call('POST', '/v1/google/check', { idToken: await idToken(s) });
    assert.equal(after.body.linked, true);
  });

  it('an account already linked to a Google account cannot be replaced', async () => {
    const s = googleServer();
    await googleSignUp(s);
    const again = await s.call('POST', '/v1/google/register', {
      idToken: await idToken(s), ...googleFields(), replace: true,
    });
    assert.equal(again.status, 409);
    // Nor can another Google account take the same address.
    const other = await s.call('POST', '/v1/google/register', {
      idToken: await idToken(s, { sub: 'second' }), ...googleFields(), replace: true,
    });
    assert.equal(other.status, 409);
  });
});
