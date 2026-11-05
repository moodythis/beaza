// Google Gemini, the only AI the server uses.
// The key is a Worker secret (GEMINI_API_KEY), never in the app or the
// code. Callers build Workers AI-style inputs; this file puts them into
// Gemini's request shape. When it fails the callers fall back to rules.
import type { AiLike } from './coach.ts';

export const GEMINI_DEFAULT_MODEL = 'gemini-3.8-flash';

/** Tried in order after the first model when it is busy (503), over quota
 * (429), or closed to the key (404): lighter free-tier Flash models. */
export const GEMINI_BACKUP_MODELS = ['gemini-3.5-flash-lite', 'gemini-3.1-flash-lite'];
const RETRY_STATUSES = new Set([404, 429, 500, 503, 504]);

/** How long one model may take before the next is tried, so the phone
 * (which waits 75 s for a plan) gets an answer or a reason in time. */
export const GEMINI_CALL_MS = 20000;

type FetchLike = (url: string, init: { method: string; headers: Record<string, string>; body: string }) =>
  Promise<{ ok: boolean; status: number; json(): Promise<unknown> }>;

type Part = { text: string } | { inline_data: { mime_type: string; data: string } };

/** Gemini 2.x takes a thinking budget and a temperature; from 3.x on the
 * docs say to send a thinking level instead and drop temperature, and the
 * thinking counts toward the output tokens, so the cap is raised. */
export function generationConfig(model: string, temperature: number, maxTokens: number): Record<string, unknown> {
  if (/^gemini-2\./.test(model)) {
    return { temperature, maxOutputTokens: maxTokens, thinkingConfig: { thinkingBudget: 0 } };
  }
  return { maxOutputTokens: Math.max(maxTokens * 4, 2048), thinkingConfig: { thinkingLevel: 'low' } };
}

/** Our Workers AI-style input as a Gemini generateContent body. */
export function geminiBody(input: Record<string, unknown>, model: string = GEMINI_DEFAULT_MODEL): Record<string, unknown> {
  // Speech to text (the Whisper call): the recording plus an instruction.
  if (typeof input.audio === 'string') {
    const lang = input.language === 'ar' ? 'Arabic (Gulf dialect)' : 'English';
    return {
      contents: [{
        role: 'user',
        parts: [
          { text: `Write down exactly what is said in this recording, in ${lang}. Reply with the words only.` },
          { inline_data: { mime_type: 'audio/mp4', data: input.audio } },
        ],
      }],
      generationConfig: generationConfig(model, 0, 400),
    };
  }
  const messages = Array.isArray(input.messages) ? input.messages as { role: string; content: unknown }[] : [];
  const system = messages.filter((m) => m.role === 'system').map((m) => String(m.content)).join('\n');
  const contents = messages.filter((m) => m.role !== 'system').map((m) => ({
    role: m.role === 'assistant' ? 'model' : 'user',
    parts: partsOf(m.content),
  }));
  return {
    ...(system ? { systemInstruction: { parts: [{ text: system }] } } : {}),
    contents,
    generationConfig: generationConfig(
      model,
      typeof input.temperature === 'number' ? input.temperature : 0.4,
      typeof input.max_tokens === 'number' ? input.max_tokens : 400,
    ),
  };
}

function partsOf(content: unknown): Part[] {
  if (typeof content === 'string') return [{ text: content }];
  if (!Array.isArray(content)) return [];
  const parts: Part[] = [];
  for (const c of content as Record<string, unknown>[]) {
    if (c.type === 'text' && typeof c.text === 'string') parts.push({ text: c.text });
    const url = (c.image_url as { url?: unknown } | undefined)?.url;
    if (c.type === 'image_url' && typeof url === 'string') {
      const m = url.match(/^data:([^;]+);base64,(.*)$/);
      if (m) parts.push({ inline_data: { mime_type: m[1], data: m[2] } });
    }
  }
  return parts;
}

/** The text of a Gemini reply, or null. */
export function geminiText(r: unknown): string | null {
  const parts = (r as { candidates?: { content?: { parts?: { text?: unknown }[] } }[] })
    ?.candidates?.[0]?.content?.parts;
  if (!Array.isArray(parts)) return null;
  const text = parts.map((p) => (typeof p.text === 'string' ? p.text : '')).join('').trim();
  return text || null;
}

export class GeminiAi implements AiLike {
  key: string;
  model: string;
  doFetch: FetchLike;

  constructor(key: string, model: string = GEMINI_DEFAULT_MODEL, doFetch?: FetchLike) {
    this.key = key;
    this.model = model;
    this.doFetch = doFetch ?? ((url, init) => fetch(url, { ...init, signal: AbortSignal.timeout(GEMINI_CALL_MS) }));
  }

  async run(_model: string, input: unknown): Promise<unknown> {
    const models = [this.model, ...GEMINI_BACKUP_MODELS.filter((m) => m !== this.model)];
    let last: unknown;
    for (const model of models) {
      try {
        return await this.runOn(model, input);
      } catch (e) {
        last = e;
        const status = (e as { status?: number }).status;
        if (status === undefined || !RETRY_STATUSES.has(status)) throw e;
      }
    }
    throw last;
  }

  async runOn(model: string, input: unknown): Promise<unknown> {
    const i = (input ?? {}) as Record<string, unknown>;
    let res: Awaited<ReturnType<FetchLike>>;
    try {
      res = await this.doFetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
      {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'x-goog-api-key': this.key },
        body: JSON.stringify(geminiBody(i, model)),
      },
    );
    } catch (e) {
      const name = (e as { name?: string }).name;
      if (name !== 'TimeoutError' && name !== 'AbortError') throw e;
      const err = new Error(`gemini timeout ${model}`) as Error & { status?: number };
      err.status = 504;
      throw err;
    }
    if (!res.ok) {
      // Google's own reason ("API key not valid", "quota", "location"), so a
      // failure can be told apart on the phone. It never holds the key.
      let reason = '';
      try {
        const body = (await res.json()) as { error?: { message?: unknown; status?: unknown } };
        reason = [body?.error?.status, body?.error?.message].filter((x) => typeof x === 'string').join(': ');
      } catch {
        reason = '';
      }
      const err = new Error(`gemini ${res.status} ${model}${reason ? ` ${reason.slice(0, 140)}` : ''}`) as Error & { status?: number };
      err.status = res.status;
      throw err;
    }
    const text = geminiText(await res.json());
    if (text === null) throw new Error('gemini empty');
    // The shapes the callers already read: Whisper's {text}, the LLMs' {response}.
    return typeof i.audio === 'string'
      ? { text, provider: 'gemini' }
      : { response: text, provider: 'gemini' };
  }
}

/** Tries [first], then [second] with the same call. */
export function firstOf(first: AiLike | undefined, second: AiLike | undefined): AiLike | undefined {
  if (!first) return second;
  if (!second) return first;
  return {
    async run(model: string, input: unknown, options?: unknown) {
      try {
        return await first.run(model, input, options);
      } catch {
        return second.run(model, input, options);
      }
    },
  };
}

/** Which service answered: "gemini" or "workers-ai". */
export function providerOf(result: unknown): string {
  return (result as { provider?: unknown } | null)?.provider === 'gemini' ? 'gemini' : 'workers-ai';
}

