// Sorting purchases into categories with AI (SRS FR-8.14). The phone sends
// only shop names (digits removed) of purchases it could not sort itself,
// with no amount, date, account or anything about the person; the model
// picks one category for each; anything outside the list is dropped. The
// person can change any category on the phone. Nothing is stored except
// the shared per-day request count.
import type { D1Like } from './d1.ts';
import { allow, COACH_DAILY_CAP, COACH_MODEL, shopName, textOf } from './coach.ts';
import type { AiLike } from './coach.ts';
import { HttpError, isObject } from './validate.ts';

/** The version of the sorting consent the phone must have shown. */
export const CATEGORIZE_CONSENT_VERSION = '2026-11-05';

/** At most this many names in one request. */
export const CATEGORIZE_MAX_NAMES = 30;

export const CATEGORIES = [
  'food', 'groceries', 'shopping', 'transport', 'bills', 'health',
  'entertainment', 'education', 'other',
];

const SYSTEM = `You sort shop names from bank messages in Bahrain into spending categories.
Categories: food (restaurants, cafes, delivery apps like Talabat), groceries (supermarkets, cold stores, bakeries for home), shopping (clothes, electronics, malls, online stores), transport (fuel, taxi, Careem, Uber, parking), bills (telecom, electricity, water, internet, subscriptions), health (pharmacies, clinics, hospitals), entertainment (cinema, games, streaming), education (university, books, courses), other.
Reply with one JSON object only, mapping each given name exactly as written to one category. If you do not recognise a name, use "other".`;

export function checkCategorizeInput(body: Record<string, unknown>): string[] {
  for (const k of Object.keys(body)) {
    if (k !== 'consent' && k !== 'names') throw new HttpError(400, 'unexpected_field', { field: k });
  }
  if (body.consent !== CATEGORIZE_CONSENT_VERSION) {
    throw new HttpError(400, 'consent_required', { version: CATEGORIZE_CONSENT_VERSION });
  }
  const names = body.names;
  if (!Array.isArray(names) || names.length === 0 || names.length > CATEGORIZE_MAX_NAMES) {
    throw new HttpError(400, 'bad_names');
  }
  const out = names.map((n) => shopName(n, 'bad_names'));
  if (new Set(out).size !== out.length) throw new HttpError(400, 'bad_names');
  return out;
}

/** The model's reply as {name: category}, keeping only given names and
 * known categories. Tolerates a ```json fence around the object. */
export function parseCategories(reply: string, names: string[]): Record<string, string> {
  const start = reply.indexOf('{');
  const end = reply.lastIndexOf('}');
  if (start < 0 || end <= start) return {};
  let parsed: unknown;
  try {
    parsed = JSON.parse(reply.slice(start, end + 1));
  } catch {
    return {};
  }
  if (!isObject(parsed)) return {};
  const byUpper = new Map(names.map((n) => [n.toUpperCase(), n]));
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(parsed)) {
    const name = byUpper.get(k.trim().toUpperCase());
    if (name && typeof v === 'string' && CATEGORIES.includes(v.trim().toLowerCase())) {
      out[name] = v.trim().toLowerCase();
    }
  }
  return out;
}

export async function categorize(
  body: Record<string, unknown>,
  db: D1Like,
  ai: AiLike | undefined,
  now: number,
  cap = COACH_DAILY_CAP,
): Promise<Record<string, unknown>> {
  const names = checkCategorizeInput(body);
  if (!ai) throw new HttpError(503, 'coach_disabled');
  if (!(await allow(db, now, cap))) throw new HttpError(429, 'coach_busy');
  let reply: string | null = null;
  try {
    const result = await ai.run(COACH_MODEL, {
      messages: [
        { role: 'system', content: SYSTEM },
        { role: 'user', content: JSON.stringify(names) },
      ],
      max_tokens: 600,
      temperature: 0,
      chat_template_kwargs: { enable_thinking: false },
    });
    reply = textOf(result);
  } catch {
    reply = null;
  }
  return { categories: reply ? parseCategories(reply, names) : {}, model: COACH_MODEL };
}
