// Receipt photos and voice read with AI (SRS FR-8.15), only after the
// person turned it on: the photo (made smaller on the phone) or the voice
// recording goes to Workers AI and is not stored. The phone shows what was
// read for the person to check and change before anything is saved.
import type { D1Like } from './d1.ts';
import { allow, COACH_DAILY_CAP, COACH_MODEL, textOf } from './coach.ts';
import type { AiLike } from './coach.ts';
import { CATEGORIES } from './categorize.ts';
import { HttpError } from './validate.ts';
import { providerOf } from './gemini.ts';

/** The version of the photo and voice consent the phone must have shown. */
export const MEDIA_CONSENT_VERSION = '2026-11-05.3';

export const WHISPER_MODEL = '@cf/openai/whisper-large-v3-turbo';

/** Base64 sizes: a 1600 px JPEG is well under this; 60 s of 32 kbps AAC too. */
const MAX_IMAGE_CHARS = 3_000_000;
const MAX_AUDIO_CHARS = 1_000_000;
const MAX_TEXT = 500;
const MAX_FILS = 10_000_000; // BHD 10,000

function checkKeys(body: Record<string, unknown>, keys: string[]) {
  for (const k of Object.keys(body)) {
    if (!keys.includes(k)) throw new HttpError(400, 'unexpected_field', { field: k });
  }
  if (body.consent !== MEDIA_CONSENT_VERSION) {
    throw new HttpError(400, 'consent_required', { version: MEDIA_CONSENT_VERSION });
  }
  if (body.language !== 'ar' && body.language !== 'en') throw new HttpError(400, 'bad_language');
}

function base64(v: unknown, max: number, code: string): string {
  if (typeof v !== 'string' || v.length < 16 || v.length > max || !/^[A-Za-z0-9+/]+=*$/.test(v)) {
    throw new HttpError(400, code);
  }
  return v;
}

/** The first JSON object or array in a reply (models like ```json fences). */
export function jsonIn(reply: string): unknown {
  const starts = [reply.indexOf('{'), reply.indexOf('[')].filter((i) => i >= 0);
  if (starts.length === 0) return null;
  const start = Math.min(...starts);
  const close = reply[start] === '{' ? '}' : ']';
  const end = reply.lastIndexOf(close);
  if (end <= start) return null;
  try {
    return JSON.parse(reply.slice(start, end + 1));
  } catch {
    return null;
  }
}

/** "1.100", "1.1", 1.1 or "BD 1.100" to fils; null when not an amount. */
export function toFils(v: unknown): number | null {
  const s = typeof v === 'number' ? String(v) : typeof v === 'string' ? v : '';
  const m = s.replace(/[٠-٩]/g, (d) => String(d.charCodeAt(0) - 0x0660)).match(/(\d{1,7})(?:[.,](\d{1,3}))?/);
  if (!m) return null;
  const fils = Number(m[1]) * 1000 + Number((m[2] ?? '').padEnd(3, '0'));
  return fils > 0 && fils <= MAX_FILS ? fils : null;
}

const KINDS = ['purchase', 'refund', 'declined', 'transfer'];

export type AiReceipt = {
  fils: number;
  currency: string;
  shop?: string;
  date?: string;
  time?: string;
  kind: string;
  category?: string;
};

/** Keeps only well-formed fields of what the model read. */
export function cleanReceipt(v: unknown): AiReceipt | null {
  if (typeof v !== 'object' || v === null || Array.isArray(v)) return null;
  const o = v as Record<string, unknown>;
  const fils = toFils(o.total);
  if (fils === null) return null;
  const currency = typeof o.currency === 'string' && /^[A-Za-z]{3}$/.test(o.currency.trim())
    ? o.currency.trim().toUpperCase() : 'BHD';
  const out: AiReceipt = {
    fils,
    currency,
    kind: typeof o.kind === 'string' && KINDS.includes(o.kind) ? o.kind : 'purchase',
  };
  if (typeof o.shop === 'string' && o.shop.trim().length >= 2) out.shop = o.shop.trim().slice(0, 60);
  if (typeof o.category === 'string' && CATEGORIES.includes(o.category.trim().toLowerCase())) {
    out.category = o.category.trim().toLowerCase();
  }
  if (typeof o.date === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(o.date)) out.date = o.date;
  if (typeof o.time === 'string' && /^\d{2}:\d{2}$/.test(o.time)) out.time = o.time;
  return out;
}

const RECEIPT_PROMPT = `Read this receipt or payment screen from Bahrain. Reply with one JSON object only:
{"total": the amount actually paid as a string with 3 decimals like "1.100", "currency": "BHD" or the 3-letter code printed, "shop": the shop or payee name as printed, "date": "YYYY-MM-DD" or null, "time": "HH:MM" (24 h) or null, "kind": "purchase", "refund", "declined" (failed or rejected) or "transfer" (money sent to a person or account), "category": one of ${CATEGORIES.join(', ')} from what was bought}.
Dates in Bahrain are usually day/month/year. Arabic and English text may both appear. If there is no amount, reply {"total": null}.`;

export async function readReceipt(
  body: Record<string, unknown>,
  db: D1Like,
  ai: AiLike | undefined,
  now: number,
  cap = COACH_DAILY_CAP,
): Promise<Record<string, unknown>> {
  checkKeys(body, ['consent', 'language', 'image']);
  const image = base64(body.image, MAX_IMAGE_CHARS, 'bad_image');
  if (!ai) throw new HttpError(503, 'coach_disabled');
  if (!(await allow(db, now, cap))) throw new HttpError(429, 'coach_busy');
  let reply: string | null = null;
  let provider = 'workers-ai';
  try {
    const result = await ai.run(COACH_MODEL, {
      messages: [{
        role: 'user',
        content: [
          { type: 'text', text: RECEIPT_PROMPT },
          { type: 'image_url', image_url: { url: `data:image/jpeg;base64,${image}` } },
        ],
      }],
      max_tokens: 300,
      temperature: 0,
      chat_template_kwargs: { enable_thinking: false },
    });
    reply = textOf(result);
    provider = providerOf(result);
  } catch (e) {
    // Why, so a failure on a real phone can be told apart (no image in it).
    return { receipt: null, reason: 'model_error', detail: String(e).slice(0, 200) };
  }
  if (!reply) return { receipt: null, reason: 'empty_reply', provider };
  const receipt = cleanReceipt(jsonIn(reply));
  if (!receipt) return { receipt: null, reason: 'no_amount', detail: reply.slice(0, 200), provider };
  return { receipt, provider };
}

export type AiDraft = { item: string; fils: number; category?: string };

export function cleanDrafts(v: unknown): AiDraft[] {
  if (!Array.isArray(v)) return [];
  const out: AiDraft[] = [];
  for (const d of v.slice(0, 10)) {
    if (typeof d !== 'object' || d === null) continue;
    const o = d as Record<string, unknown>;
    const fils = typeof o.fils === 'number' && Number.isInteger(o.fils) && o.fils > 0 && o.fils <= MAX_FILS
      ? o.fils : null;
    if (fils === null) continue;
    const item = typeof o.item === 'string' ? o.item.trim().slice(0, 40) : '';
    const draft: AiDraft = { item, fils };
    if (typeof o.category === 'string' && CATEGORIES.includes(o.category)) draft.category = o.category;
    out.push(draft);
  }
  return out;
}

const EXPENSES_PROMPT = `You turn what a person in Bahrain said about cash spending into a list. Reply with one JSON array only:
[{"item": what was bought, in the person's words, "fils": the amount in fils as an integer, "category": one of ${CATEGORIES.join(', ')}}].
Bahraini money: 1 dinar = 1000 fils; ربية = 100 fils; ربيتين = 200; خمس ربيات or نص دينار = 500; ربع دينار = 250; ثلاث ارباع = 750; نص ربية = 50; اربعانه = 25; "دينار ونص" = 1500. A bare number under 100 is dinars, 100 or more is fils.
If nothing was spent, reply [].`;

async function expensesFrom(ai: AiLike, text: string): Promise<AiDraft[]> {
  try {
    const result = await ai.run(COACH_MODEL, {
      messages: [
        { role: 'system', content: EXPENSES_PROMPT },
        { role: 'user', content: text },
      ],
      max_tokens: 400,
      temperature: 0,
      chat_template_kwargs: { enable_thinking: false },
    });
    const reply = textOf(result);
    return reply ? cleanDrafts(jsonIn(reply)) : [];
  } catch {
    return [];
  }
}

export async function readExpenses(
  body: Record<string, unknown>,
  db: D1Like,
  ai: AiLike | undefined,
  now: number,
  cap = COACH_DAILY_CAP,
): Promise<Record<string, unknown>> {
  checkKeys(body, ['consent', 'language', 'text']);
  const text = body.text;
  if (typeof text !== 'string' || text.trim().length === 0 || text.length > MAX_TEXT) {
    throw new HttpError(400, 'bad_text');
  }
  if (!ai) throw new HttpError(503, 'coach_disabled');
  if (!(await allow(db, now, cap))) throw new HttpError(429, 'coach_busy');
  return { drafts: await expensesFrom(ai, text.trim()) };
}

export async function readVoice(
  body: Record<string, unknown>,
  db: D1Like,
  ai: AiLike | undefined,
  now: number,
  cap = COACH_DAILY_CAP,
): Promise<Record<string, unknown>> {
  checkKeys(body, ['consent', 'language', 'audio']);
  const audio = base64(body.audio, MAX_AUDIO_CHARS, 'bad_audio');
  if (!ai) throw new HttpError(503, 'coach_disabled');
  if (!(await allow(db, now, cap))) throw new HttpError(429, 'coach_busy');
  let text = '';
  try {
    const result = await ai.run(WHISPER_MODEL, {
      audio,
      task: 'transcribe',
      language: body.language,
      vad_filter: true,
      initial_prompt: body.language === 'ar'
        ? 'شريت كرك بربيتين وشاورما بـ 800 فلس، ودفعت دينار ونص بترول.'
        : 'Coffee 800 fils and lunch 2 dinars.',
    });
    text = typeof (result as { text?: unknown })?.text === 'string'
      ? ((result as { text: string }).text).trim()
      : '';
  } catch {
    text = '';
  }
  if (!text) return { text: '', drafts: [] };
  return { text: text.slice(0, MAX_TEXT), drafts: await expensesFrom(ai, text.slice(0, MAX_TEXT)) };
}
