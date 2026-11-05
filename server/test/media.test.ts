import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { MEDIA_CONSENT_VERSION, WHISPER_MODEL, cleanReceipt, toFils } from '../src/media.ts';
import { Server } from './harness.ts';

class FakeAi {
  calls: { model: string; input: any }[] = [];
  replies: unknown[];
  constructor(...replies: unknown[]) {
    this.replies = replies;
  }
  async run(model: string, input: unknown) {
    this.calls.push({ model, input });
    const r = this.replies.shift();
    if (r instanceof Error) throw r;
    return r;
  }
}

const JPEG = 'AAAA'.repeat(10);

describe('AI reading of receipt photos and voice', () => {
  it('a photo goes to the vision model and comes back as checked fields', async () => {
    const s = new Server();
    const ai = new FakeAi({
      response: '```json\n{"total": "1.100", "currency": "BHD", "shop": "Kids Port Games", "date": "2026-11-03", "time": "22:56", "kind": "purchase"}\n```',
    });
    s.ai = ai;
    const res = await s.call('POST', '/v1/receipt', { consent: MEDIA_CONSENT_VERSION, language: 'ar', image: JPEG });
    assert.equal(res.status, 200);
    assert.deepEqual(res.body.receipt, {
      fils: 1100, currency: 'BHD', shop: 'Kids Port Games', date: '2026-11-03', time: '22:56', kind: 'purchase',
    });
    const content = ai.calls[0].input.messages[0].content;
    assert.equal(content[1].image_url.url, `data:image/jpeg;base64,${JPEG}`);
  });

  it('no amount or a failed model: no receipt, not an error', async () => {
    const s = new Server();
    s.ai = new FakeAi({ response: '{"total": null}' }, new Error('down'));
    for (let i = 0; i < 2; i++) {
      const res = await s.call('POST', '/v1/receipt', { consent: MEDIA_CONSENT_VERSION, language: 'en', image: JPEG });
      assert.equal(res.status, 200);
      assert.equal(res.body.receipt, null);
    }
  });

  it('voice: Whisper writes it down, then the drafts come from the text', async () => {
    const s = new Server();
    const ai = new FakeAi(
      { text: 'شريت كرك بربيتين وشاورما بـ 800 فلس' },
      { response: '[{"item": "كرك", "fils": 200, "category": "food"}, {"item": "شاورما", "fils": 800, "category": "food"}, {"item": "x", "fils": -5}]' },
    );
    s.ai = ai;
    const res = await s.call('POST', '/v1/voice', { consent: MEDIA_CONSENT_VERSION, language: 'ar', audio: JPEG });
    assert.equal(res.status, 200);
    assert.equal(res.body.text, 'شريت كرك بربيتين وشاورما بـ 800 فلس');
    assert.deepEqual(res.body.drafts, [
      { item: 'كرك', fils: 200, category: 'food' },
      { item: 'شاورما', fils: 800, category: 'food' },
    ]);
    assert.equal(ai.calls[0].model, WHISPER_MODEL);
    assert.equal(ai.calls[0].input.language, 'ar');
  });

  it('typed text can be understood too', async () => {
    const s = new Server();
    s.ai = new FakeAi({ response: '[{"item": "بترول", "fils": 1500, "category": "transport"}]' });
    const res = await s.call('POST', '/v1/expenses', { consent: MEDIA_CONSENT_VERSION, language: 'ar', text: 'عبيت بترول بدينار ونص' });
    assert.deepEqual(res.body.drafts, [{ item: 'بترول', fils: 1500, category: 'transport' }]);
  });

  it('refuses without consent, extra fields or a bad picture', async () => {
    const s = new Server();
    s.ai = new FakeAi();
    const cases: [string, Record<string, unknown>, string][] = [
      ['/v1/receipt', { language: 'ar', image: JPEG }, 'consent_required'],
      ['/v1/receipt', { consent: MEDIA_CONSENT_VERSION, language: 'ar', image: 'not base64!' }, 'bad_image'],
      ['/v1/voice', { consent: MEDIA_CONSENT_VERSION, language: 'ar', audio: JPEG, name: 'x' }, 'unexpected_field'],
      ['/v1/expenses', { consent: MEDIA_CONSENT_VERSION, language: 'fr', text: 'x' }, 'bad_language'],
    ];
    for (const [path, body, code] of cases) {
      const res = await s.call('POST', path, body);
      assert.equal(res.status, 400, path);
      assert.equal(res.body.error, code);
    }
  });

  it('amounts and fields are checked', () => {
    assert.equal(toFils('BD 1.100'), 1100);
    assert.equal(toFils('2.5'), 2500);
    assert.equal(toFils(3), 3000);
    assert.equal(toFils('abc'), null);
    assert.equal(cleanReceipt({ total: '1.000', kind: 'weird', date: '03/11/2026' })?.kind, 'purchase');
    assert.equal(cleanReceipt({ total: '1.000', date: '03/11/2026' })?.date, undefined);
  });
});
