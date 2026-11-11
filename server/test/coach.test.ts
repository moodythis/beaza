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
    assert.match(res.body.plan, /لو خففت التسوق شوي، 20٪ بس/);
    assert.ok(onlyGivenNumbers(res.body.plan, res.body.facts));
  });

  it('a failing or empty model also gives the rule plan', async () => {
    for (const reply of [new Error('busy'), {}, { choices: [] }]) {
      const s = new Server();
      s.ai = new FakeAi(reply);
      const res = await s.call('POST', '/v1/coach', request({ language: 'en' }));
      assert.equal(res.status, 200);
      assert.equal(res.body.source, 'rules');
      assert.match(res.body.plan, /If you eased off shopping by just 20%/);
    }
  });

  it('does not suggest cutting a small category (20% of 1.8 BHD is pennies)', async () => {
    const s = new Server();
    s.ai = new FakeAi(new Error('model off'));
    const res = await s.call('POST', '/v1/coach', request({
      language: 'en',
      week_total_fils: 4000,
      categories: [{ category: 'food', fils: 1800, percent: 45 }, { category: 'transport', fils: 2200, percent: 55 }],
    }));
    assert.equal(res.body.source, 'rules');
    assert.doesNotMatch(res.body.plan, /Cut food/);
    assert.doesNotMatch(res.body.plan, /0\.360/);
  });

  it('says to sort the spending first when most of it is unsorted', async () => {
    const s = new Server();
    s.ai = new FakeAi(new Error('model off'));
    const res = await s.call('POST', '/v1/coach', request({
      language: 'en',
      week_total_fils: 200000,
      categories: [{ category: 'unsorted', fils: 176000, percent: 88 }, { category: 'food', fils: 1800, percent: 1 }],
    }));
    assert.match(res.body.plan, /^Most of your spending isn't sorted yet/);
    assert.ok(res.body.facts.some((l: string) => /not sorted/.test(l)));
  });

  it('takes up to 5 shop names and gives them to the model as facts', async () => {
    const s = new Server();
    const ai = new FakeAi({ response: '1. Fewer visits to TALABAT.' });
    s.ai = ai;
    const res = await s.call('POST', '/v1/coach', request({
      language: 'en',
      shops: [{ name: 'TALABAT', fils: 9200, count: 4 }, { name: 'COSTA COFFEE', fils: 5400, count: 3 }],
    }));
    assert.equal(res.status, 200);
    assert.equal(res.body.source, 'model');
    assert.ok(res.body.facts.includes('Shop TALABAT: BHD 9.200 (4 times)'));
  });

  it('the rule plan names a shop visited 4 times or more', async () => {
    const s = new Server();
    s.ai = new FakeAi(new Error('model off'));
    const res = await s.call('POST', '/v1/coach', request({
      language: 'en',
      shops: [{ name: 'TALABAT', fils: 9200, count: 4 }],
    }));
    assert.match(res.body.plan, /You went to TALABAT 4 times this week \(BHD 9\.200\)/);
  });

  it('refuses shop names with digits, too many shops, or extra fields', async () => {
    const s = new Server();
    s.ai = new FakeAi({ response: '1. ok' });
    const bad = [
      [{ name: 'CARD 4111', fils: 1, count: 1 }],
      [{ name: 'محل ٤٥', fils: 1, count: 1 }],
      [{ name: 'a@b.com', fils: 1, count: 1 }],
      [{ name: 'X', fils: 1, count: 1 }],
      [{ name: 'SHOP', fils: 1, count: 1, last4: '1234' }],
      Array.from({ length: 6 }, (_, i) => ({ name: `SHOP ${'ABCDEF'[i]}`, fils: 1, count: 1 })),
    ];
    for (const shops of bad) {
      const res = await s.call('POST', '/v1/coach', request({ shops }));
      assert.equal(res.status, 400, JSON.stringify(shops));
      assert.equal(res.body.error, 'bad_shops');
    }
  });

  it('an old consent version is refused', async () => {
    const s = new Server();
    s.ai = new FakeAi({ response: '1. ok' });
    const res = await s.call('POST', '/v1/coach', request({ consent: '2026-11-05' }));
    assert.equal(res.status, 400);
    assert.equal(res.body.error, 'consent_required');
  });

  it('late-night, weekend and month-left facts are worked out here', async () => {
    const s = new Server();
    s.ai = new FakeAi(new Error('model off'));
    const res = await s.call('POST', '/v1/coach', request({
      language: 'en',
      late_night_count: 3, late_night_fils: 4500,
      weekend_fils: 9575,
      month_left_fils: 158300, days_left_in_month: 16,
    }));
    assert.equal(res.status, 200);
    assert.ok(res.body.facts.includes('Late-night purchases (10 pm to 3 am): 3, together BHD 4.500'));
    assert.ok(res.body.facts.includes('Weekend (Thursday to Saturday): BHD 9.575 (50% of the week)'));
    assert.ok(res.body.facts.includes('Left until the end of the month: BHD 158.300 for 16 days, about BHD 9.893 a day'));
    assert.match(res.body.plan, /3 late-night purchases \(BHD 4\.500\)/);
  });

  it('month left needs both fields and at least one day', async () => {
    const s = new Server();
    s.ai = new FakeAi({ response: '1. ok' });
    for (const extra of [{ month_left_fils: 1000 }, { month_left_fils: 1000, days_left_in_month: 0 }]) {
      const res = await s.call('POST', '/v1/coach', request(extra));
      assert.equal(res.status, 400);
      assert.equal(res.body.error, 'bad_number');
    }
  });

  it("this week's purchases become facts the model may quote", async () => {
    const s = new Server();
    s.ai = new FakeAi({ response: '1. Skip the Thu 23:00 TALABAT order: BHD 3.500.' });
    const res = await s.call('POST', '/v1/coach', request({
      language: 'en',
      recent: [
        { weekday: 'thu', hour: 23, fils: 3500, category: 'food', shop: 'TALABAT' },
        { weekday: 'wed', hour: 8, fils: 900, category: 'food' },
      ],
    }));
    assert.equal(res.status, 200);
    assert.equal(res.body.source, 'model');
    assert.ok(res.body.facts.includes('  Thu 23:00 · food · TALABAT · BHD 3.500'));
    assert.ok(res.body.facts.includes('  Wed 08:00 · food · - · BHD 0.900'));
  });

  it('refuses purchases with a date, digits in the shop, or a bad hour', async () => {
    const s = new Server();
    s.ai = new FakeAi({ response: '1. ok' });
    const bad = [
      [{ weekday: 'thu', hour: 23, fils: 1, category: 'food', date: '2026-11-05' }],
      [{ weekday: 'thu', hour: 23, fils: 1, category: 'food', shop: 'CPR 880101234' }],
      [{ weekday: 'thu', hour: 24, fils: 1, category: 'food' }],
      [{ weekday: 'someday', hour: 1, fils: 1, category: 'food' }],
      Array.from({ length: 41 }, () => ({ weekday: 'mon', hour: 1, fils: 1, category: 'food' })),
    ];
    for (const recent of bad) {
      const res = await s.call('POST', '/v1/coach', request({ recent }));
      assert.equal(res.status, 400, JSON.stringify(recent).slice(0, 80));
      assert.equal(res.body.error, 'bad_recent');
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
