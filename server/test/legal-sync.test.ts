import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { it } from 'node:test';
import { DART_FILE, dartSource } from '../scripts/legal-dart.ts';

it('the app shows exactly the privacy notice and terms the server publishes', () => {
  assert.equal(
    readFileSync(DART_FILE, 'utf8'),
    dartSource(),
    'Run: node scripts/legal-dart.ts',
  );
});
