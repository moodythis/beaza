// Full check of a deployed server, using a throw-away account that is
// deleted at the end. Run by the "Smoke test" workflow:
//   node scripts/smoke.ts https://beaza-sync.<name>.workers.dev
import { randomBytes, toB64 } from '../src/util.ts';

const base = (process.argv[2] ?? '').replace(/\/$/, '');
if (!base.startsWith('https://')) throw new Error('give the server URL');

let step = 0;
function check(name: string, ok: boolean, detail?: unknown) {
  step++;
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${step}. ${name}${ok ? '' : ` -> ${JSON.stringify(detail)}`}`);
  if (!ok) failed = true;
}
let failed = false;

async function call(method: string, path: string, body?: unknown, token?: string) {
  const res = await fetch(base + path, {
    method,
    headers: {
      ...(body === undefined ? {} : { 'content-type': 'application/json' }),
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  return { status: res.status, body: (await res.json()) as any };
}

const email = `smoke-${Date.now()}@example.com`;
const authKey = toB64(randomBytes(32));
const recoveryAuthKey = toB64(randomBytes(32));
const bundle = {
  v: 1,
  keyId: Array.from(randomBytes(16), (b) => b.toString(16).padStart(2, '0')).join(''),
  recovery: toB64(randomBytes(105)),
  password: {
    salt: toB64(randomBytes(16)),
    kdf: { alg: 'argon2id', m: 19456, t: 2, p: 1 },
    key: toB64(randomBytes(105)),
  },
};
const blob = toB64(randomBytes(200));

try {
  let r = await call('GET', '/v1/health');
  check('health', r.status === 200 && r.body.ok === true, r);

  r = await call('POST', '/v1/register', { email, authKey, recoveryAuthKey, bundle });
  check('register', r.status === 200 && typeof r.body.token === 'string', r);
  const token = r.body.token as string;

  r = await call('POST', '/v1/register', { email, authKey, recoveryAuthKey, bundle });
  check('same email again is refused', r.status === 409, r);

  r = await call('POST', '/v1/kdf', { email });
  check('kdf returns the account salt', r.body.salt === bundle.password.salt, r);

  r = await call('POST', '/v1/login', { email, authKey: toB64(randomBytes(32)) });
  check('wrong key is refused', r.status === 401, r);

  r = await call('POST', '/v1/login', { email, authKey });
  check('login returns the same bundle', r.status === 200 && JSON.stringify(r.body.bundle) === JSON.stringify(bundle), r);
  const second = r.body.token as string;

  r = await call('POST', '/v1/recover', { email, recoveryAuthKey });
  check('recover works with the recovery proof', r.status === 200, r);

  r = await call('POST', '/v1/records', { records: [{ collection: 'transactions', id: 'smoke1', blob }] }, token);
  check('push a record', r.status === 200 && r.body.seq === 1, r);

  r = await call('GET', '/v1/records?since=0', undefined, second);
  check('another session pulls it back, unchanged',
    r.status === 200 && r.body.records.length === 1 && r.body.records[0].blob === blob && r.body.records[0].seq === 1, r);

  r = await call('GET', '/v1/records');
  check('no session is refused', r.status === 401, r);

  r = await call('POST', '/v1/account/delete', { authKey }, token);
  check('delete the account', r.status === 200, r);

  r = await call('POST', '/v1/login', { email, authKey });
  check('the deleted account cannot log in', r.status === 401, r);
} catch (error) {
  failed = true;
  console.log('FAIL', error);
}
console.log(failed ? 'SMOKE TEST FAILED' : 'SMOKE TEST PASSED');
process.exit(failed ? 1 : 0);
