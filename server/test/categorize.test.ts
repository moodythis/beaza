import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { CATEGORIZE_CONSENT_VERSION, parseCategories } from '../src/categorize.ts';
import { Server } from './harness.ts';

class FakeAi {
  calls: unknown[] = [];
  reply: unknown;
  constructor(reply: unknown) {
    this.reply = reply;
  }
  async run(_model: string, input: unknown) {
    this.calls.push(input);
    if (this.reply instanceof Error) throw this.reply;
    return this.reply;
  }
}

const body = (names: unknown, extra: Record<string, unknown> = {}) => ({
  consent: CATEGORIZE_CONSENT_VERSION,
  names,
  ...extra,
});

describe('POST /v1/categorize (AI sorting of shop names)', () => {
  it('sends only the names and keeps known categories for given names', async () => {
    const s = new Server();
    const ai = new FakeAi({
      response: '```json\n{"TALABAT": "food", "LULU HYPERMARKET": "groceries", "BATELCO": "telecom", "OTHER SHOP": "food"}\n```',
    });
    s.ai = ai;
    const res = await s.call('POST', '/v1/categorize', body(['TALABAT', 'LULU HYPERMARKET', 'BATELCO']));
    assert.equal(res.status, 200);
    assert.deepEqual(res.body.categories, { TALABAT: 'food', 'LULU HYPERMARKET': 'groceries' });
    assert.equal(JSON.stringify(ai.calls[0]).includes('TALABAT'), true);
  });

  it('a failed model gives an empty answer, not an error', async () => {
    const s = new Server();
    s.ai = new FakeAi(new Error('down'));
    const res = await s.call('POST', '/v1/categorize', body(['TALABAT']));
    assert.equal(res.status, 200);
    assert.deepEqual(res.body.categories, {});
  });

  it('refuses digits, too many names, other fields and no consent', async () => {
    const s = new Server();
    s.ai = new FakeAi({ response: '{}' });
    const cases: [unknown, string][] = [
      [body(['CARD 4111']), 'bad_names'],
      [body([]), 'bad_names'],
      [body(Array.from({ length: 31 }, (_, i) => `SHOP ${'ABCDEFGHIJKLMNOPQRSTUVWXYZABCDEF'[i]}x${'abcdefghijklmnopqrstuvwxyzabcdef'[i]}`)), 'bad_names'],
      [body(['A1']), 'bad_names'],
      [body(['TALABAT'], { amount: 1 }), 'unexpected_field'],
      [{ names: ['TALABAT'] }, 'consent_required'],
    ];
    for (const [b, code] of cases) {
      const res = await s.call('POST', '/v1/categorize', b as Record<string, unknown>);
      assert.equal(res.status, 400, JSON.stringify(b).slice(0, 60));
      assert.equal(res.body.error, code);
    }
  });

  it('parseCategories matches names in any letter case', () => {
    assert.deepEqual(parseCategories('{"talabat": "Food"}', ['TALABAT']), { TALABAT: 'food' });
    assert.deepEqual(parseCategories('not json', ['TALABAT']), {});
  });
});
