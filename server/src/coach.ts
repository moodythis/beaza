// AI savings plan (SRS FR-8.8). The phone sends totals it computed, shop
// names, and this week's purchases (weekday, hour, amount, category, shop).
// Nothing that identifies the person: no message text, no account, card or
// phone digits, no CPR, no references, no calendar dates, no transfer
// recipients. Anything else in the request is refused. The model writes a short plan from those
// numbers; every number in its reply must be one it was given, otherwise a
// plan written by rules is returned instead. Nothing is stored except a
// per-day request count, and the request body is never logged.
import type { D1Like } from './d1.ts';
import { HttpError, isObject } from './validate.ts';
import { providerOf } from './gemini.ts';

/** The version of the AI consent text the phone must have shown. */
export const COACH_CONSENT_VERSION = '2026-11-06.2';

/** At most this many recent purchases (phone: kCoachMaxRecent). */
export const COACH_MAX_RECENT = 40;

const WEEKDAYS = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

/** At most this many shops (phone: kCoachMaxShops). */
export const COACH_MAX_SHOPS = 5;

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
/** A category is worth trimming only from 10 BHD a week: below that, 20% is
 * pennies and the advice would be silly. */
const TRIM_MIN_FILS = 10000;

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
  shops: { name: string; fils: number; count: number }[];
  recent: { weekday: string; hour: number; fils: number; category: string; shop?: string }[];
  lateCount: number;
  lateFils: number;
  weekendFils: number;
  /** Only when the limit is worked out from income; never the income. */
  month?: { leftFils: number; days: number };
};

const KEYS = [
  'consent', 'language', 'week_total_fils', 'previous_week_total_fils',
  'daily_limit_fils', 'days_over_limit', 'small_purchases_count',
  'small_purchases_fils', 'categories', 'shops', 'recent', 'late_night_count',
  'late_night_fils', 'weekend_fils', 'month_left_fils', 'days_left_in_month',
];

/** A shop name may carry no digit of any script (no card, phone, branch or
 * reference number can ride along), and nothing that looks like an email
 * or a phone number. */
export function shopName(v: unknown, code = 'bad_shops'): string {
  if (typeof v !== 'string') throw new HttpError(400, code);
  const s = v.trim();
  if (s.length < 2 || s.length > 40 || /[0-9\u0660-\u0669\u06F0-\u06F9@+]/.test(s) || /[\u0000-\u001F]/.test(s)) {
    throw new HttpError(400, code);
  }
  return s;
}

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
  const shopList = body.shops ?? [];
  if (!Array.isArray(shopList) || shopList.length > COACH_MAX_SHOPS) {
    throw new HttpError(400, 'bad_shops');
  }
  const shops = shopList.map((x) => {
    if (!isObject(x) || Object.keys(x).some((k) => !['name', 'fils', 'count'].includes(k))) {
      throw new HttpError(400, 'bad_shops');
    }
    return {
      name: shopName(x.name),
      fils: int(x.fils, MAX_FILS, 'bad_shops'),
      count: int(x.count, 10_000, 'bad_shops'),
    };
  });
  const recentList = body.recent ?? [];
  if (!Array.isArray(recentList) || recentList.length > COACH_MAX_RECENT) {
    throw new HttpError(400, 'bad_recent');
  }
  const recent = recentList.map((x) => {
    if (!isObject(x) || Object.keys(x).some((k) => !['weekday', 'hour', 'fils', 'category', 'shop'].includes(k))) {
      throw new HttpError(400, 'bad_recent');
    }
    if (typeof x.weekday !== 'string' || !WEEKDAYS.includes(x.weekday)) throw new HttpError(400, 'bad_recent');
    if (typeof x.category !== 'string' || !BUCKETS.has(x.category)) throw new HttpError(400, 'bad_recent');
    return {
      weekday: x.weekday,
      hour: int(x.hour, 23, 'bad_recent'),
      fils: int(x.fils, MAX_FILS, 'bad_recent'),
      category: x.category,
      ...(x.shop === undefined ? {} : { shop: shopName(x.shop, 'bad_recent') }),
    };
  });
  return {
    language: body.language,
    recent,
    weekTotalFils: int(body.week_total_fils, MAX_FILS, 'bad_number'),
    previousWeekTotalFils: int(body.previous_week_total_fils, MAX_FILS, 'bad_number'),
    dailyLimitFils: int(body.daily_limit_fils, MAX_FILS, 'bad_number'),
    daysOverLimit: int(body.days_over_limit, 7, 'bad_number'),
    smallCount: int(body.small_purchases_count, 10_000, 'bad_number'),
    smallFils: int(body.small_purchases_fils, MAX_FILS, 'bad_number'),
    categories: categories.sort((a, b) => b.fils - a.fils),
    shops: shops.sort((a, b) => b.fils - a.fils),
    lateCount: int(body.late_night_count ?? 0, 10_000, 'bad_number'),
    lateFils: int(body.late_night_fils ?? 0, MAX_FILS, 'bad_number'),
    weekendFils: int(body.weekend_fils ?? 0, MAX_FILS, 'bad_number'),
    month: monthOf(body),
  };
}

function monthOf(body: Record<string, unknown>): CoachInput['month'] {
  const has = body.month_left_fils !== undefined || body.days_left_in_month !== undefined;
  if (!has) return undefined;
  const days = int(body.days_left_in_month, 30, 'bad_number');
  if (days < 1) throw new HttpError(400, 'bad_number');
  return { leftFils: int(body.month_left_fils, MAX_FILS, 'bad_number'), days };
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

const DAYS_AR: Record<string, string> = {
  mon: 'الاثنين', tue: 'الثلاثاء', wed: 'الأربعاء', thu: 'الخميس',
  fri: 'الجمعة', sat: 'السبت', sun: 'الأحد',
};

function name(category: string, ar: boolean): string {
  return ar ? (NAMES_AR[category] ?? category) : category;
}

/** Most of the week is "unsorted" (and not a trivial amount). */
function unsortedHeavy(x: CoachInput): boolean {
  const u = x.categories.find((c) => c.category === 'unsorted');
  return !!u && u.fils >= 2000 && u.percent >= 40;
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
  if (x.lateCount > 0) {
    lines.push(ar
      ? `مشتريات آخر الليل (10 بالليل لين 3 الفجر): ${x.lateCount} مرات، مجموعها ${money(x.lateFils, true)}`
      : `Late-night purchases (10 pm to 3 am): ${x.lateCount}, together ${money(x.lateFils, false)}`);
  }
  if (x.weekendFils > 0 && x.weekTotalFils > 0) {
    const pct = Math.round((x.weekendFils * 100) / x.weekTotalFils);
    lines.push(ar
      ? `الجمعة والسبت: ${money(x.weekendFils, true)} (${pct}٪ من الأسبوع)`
      : `Friday and Saturday: ${money(x.weekendFils, false)} (${pct}% of the week)`);
  }
  if (x.month) {
    const perDay = Math.floor(x.month.leftFils / x.month.days);
    lines.push(ar
      ? `الباقي لآخر الشهر: ${money(x.month.leftFils, true)} لـ ${x.month.days} يوم، يعني تقريباً ${money(perDay, true)} باليوم`
      : `Left until the end of the month: ${money(x.month.leftFils, false)} for ${x.month.days} days, about ${money(perDay, false)} a day`);
  }
  for (const sh of x.shops) {
    lines.push(ar
      ? `محل ${sh.name}: ${money(sh.fils, true)} (${sh.count} مرات)`
      : `Shop ${sh.name}: ${money(sh.fils, false)} (${sh.count} times)`);
  }
  if (x.recent.length > 0) {
    lines.push(ar ? 'مشتريات هالأسبوع (الأحدث أولاً):' : "This week's purchases (newest first):");
    for (const p of x.recent) {
      const hh = String(p.hour).padStart(2, '0');
      const day = ar ? DAYS_AR[p.weekday] : p.weekday.charAt(0).toUpperCase() + p.weekday.slice(1);
      lines.push(`  ${day} ${hh}:00 · ${name(p.category, ar)} · ${p.shop ?? '-'} · ${money(p.fils, ar)}`);
    }
  }
  if (unsortedHeavy(x)) {
    lines.push(ar
      ? 'أغلب المصروف غير مصنّف: صنّفه أول علشان تعرف وين تروح فلوسك'
      : 'Most of the spending is not sorted into categories: sort it first to see where the money goes');
  }
  const top = x.categories.find((c) => DISCRETIONARY.includes(c.category) && c.fils >= TRIM_MIN_FILS);
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
لا تنصح بتخفيف فئة إلا إذا في "الحقائق" سطر "لو قلّ صرف"؛ وإلا لا تقترح تخفيف أي شي، وقل إن صرفه معقول إذا المبالغ صغيرة.
إذا في سطر "غير مصنّف" خل الخطوة 1 تصنيف المصاريف.
تقدر تذكر أسماء المحلات وأوقات المشتريات من الحقائق إذا تفيد النصيحة (مثل محل يتكرر كل يوم، أو طلبات آخر الليل). انسخ الأسماء كما هي.
لا تنصح بقروض أو استثمار أو بنوك أو منتجات مالية، ولا تلوم الشخص. أقل من 120 كلمة.
ابدأ مباشرة بالخطوة 1، بدون تحية وبدون جملة ختامية.`,
  en: `You are the savings helper in Beaza, an app for university students in Bahrain.
Write a short, friendly savings plan: 3 or 4 numbered steps, one practical sentence each.
Use only the numbers in FACTS, copied exactly. Never calculate or invent a number.
Suggest cutting a category only if FACTS has an "If ... spending drops" line; otherwise suggest no cuts, and say the spending looks reasonable if the amounts are small.
If FACTS says the spending is not sorted, make step 1 sorting it.
You may name shops and purchase times from FACTS when it helps (for example the same shop every day, or late-night orders); copy names exactly.
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
  if (unsortedHeavy(x)) {
    steps.push(ar
      ? 'أغلب مصروفك غير مصنّف: صنّفه من القائمة علشان تعرف وين تروح فلوسك.'
      : 'Most of your spending is not sorted: give each item a category to see where the money goes.');
  }
  if (trim) {
    steps.push(ar
      ? `خفّف ${name(trim.category, true)} 20٪ هالأسبوع: توفّر تقريباً ${money(trim.week, true)}، يعني ${money(trim.month, true)} في 4 أسابيع.`
      : `Cut ${trim.category} by 20% this week: about ${money(trim.week, false)} kept, ${money(trim.month, false)} in 4 weeks.`);
  }
  if (x.lateCount >= 3) {
    steps.push(ar
      ? `${x.lateCount} مشتريات آخر الليل بمجموع ${money(x.lateFils, true)}: حط قاعدة ما تطلب بعد 10 بالليل.`
      : `${x.lateCount} late-night purchases came to ${money(x.lateFils, false)}: make a rule of no orders after 10 pm.`);
  }
  const often = x.shops.find((sh) => sh.count >= 4);
  if (often) {
    steps.push(ar
      ? `رحت ${often.name} ${often.count} مرات هالأسبوع بمجموع ${money(often.fils, true)}: جرّب تقللها مرتين.`
      : `You went to ${often.name} ${often.count} times this week, ${money(often.fils, false)} in all: try two fewer visits.`);
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

export function textOf(r: unknown): string | null {
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
export async function allow(db: D1Like, now: number, cap: number): Promise<boolean> {
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
  let provider = 'workers-ai';
  let aiError: string | undefined;
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
    provider = providerOf(result);
  } catch (e) {
    reply = null;
    aiError = String(e instanceof Error ? e.message : e).slice(0, 200);
  }
  if (reply && reply.length <= 1200 && onlyGivenNumbers(reply, lines)) {
    return { plan: reply, source: 'model', model: COACH_MODEL, provider, facts: lines };
  }
  return {
    plan: rulePlan(x),
    source: 'rules',
    facts: lines,
    // Why the model's plan was not used, for the person to send us.
    reason: aiError ?? (reply ? 'unchecked_number' : 'empty_reply'),
  };
}
