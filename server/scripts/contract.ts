// Contract test, step 2 of 3 (see .github/workflows/ci.yml, job "contract").
// Sends a real account made by the Dart code (step 1) to the real server
// code, on SQLite, and saves the answers for step 3.
//   node scripts/contract.ts account.json responses.json
import { readFileSync, writeFileSync } from 'node:fs';
import { PRIVACY_VERSION, TERMS_VERSION } from '../src/legal.ts';
import { Server } from '../test/harness.ts';

const sample = JSON.parse(readFileSync(process.argv[2], 'utf8'));
const out = process.argv[3];
const s = new Server();
let failed = false;
function check(name: string, ok: boolean, detail?: unknown) {
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}${ok ? '' : ` -> ${JSON.stringify(detail)}`}`);
  if (!ok) failed = true;
}

const consent = { privacy: PRIVACY_VERSION, terms: TERMS_VERSION, adult: true };
const reg = await s.call('POST', '/v1/register', {
  email: sample.email,
  authKey: sample.authKey,
  recoveryAuthKey: sample.recoveryAuthKey,
  bundle: sample.bundle,
  consent,
});
check('the server accepts a real sign-up from the phone', reg.status === 200, reg.body);
const token = reg.body.token as string;

const kdf = await s.call('POST', '/v1/kdf', { email: sample.email });
check('kdf returns the salt and setting the phone made', kdf.body.salt === sample.bundle.password.salt, kdf.body);

const login = await s.call('POST', '/v1/login', { email: sample.email, authKey: sample.authKey });
check('log-in with the real auth key works', login.status === 200, login.body);

const recover = await s.call('POST', '/v1/recover', {
  email: sample.email,
  recoveryAuthKey: sample.recoveryAuthKey,
});
check('recovery with the real recovery proof works', recover.status === 200, recover.body);

const push = await s.call('POST', '/v1/records', { records: [sample.record] }, token);
check('the server accepts a real encrypted record', push.status === 200, push.body);
const pull = await s.call('GET', '/v1/records', undefined, token);
check('and returns it unchanged', pull.body.records?.[0]?.blob === sample.record.blob, pull.body);

const stored = s.d1.dump();
const secrets = sample.secrets;
for (const secret of [secrets.password, secrets.recoveryKey, secrets.dataKey, sample.authKey, sample.recoveryAuthKey, ...secrets.plainTexts]) {
  check(`the database does not contain ${String(secret).slice(0, 12)}…`, !stored.includes(secret));
}

writeFileSync(out, JSON.stringify({ kdf: kdf.body, login: login.body, pull: pull.body }));
console.log(failed ? 'CONTRACT FAILED' : 'CONTRACT PASSED');
process.exit(failed ? 1 : 0);
