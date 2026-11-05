import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { firstOf, GeminiAi, geminiBody, geminiText } from '../src/gemini.ts';

function fakeFetch(status: number, body: unknown) {
  const calls: { url: string; init: any }[] = [];
  const f = async (url: string, init: any) => {
    calls.push({ url, init });
    return { ok: status === 200, status, json: async () => body };
  };
  return { f, calls };
}

const reply = (text: string) => ({ candidates: [{ content: { parts: [{ text }] } }] });

describe('Gemini first, Workers AI behind it', () => {
  it('chat messages become systemInstruction and contents', () => {
    const b = geminiBody({
      messages: [{ role: 'system', content: 'rules' }, { role: 'user', content: 'FACTS' }],
      max_tokens: 300,
      temperature: 0,
    }, 'gemini-2.5-flash') as any;
    assert.deepEqual(b.systemInstruction, { parts: [{ text: 'rules' }] });
    assert.deepEqual(b.contents, [{ role: 'user', parts: [{ text: 'FACTS' }] }]);
    assert.equal(b.generationConfig.maxOutputTokens, 300);
    assert.equal(b.generationConfig.temperature, 0);
    assert.deepEqual(b.generationConfig.thinkingConfig, { thinkingBudget: 0 });
  });

  it('newer models get a thinking level, no temperature, and room for thinking', () => {
    const b = geminiBody({ messages: [{ role: 'user', content: 'FACTS' }], max_tokens: 300, temperature: 0 }) as any;
    assert.deepEqual(b.generationConfig, { maxOutputTokens: 2048, thinkingConfig: { thinkingLevel: 'low' } });
  });

  it('a photo becomes inline data; a recording asks for the words', () => {
    const img = geminiBody({
      messages: [{ role: 'user', content: [
        { type: 'text', text: 'read' },
        { type: 'image_url', image_url: { url: 'data:image/jpeg;base64,QUJD' } },
      ] }],
    }) as any;
    assert.deepEqual(img.contents[0].parts[1], { inline_data: { mime_type: 'image/jpeg', data: 'QUJD' } });
    const voice = geminiBody({ audio: 'QUJD', language: 'ar' }) as any;
    assert.deepEqual(voice.contents[0].parts[1], { inline_data: { mime_type: 'audio/mp4', data: 'QUJD' } });
    assert.match(voice.contents[0].parts[0].text, /Arabic/);
  });

  it('a busy model hands the same call to the next free model', async () => {
    const calls: string[] = [];
    const f = async (url: string) => {
      calls.push(url);
      const busy = calls.length === 1;
      return { ok: !busy, status: busy ? 503 : 200, json: async () => (busy ? { error: { status: 'UNAVAILABLE' } } : reply('1. ok')) };
    };
    const g = new GeminiAi('K', 'gemini-3.8-flash', f);
    assert.deepEqual(await g.run('@cf/x', { messages: [{ role: 'user', content: 'hi' }] }), { response: '1. ok', provider: 'gemini' });
    assert.equal(calls.length, 2);
    assert.match(calls[1], /gemini-3\.5-flash-lite/);
  });

  it('a bad key is not retried on other models', async () => {
    const { f, calls } = fakeFetch(400, { error: { status: 'INVALID_ARGUMENT', message: 'API key not valid' } });
    await assert.rejects(new GeminiAi('K', 'gemini-3.8-flash', f).run('@cf/x', { messages: [] }), /gemini 400/);
    assert.equal(calls.length, 1);
  });

  it('the key goes in a header, never the URL; answers keep the callers\' shapes', async () => {
    const { f, calls } = fakeFetch(200, reply('1. ok'));
    const g = new GeminiAi('SECRET', 'gemini-2.5-flash', f);
    assert.deepEqual(await g.run('@cf/x', { messages: [{ role: 'user', content: 'hi' }] }), { response: '1. ok', provider: 'gemini' });
    assert.equal(calls[0].url.includes('SECRET'), false);
    assert.equal(calls[0].init.headers['x-goog-api-key'], 'SECRET');
    assert.match(calls[0].url, /models\/gemini-2\.5-flash:generateContent$/);
    assert.deepEqual(await g.run('@cf/whisper', { audio: 'QUJD', language: 'ar' }), { text: '1. ok', provider: 'gemini' });
  });

  it('quota or errors fall back to Workers AI with the same call', async () => {
    const { f } = fakeFetch(429, { error: { message: 'quota' } });
    const workers = { calls: [] as unknown[], async run(model: string, input: unknown) { this.calls.push([model, input]); return { response: 'from workers' }; } };
    const ai = firstOf(new GeminiAi('K', undefined, f), workers)!;
    assert.deepEqual(await ai.run('@cf/google/gemma', { messages: [] }), { response: 'from workers' });
    assert.equal(workers.calls.length, 1);
  });

  it('no key: Workers AI only', () => {
    const workers = { async run() { return {}; } };
    assert.equal(firstOf(undefined, workers), workers);
    assert.equal(geminiText({ candidates: [] }), null);
  });
});
