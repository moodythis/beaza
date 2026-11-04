// AI savings plan (SRS FR-8.8). The phone sends only totals it computed:
// no shop names, no message text, no account digits, no dates. Anything
// else in the request is refused. The model writes a short plan from those
// numbers; every number in its reply must be one it was given, otherwise a
// plan written by rules is returned instead. Nothing is stored except a
// per-day request count, and the request body is never logged.
import type { D1Like } from './d1.ts';
import { HttpError, isObject } from './validate.ts';

/** The version of the AI consent text the phone must have shown. */
export const COACH_CONSENT_VERSION = '2026-11-04';

/** Workers AI model: multilingual, "zero data retention" in Cloudflare's
 * model catalog (checked 4 Nov 2026). */
export const COACH_MODEL = '@cf/google/gemma-4-26b-a4b-it';

/** Plans per UTC day for everyone together, to stay inside the free
 * Workers AI allowance (10,000 neurons a day; one plan is roughly 17). */
export const COACH_DAILY_CAP = 300;

export interface AiLike {
  run(model: string, input: unknown, options?: unknown): Promise<unknown>;
}

const BUCKETS = new Set([
  'food', 'groceries', 'shopping', 'transport', 'bills', 'health',
  'entertainment', 'education', 'other', 'transfer', 'unsorted',
]);
const DISCRETIONARY = ['food', 'shopping', 'entertainment'];

const MAX_FILS = 100_000_000; // BHD 100,000

export type CoachInput = {
  language: 'ar' | 'en';
  weekTotalFils: number;
  previousWeekTotalFils: number;
  dailyLimitFils: number;
  daysOverLimit: number;
  smallCount: number;
  smallFils: number;
  categories: { category: string; fils: number; percent: number }[];
};

const KEYS = [
  'consent', 'language', 'week_total_fils', 'previous_week_total_fils',
  'daily_limit_fils', 'days_over_limit', 'small_purchases_count',
  'small_purchases_fils', 'categories',
];

function int(v: unknown, max: number, code: string): number {
  if (typeof v !== 'number' || !Number.isInteger(v) || v < 0 || v > max) {
    throw new HttpError(400, code);
  }
  return v;
}

export function checkCoachInput(body: Record<string, unknown>): CoachInput {
  for (const k of Object.keys(body)) {
    if (!KEYS.includes(k)) throw new HttpError(400, 'unexpected_field', { field: k });
  }
  if (body.consent !== COACH_CONSENT_VERSION) {
    throw new HttpError(400, 'consent_required', { version: COACH_CONSENT_VERSION });
  }
  if (body.language !== 'ar' && body.language !== 'en') {
    throw new HttpError(400, 'bad_language');
  }
  const list = body.categories;
  if (!Array.isArray(list) || list.length > BUCKETS.size) {
    throw new HttpError(400, 'bad_categories');
  }
  const seen = new Set<string>();
  const categories = list.map((c) => {
    if (!isObject(c) || Object.keys(c).some((k) => !['category', 'fils', 'percent'].includes(k))) {
      throw new HttpError(400, 'bad_categories');
    }
    const category = c.category;
    if (typeof category !== 'string' || !BUCKETS.has(category) || seen.has(category)) {
      throw new HttpError(400, 'bad_categories');
    }
    seen.add(category);
    return {
      category,
      fils: int(c.fils, MAX_FILS, 'bad_categories'),
      percent: int(c.percent, 100, 'bad_categories'),
    };
  });
  return {
    language: body.language,
    weekTotalFils: int(body.week_total_fils, MAX_FILS, 'bad_number'),
    previousWeekTotalFils: int(body.previous_week_total_fils, MAX_FILS, 'bad_number'),
    dailyLimitFils: int(body.daily_limit_fils, MAX_FILS, 'bad_number'),
    daysOverLimit: int(body.days_over_limit, 7, 'bad_number'),
    smallCount: int(body.small_purchases_count, 10_000, 'bad_number'),
    smallFils: int(body.small_purchases_fils, MAX_FILS, 'bad_number'),
    categories: categories.sort((a, b) => b.fils - a.fils),
  };
}

export function money(fils: number, ar: boolean): string {
  const s = `${Math.floor(fils / 1000)}.${String(fils % 1000).padStart(3, '0')}`;
  return ar ? `${s} د.ب` : `BHD ${s}`;
}

const NAMES_AR: Record<string, string> = {
  food: 'الأكل والمطاعم', groceries: 'البقالة', shopping: 'التسوق',
  transport: 'المواصلات', bills: 'الفواتير', health: 'الصحة',
  entertainment: 'الترفيه', education: 'الدراسة', other: 'أشياء ثانية',
  transfer: 'التحويلات', unsorted: 'غير مصنّف',
};

function name(category: string, ar: boolean): string {
  return ar ? (NAMES_AR[category] ?? category) : category;
}

/** The facts the model may use, each with its numbers already worked out
 * here in integers (the model does no arithmetic). */
export function facts(x: CoachInput): { lines: string[]; trim?: { category: string; week: number; month: number } } {
  const ar = x.language === 'ar';
  const lines: string[] = [];
  lines.push(ar
    ? `المصروف في آخر 7 أيام: ${money(x.weekTotalFils, true)}`
    : `Spent in the last 7 days: ${money(x.weekTotalFils, false)}`);
  if (x.previousWeekTotalFils > 0) {
    const diff = x.weekTotalFils - x.previousWeekTotalFils;
    const pct = Math.round((Math.abs(diff) * 100) / x.previousWeekTotalFils);
    lines.push(ar
      ? `الأسبوع اللي قبله: ${money(x.previousWeekTotalFils, true)} (${diff >= 0 ? 'زيادة' : 'نقص'} ${pct}٪)`
      : `The week before: ${money(x.previousWeekTotalFils, false)} (${diff >= 0 ? 'up' : 'down'} ${pct}%)`);
  }
  if (x.dailyLimitFils > 0) {
    lines.push(ar
      ? `الحد اليومي: ${money(x.dailyLimitFils, true)}، وتعدّاه ${x.daysOverLimit} من آخر 7 أيام`
      : `Daily limit: ${money(x.dailyLimitFils, false)}; passed on ${x.daysOverLimit} of the last 7 days`);
  }
  if (x.smallCount > 0) {
    lines.push(ar
      ? `مصاريف صغيرة: ${x.smallCount} مرات، مجموعها ${money(x.smallFils, true)}`
      : `Small purchases: ${x.smallCount}, together ${money(x.smallFils, false)}`);
  }
  for (const c of x.categories.slice(0, 5)) {
    lines.push(`${name(c.category, ar)}: ${money(c.fils, ar)} (${c.percent}${ar ? '٪' : '%'})`);
  }
  const top = x.categories.find((c) => DISCRETIONARY.includes(c.category) && c.fils >= 1000);
  let trim: { category: string; week: number; month: number } | undefined;
  if (top) {
    const week = Math.floor(top.fils / 5);
    trim = { category: top.category, week, month: week * 4 };
    lines.push(ar
      ? `لو قلّ صرف ${name(top.category, true)} 20٪: توفير تقريباً ${money(week, true)} بالأسبوع، و${money(week * 4, true)} في 4 أسابيع`
      : `If ${top.category} spending drops by 20%: about ${money(week, false)} kept a week, ${money(week * 4, false)} in 4 weeks`);
  }
  return { lines, trim };
}

const SYSTEM = {
  ar: `أنت مساعد توفير في تطبيق بيزة لطلاب الجامعة في البحرين.
اكتب خطة توفير قصيرة بلهجة خليجية بسيطة وودّية: 3 أو 4 خطوات مرقّمة، كل خطوة جملة وحدة عملية.
استخدم فقط الأرقام الموجودة في "الحقائق" وانسخها كما هي. لا تحسب ولا تخترع أي رقم جديد.
لا تنصح بقروض أو استثمار أو بنوك أو منتجات مالية، ولا تلوم الشخص. أقل من 120 كلمة.
ابدأ مباشرة بالخطوة 1، بدون تحية وبدون جملة ختامية.`,
  en: `You are the savings helper in Beaza, an app for university students in Bahrain.
Write a short, friendly savings plan: 3 or 4 numbered steps, one practical sentence each.
Use only the numbers in FACTS, copied exactly. Never calculate or invent a number.
No loans, investments, banks or financial products, and no blame. Under 120 words.
Start directly with step 1: no greeting and no closing line.`,
};

/** Numbers in a text, written one way: Arabic digits to ASCII, "2.500" and
 * "2.5" the same, "07" and "7" the same. */
export function numbersIn(text: string): Set<string> {
  const ascii = text
    .replace(/[٠-٩]/g, (d) => String(d.charCodeAt(0) - 0x0660))
    .replace(/[۰-۹]/g, (d) => String(d.charCodeAt(0) - 0x06f0))
    .replace(/٫/g, '.');
  const out = new Set<string>();
  for (const m of ascii.matchAll(/\d+(?:\.\d+)?/g)) {
    let n = m[0];
    if (n.includes('.')) {
      n = n.replace(/0+$/, '').replace(/\.$/, '');
    }
    const [whole, frac] = n.split('.');
    out.add(frac === undefined ? String(Number(whole)) : `${Number(whole)}.${frac}`);
  }
  return out;
}

/** True when every number in [reply] was given (or is a step number 1-7). */
export function onlyGivenNumbers(reply: string, given: string[]): boolean {
  const allowed = new Set(['1', '2', '3', '4', '5', '6', '7']);
  for (const g of given) for (const n of numbersIn(g)) allowed.add(n);
  for (const n of numbersIn(reply)) if (!allowed.has(n)) return false;
  return true;
}

/** A plan written by rules, used when the model is off, busy or wrong. */
export function rulePlan(x: CoachInput): string {
  const ar = x.language === 'ar';
  const { trim } = facts(x);
  const steps: string[] = [];
  if (trim) {
    steps.push(ar
      ? `خفّف ${name(trim.category, true)} 20٪ هالأسبوع: توفّر تقريباً ${money(trim.week, true)}، يعني ${money(trim.month, true)} في 4 أسابيع.`
      : `Cut ${trim.category} by 20% this week: about ${money(trim.week, false)} kept, ${money(trim.month, false)} in 4 weeks.`);
  }
  if (x.smallCount >= 5) {
    steps.push(ar
      ? `عندك ${x.smallCount} مصاريف صغيرة مجموعها ${money(x.smallFils, true)}: اختار يومين بالأسبوع بدونها.`
      : `${x.smallCount} small purchases came to ${money(x.smallFils, false)}: pick two days a week without them.`);
  }
  if (x.dailyLimitFils > 0 && x.daysOverLimit > 0) {
    steps.push(ar
      ? `تعدّيت حدك ${x.daysOverLimit} من 7 أيام: شيّك على الباقي قبل أي مصروف مو ضروري.`
      : `You passed your limit on ${x.daysOverLimit} of 7 days: check what is left before anything you don't need.`);
  }
  if (x.dailyLimitFils === 0) {
    steps.push(ar
      ? 'حط حد يومي في بيزة علشان ينبهك قبل لا تتعداه.'
      : 'Set a daily limit in Beaza so it can warn you before you pass it.');
  }
  steps.push(ar
    ? 'آخر الأسبوع افتح «أين ذهبت أموالي؟» وقارن.'
    : 'At the end of the week, open "Where did my money go?" and compare.');
  return steps.slice(0, 4).map((s, i) => `${i + 1}. ${s}`).join('\n');
}

function textOf(r: unknown): string | null {
  if (!isObject(r)) return null;
  if (typeof r.response === 'string') return r.response;
  const choices = r.choices;
  if (Array.isArray(choices) && isObject(choices[0])) {
    const message = choices[0].message;
    if (isObject(message) && typeof message.content === 'string') return message.content;
  }
  return null;
}

/** Counts this request against today's cap; false when the cap is reached. */
async function allow(db: D1Like, now: number, cap: number): Promise<boolean> {
  const day = new Date(now).toISOString().slice(0, 10);
  const row = await db
    .prepare(
      'INSERT INTO coach_usage (day, count) VALUES (?, 1) ' +
        'ON CONFLICT (day) DO UPDATE SET count = count + 1 RETURNING count',
    )
    .bind(day)
    .first<{ count: number }>();
  return (row?.count ?? 0) <= cap;
}

export async function coach(
  body: Record<string, unknown>,
  db: D1Like,
  ai: AiLike | undefined,
  now: number,
  cap = COACH_DAILY_CAP,
): Promise<Record<string, unknown>> {
  const x = checkCoachInput(body);
  if (!ai) throw new HttpError(503, 'coach_disabled');
  if (!(await allow(db, now, cap))) throw new HttpError(429, 'coach_busy');
  const ar = x.language === 'ar';
  const { lines } = facts(x);
  let reply: string | null = null;
  try {
    const result = await ai.run(COACH_MODEL, {
      messages: [
        { role: 'system', content: SYSTEM[x.language] },
        { role: 'user', content: `${ar ? 'الحقائق' : 'FACTS'}:\n- ${lines.join('\n- ')}` },
      ],
      max_tokens: 400,
      temperature: 0.4,
      chat_template_kwargs: { enable_thinking: false },
    });
    reply = textOf(result)?.replace(/<think>[\s\S]*?<\/think>/g, '').trim() ?? null;
  } catch {
    reply = null;
  }
  if (reply && reply.length <= 1200 && onlyGivenNumbers(reply, lines)) {
    return { plan: reply, source: 'model', model: COACH_MODEL, facts: lines };
  }
  return { plan: rulePlan(x), source: 'rules', facts: lines };
}
