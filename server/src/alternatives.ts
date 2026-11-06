// "Cheaper options": for the shops where the person spent most this week,
// the AI suggests a cheaper way to meet the same need (a cheaper kind of
// place, a cheaper chain, making it at home, pick-up instead of delivery).
// It gets only shop names and visit counts (no amounts), under the savings
// plan's consent, and nothing about the person. The AI has no prices, so
// any idea with a number in it is dropped: Beaza never shows a price or an
// offer it cannot check. Nothing is stored except the shared daily count.
import type { D1Like } from './d1.ts';
import { allow, COACH_CONSENT_VERSION, COACH_DAILY_CAP, COACH_MAX_SHOPS, COACH_MODEL, shopName, textOf } from './coach.ts';
import type { AiLike } from './coach.ts';
import { providerOf } from './gemini.ts';
import { HttpError, isObject } from './validate.ts';

export interface AltInput {
  language: 'ar' | 'en';
  shops: { name: string; count: number }[];
}

export interface Alternative {
  shop: string;
  idea: string;
}

const MAX_IDEA = 160;

function int(v: unknown, max: number): number {
  if (typeof v !== 'number' || !Number.isInteger(v) || v < 1 || v > max) {
    throw new HttpError(400, 'bad_shops');
  }
  return v;
}

export function checkAltInput(body: Record<string, unknown>): AltInput {
  for (const k of Object.keys(body)) {
    if (!['consent', 'language', 'shops'].includes(k)) throw new HttpError(400, 'unexpected_field', { field: k });
  }
  if (body.consent !== COACH_CONSENT_VERSION) {
    throw new HttpError(400, 'consent_required', { version: COACH_CONSENT_VERSION });
  }
  if (body.language !== 'ar' && body.language !== 'en') throw new HttpError(400, 'bad_language');
  const list = body.shops;
  if (!Array.isArray(list) || list.length === 0 || list.length > COACH_MAX_SHOPS) {
    throw new HttpError(400, 'bad_shops');
  }
  const shops = list.map((x) => {
    if (!isObject(x) || Object.keys(x).some((k) => !['name', 'count'].includes(k))) {
      throw new HttpError(400, 'bad_shops');
    }
    return { name: shopName(x.name), count: int(x.count, 10_000) };
  });
  if (new Set(shops.map((s) => s.name.toUpperCase())).size !== shops.length) {
    throw new HttpError(400, 'bad_shops');
  }
  return { language: body.language, shops };
}

const SYSTEM = {
  en: `You help a person in Bahrain spend less without giving up what they need.
For each shop below, suggest ONE cheaper way to meet the same need: a cheaper kind of place, a well-known cheaper chain or store in Bahrain, buying in bulk, making it at home, picking up instead of delivery, or a loyalty card.
Never write a price, a percentage, a discount or any number, and never claim an offer exists: you do not know prices.
Reply with a JSON array only: [{"shop": "<the shop name exactly as given>", "idea": "<one short sentence in English>"}].`,
  ar: `أنت تساعد شخصًا في البحرين يصرف أقل بدون ما يتخلى عن اللي يحتاجه.
لكل محل تحت، اقترح طريقة وحدة أرخص لنفس الحاجة: نوع مكان أرخص، أو سلسلة أو محل معروف أرخص في البحرين، أو الشراء بالجملة، أو التحضير في البيت، أو الاستلام بدل التوصيل، أو بطاقة ولاء.
لا تكتب سعرًا ولا نسبة ولا خصمًا ولا أي رقم، ولا تقول إن فيه عرض: أنت ما تعرف الأسعار.
رد بمصفوفة JSON فقط: [{"shop": "<اسم المحل بالضبط مثل ما انكتب>", "idea": "<جملة قصيرة وحدة بالعربي>"}].`,
};

/** The model's ideas, one per given shop, without numbers. */
export function parseAlternatives(reply: string, shops: string[]): Alternative[] {
  const start = reply.indexOf('[');
  const end = reply.lastIndexOf(']');
  if (start < 0 || end <= start) return [];
  let parsed: unknown;
  try {
    parsed = JSON.parse(reply.slice(start, end + 1));
  } catch {
    return [];
  }
  if (!Array.isArray(parsed)) return [];
  const byUpper = new Map(shops.map((n) => [n.toUpperCase(), n]));
  const out: Alternative[] = [];
  const seen = new Set<string>();
  for (const item of parsed) {
    if (!isObject(item) || typeof item.shop !== 'string' || typeof item.idea !== 'string') continue;
    const shop = byUpper.get(item.shop.trim().toUpperCase());
    const idea = item.idea.replace(/\s+/g, ' ').trim();
    if (!shop || seen.has(shop)) continue;
    if (idea.length < 5 || idea.length > MAX_IDEA) continue;
    if (/[0-9٠-٩۰-۹%٪]/.test(idea)) continue;
    seen.add(shop);
    out.push({ shop, idea });
  }
  return out;
}

export async function alternatives(
  body: Record<string, unknown>,
  db: D1Like,
  ai: AiLike | undefined,
  now: number,
  cap = COACH_DAILY_CAP,
): Promise<Record<string, unknown>> {
  const x = checkAltInput(body);
  if (!ai) throw new HttpError(503, 'coach_disabled');
  if (!(await allow(db, now, cap))) throw new HttpError(429, 'coach_busy');
  const names = x.shops.map((s) => s.name);
  try {
    const result = await ai.run(COACH_MODEL, {
      messages: [
        { role: 'system', content: SYSTEM[x.language] },
        {
          role: 'user',
          content: x.shops.map((s) => `- ${s.name} (${s.count}×)`).join('\n'),
        },
      ],
      max_tokens: 500,
      temperature: 0.3,
    });
    const reply = textOf(result) ?? '';
    const ideas = parseAlternatives(reply, names);
    if (ideas.length > 0) return { alternatives: ideas, source: 'model', provider: providerOf(result) };
    return { alternatives: [], source: 'none', reason: reply ? 'unchecked_reply' : 'empty_reply' };
  } catch (e) {
    return {
      alternatives: [],
      source: 'none',
      reason: String(e instanceof Error ? e.message : e).slice(0, 200),
    };
  }
}
