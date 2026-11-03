// Registers an account made by packages/beaza_crypto/tool/new_account.dart
// on a live server, agreeing to the current privacy notice and terms.
// Prints only the outcome, never keys or tokens.
//   node scripts/register.ts https://beaza-sync.moodythis.workers.dev account.json
import { readFileSync } from 'node:fs';
import { PRIVACY_VERSION, TERMS_VERSION } from '../src/legal.ts';

const [url, file] = process.argv.slice(2);
const a = JSON.parse(readFileSync(file, 'utf8'));
const response = await fetch(new URL('/v1/register', url), {
  method: 'POST',
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify({
    email: a.email,
    authKey: a.authKey,
    recoveryAuthKey: a.recoveryAuthKey,
    bundle: a.bundle,
    consent: { privacy: PRIVACY_VERSION, terms: TERMS_VERSION, adult: true },
  }),
});
const body = (await response.json()) as { error?: string };
if (response.ok) {
  console.log(`registered ${a.email}`);
} else {
  console.log(`refused: ${response.status} ${body.error}`);
  process.exit(1);
}
