import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { parseAlternatives } from '../src/alternatives.ts';
import { COACH_CONSENT_VERSION } from '../src/coach.ts';
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

const body = (shops: unknown, extra: Record<string, unknown> = {}) => ({
  consent: COACH_CONSENT_VERSION,
  language: 'en',
  shops,
  ...extra,
});

const SHOPS = [
  { name: 'COSTA COFFEE', count: 6 },
  { name: 'TALABAT', count: 4 },
];

describe('POST /v1/alternatives (cheaper options)', () => {
  it('keeps one idea per given shop and sends only names and visits', async () => {
    const s = new Server();
    const ai = new FakeAi({
      response: '```json\n[{"shop":"costa coffee","idea":"Make coffee at home on weekdays."},{"shop":"TALABAT","idea":"Pick up instead of delivery."},{"shop":"OTHER","idea":"Not asked for."}]\n```',
    });
    s.ai = ai;
    const res = await s.call('POST', '/v1/alternatives', body(SHOPS));
    assert.equal(res.status, 200);
    assert.deepEqual(res.body.alternatives, [
      { shop: 'COSTA COFFEE', idea: 'Make coffee at home on weekdays.' },
      { shop: 'TALABAT', idea: 'Pick up instead of delivery.' },
    ]);
    assert.equal(res.body.source, 'model');
    const sent = JSON.stringify(ai.calls[0]);
    assert.ok(sent.includes('COSTA COFFEE'));
  });

  it('drops ideas with prices, percentages or invented numbers', () => {
    const ideas = parseAlternatives(
      '[{"shop":"A B","idea":"Go to X, coffee is 0.500 there."},{"shop":"C D","idea":"خصم ٢٠٪ عند Y."},{"shop":"E F","idea":"Buy in bulk at a hypermarket."}]',
      ['A B', 'C D', 'E F'],
    );
    assert.deepEqual(ideas, [{ shop: 'E F', idea: 'Buy in bulk at a hypermarket.' }]);
  });

  it('a failed model gives no ideas and says why, not an error', async () => {
    const s = new Server();
    s.ai = new FakeAi(new Error('gemini 503 busy'));
    const res = await s.call('POST', '/v1/alternatives', body(SHOPS));
    assert.equal(res.status, 200);
    assert.deepEqual(res.body.alternatives, []);
    assert.match(String(res.body.reason), /gemini 503/);
  });

  it('needs the plan consent and refuses anything else', async () => {
    const s = new Server();
    s.ai = new FakeAi({ response: '[]' });
    assert.equal((await s.call('POST', '/v1/alternatives', body(SHOPS, { consent: 'old' }))).status, 400);
    assert.equal((await s.call('POST', '/v1/alternatives', body(SHOPS, { phone: '3' }))).status, 400);
    assert.equal((await s.call('POST', '/v1/alternatives', body([{ name: 'CARD 1234', count: 1 }]))).status, 400);
    assert.equal((await s.call('POST', '/v1/alternatives', body([]))).status, 400);
    // No amounts: the AI does not need them.
    assert.equal((await s.call('POST', '/v1/alternatives', body([{ name: 'TALABAT', fils: 10, count: 1 }]))).status, 400);
  });
});
