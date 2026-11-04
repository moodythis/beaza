import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import {
  COACH_CONSENT_VERSION,
  COACH_MODEL,
  numbersIn,
  onlyGivenNumbers,
} from '../src/coach.ts';
import { Server } from './harness.ts';

/** Totals as the phone sends them: no names, texts, digits or dates. */
function request(over: Record<string, unknown> = {}) {
  return {
    consent: COACH_CONSENT_VERSION,
    language: 'ar',
    week_total_fils: 19150,
    previous_week_total_fils: 12000,
    daily_limit_fils: 10000,
    days_over_limit: 2,
    small_purchases_count: 6,
    small_purchases_fils: 5950,
    categories: [
      { category: 'shopping', fils: 13200, percent: 69 },
      { category: 'food', fils: 3900, percent: 20 },
      { category: 'unsorted', fils: 2050, percent: 11 },
    ],
    ...over,
  };
}

class FakeAi {
  calls: { model: string; input: any }[] = [];
  reply: unknown;
  constructor(reply: unknown) {
    this.reply = reply;
  }
  async run(model: string, input: unknown) {
    this.calls.push({ model, input });
    if (this.reply instanceof Error) throw this.reply;
    return this.reply;
  }
}

describe('POST /v1/coach (AI savings plan)', () => {
  it('sends only the facts to the model and returns its plan', async () => {
    const s = new Server();
    const ai = new FakeAi({
      response: '1. خفّف التسوق 20٪ هالأسبوع وتوفّر 2.640 د.ب.\n2. عندك 6 مصاريف صغيرة مجموعها 5.950 د.ب.',
    });
    s.ai = ai;
    const res = await s.call('POST', '/v1/coach', request());
    assert.equal(res.status, 200);
    assert.equal(res.body.source, 'model');
    assert.equal(res.body.model, COACH_MODEL);
    assert.match(res.body.plan, /2\.640/);
    assert.equal(ai.calls.length, 1);
    assert.equal(ai.calls[0].model, COACH_MODEL);
    const sent = JSON.stringify(ai.calls[0].input);
    // The worked-out numbers are in the facts, in the user's language.
    assert.match(sent, /19\.150 د\.ب/);
    assert.match(sent, /زيادة 60٪/);
    assert.match(sent, /2\.640 د\.ب/);
    assert.match(sent, /10\.560 د\.ب/);
    // Nothing is stored about the request but today's count.
    assert.equal(
      JSON.stringify(s.d1.db.prepare('SELECT * FROM coach_usage').all()),
      '[{"day":"2026-11-03","count":1}]',
    );
  });

  it('a reply with a number it was not given is replaced by the rule plan', async () => {
    const s = new Server();
    s.ai = new FakeAi({ response: '1. وفّر 50.000 د.ب هالشهر.' });
    const res = await s.call('POST', '/v1/coach', request());
    assert.equal(res.status, 200);
    assert.equal(res.body.source, 'rules');
    assert.doesNotMatch(res.body.plan, /50\.000/);
    assert.match(res.body.plan, /^1\. خفّف التسوق 20٪/);
    assert.ok(onlyGivenNumbers(res.body.plan, res.body.facts));
  });

  it('a failing or empty model also gives the rule plan', async () => {
    for (const reply of [new Error('busy'), {}, { choices: [] }]) {
      const s = new Server();
      s.ai = new FakeAi(reply);
      const res = await s.call('POST', '/v1/coach', request({ language: 'en' }));
      assert.equal(res.status, 200);
      assert.equal(res.body.source, 'rules');
      assert.match(res.body.plan, /^1\. Cut shopping by 20%/);
    }
  });

  it('reads the chat-completions reply shape too', async () => {
    const s = new Server();
    s.ai = new FakeAi({ choices: [{ message: { content: '1. Spend less on shopping: BHD 2.640 a week.' } }] });
    const res = await s.call('POST', '/v1/coach', request({ language: 'en' }));
    assert.equal(res.body.source, 'model');
  });

  it('refuses any field that is not a total, so no name or text can be sent', async () => {
    const s = new Server();
    s.ai = new FakeAi({ response: 'x' });
    for (const extra of [{ merchant: 'Waleed Al Kabah' }, { message: 'Dear Customer' }, { last4: '4810' }]) {
      const res = await s.call('POST', '/v1/coach', request(extra));
      assert.equal(res.status, 400);
      assert.equal(res.body.error, 'unexpected_field');
    }
    const named = await s.call('POST', '/v1/coach', request({
      categories: [{ category: 'shopping', fils: 1, percent: 1, shop: 'REDTAG' }],
    }));
    assert.equal(named.body.error, 'bad_categories');
    const unknown = await s.call('POST', '/v1/coach', request({
      categories: [{ category: 'REDTAG', fils: 1, percent: 1 }],
    }));
    assert.equal(unknown.body.error, 'bad_categories');
    assert.equal((s.ai as FakeAi).calls.length, 0);
  });

  it('needs the AI consent and whole, sensible numbers', async () => {
    const s = new Server();
    s.ai = new FakeAi({ response: 'x' });
    assert.equal((await s.call('POST', '/v1/coach', request({ consent: undefined }))).body.error, 'consent_required');
    assert.equal((await s.call('POST', '/v1/coach', request({ week_total_fils: 1.5 }))).body.error, 'bad_number');
    assert.equal((await s.call('POST', '/v1/coach', request({ days_over_limit: 8 }))).body.error, 'bad_number');
    assert.equal((await s.call('POST', '/v1/coach', request({ language: 'fr' }))).body.error, 'bad_language');
  });

  it('is off without the AI binding, and stops at the daily cap', async () => {
    const off = new Server();
    assert.equal((await off.call('POST', '/v1/coach', request())).status, 503);

    const s = new Server();
    s.ai = new FakeAi({ response: '1. ok' });
    s.coachCap = 2;
    assert.equal((await s.call('POST', '/v1/coach', request())).status, 200);
    assert.equal((await s.call('POST', '/v1/coach', request())).status, 200);
    const third = await s.call('POST', '/v1/coach', request());
    assert.equal(third.status, 429);
    assert.equal(third.body.error, 'coach_busy');
    s.advance(24 * 60 * 60 * 1000);
    assert.equal((await s.call('POST', '/v1/coach', request())).status, 200);
  });
});

describe('number guard', () => {
  it('treats 2.5 and 2.500, and Arabic digits, as the same number', () => {
    assert.deepEqual([...numbersIn('٢٫٥ و 2.500 و 07')], ['2.5', '7']);
    assert.ok(onlyGivenNumbers('وفّر ٢٫٦٤٠ د.ب', ['2.640 د.ب']));
    assert.ok(!onlyGivenNumbers('وفّر 3 د.ب و 12 مرة', ['2.640']));
    assert.ok(onlyGivenNumbers('1. a\n2. b', []));
  });
});
