import 'dart:math' as math;

import 'package:beaza/domain/use_cases/coach_request.dart';
import 'package:beaza/domain/use_cases/custom_categories.dart';
import 'package:beaza/domain/use_cases/daily_budget.dart';
import 'package:beaza/domain/use_cases/spending_by_category.dart';
import 'package:beaza_assistant/beaza_assistant.dart'
    show
        AiContextSanitizer,
        Metric,
        Period,
        PeriodKind,
        SpendingSummaryBuilder,
        percentOf;
import 'package:beaza_extraction/beaza_extraction.dart';

/// The version of the chat consent text (server: CHAT_CONSENT_VERSION).
const String kChatConsentVersion = '2026-11-14.1';

/// A question is cut to this many characters (server: CHAT_MAX_QUESTION).
const int kChatMaxQuestion = 200;

/// At most this many of the phone's own numbers go with a question.
const int kChatMaxMetrics = 8;

/// The categories the server knows (custom ones count as "other").
const Set<String> _sharedBuckets = {
  'food', 'groceries', 'shopping', 'transport', 'bills', 'health', //
  'entertainment', 'education', 'other', 'transfer', 'unsorted',
};

/// The keys the phone's rules use (server: METRIC_KEYS). A key is shown to the
/// model, so only these names go, never free text.
const Set<String> _metricKeys = {
  'average_fils', 'biggest_fils', 'coffee_count_week', 'coffee_week_fils', //
  'count', 'days', 'days_of_limit', 'days_over', 'days_so_far',
  'delivery_count_week', 'delivery_week_fils', 'diff_fils', 'diff_percent',
  'half_limit_fils', 'late_count_week', 'late_week_fils', 'left_after_fils',
  'limit_after_fils', 'limit_fils', 'limit_now_fils', 'micro_count_week',
  'micro_total_week_fils', 'month_end_fils', 'month_fils', 'month_left_fils',
  'over_fils', 'percent_used', 'period_days', 'price_fils', 'remaining_fils',
  'save_days', 'shop_count', 'shop_fils', 'spent_today_fils',
  'total_fils', 'week_before_fils', 'week_fils', 'weekend_week_fils',
};

bool _keyOk(String key) {
  if (_metricKeys.contains(key)) return true;
  final bucket = _bucketInKey.firstMatch(key)?.group(1);
  return bucket != null && _sharedBuckets.contains(bucket);
}

/// A number as the phone writes it (server: DISPLAY): never free text.
final RegExp _displayOk =
    RegExp(r'^-?(?:BHD )?\d{1,9}(?:\.\d{1,3})?(?: (?:fils|فلس|د\.ب))?$');

/// Digit runs of seven or more in any script, and a short number after a
/// card or account word, which the shared sanitizer only covers for
/// Western digits.
final RegExp _anyLongNumber = RegExp(
    r'[0-9٠-٩۰-۹](?:[\s-]?[0-9٠-٩۰-۹]){6,}');
final RegExp _anyCardNumber = RegExp(
  r'(?<![A-Za-z])((?:visa|master|mada)(?:card)?|card|account|iban|acc|بطاق[هة]|حساب|رقم|فيزا|ماستر)(?![A-Za-z])'
  r'[\s:#.\-]{0,3}(?:(?:no|number|num|ending|رقم)[\s:#.\-]{0,3})?[0-9٠-٩۰-۹Xx*]{3,}',
  caseSensitive: false,
  unicode: true,
);
final RegExp _bucketInKey = RegExp(r'^(?:bucket|trim)_(.+?)(?:_fils|_percent)$');

/// The person's question as it may be sent: contact and account details
/// masked, one line, at most [kChatMaxQuestion] characters. Null when
/// nothing is left to ask.
String? chatQuestion(String text,
    [AiContextSanitizer sanitizer = const AiContextSanitizer()]) {
  var t = sanitizer
      .sanitizeText(text)
      .replaceAllMapped(_anyCardNumber, (m) => '${m[1]} [number]')
      .replaceAll(_anyLongNumber, '[number]')
      .replaceAll(RegExp(r'[<>]'), ' ')
      .replaceAll(RegExp(r'[\u0000-\u001F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (t.length > kChatMaxQuestion) {
    t = t.substring(0, kChatMaxQuestion);
    // Do not leave half of an emoji at the cut.
    final last = t.codeUnitAt(t.length - 1);
    if (last >= 0xD800 && last <= 0xDBFF) t = t.substring(0, t.length - 1);
    t = t.trim();
  }
  return t.length < 2 ? null : t;
}

/// The numbers the phone's own rules worked out for this question, as key
/// and display text only. A number about a custom category is left out: its
/// key would carry the name the person typed.
List<Map<String, Object>> chatMetrics(Iterable<Metric> metrics) {
  final out = <Map<String, Object>>[];
  for (final m in metrics) {
    final display = m.display;
    if (display == null || !_displayOk.hasMatch(display)) continue;
    if (!_keyOk(m.key)) continue;
    out.add({'key': m.key, 'display': display});
    if (out.length == kChatMaxMetrics) break;
  }
  return out;
}

/// Everything a spending question sends, worked out on the phone in integer
/// fils: the savings plan's summary (see [coachRequest]) plus a total and
/// count for today, yesterday, the last 7 days, the 7 before, this month and
/// last month, what was spent today, a total and share per category and the
/// top shops of the month, and the numbers the phone's rules worked out for
/// this question. The question itself is masked ([chatQuestion]). Nothing
/// else leaves the phone: no message text, account or card digit, phone
/// number, CPR, reference, calendar date or transfer recipient. The server
/// refuses any other field. Null when the question is empty.
Map<String, Object>? chatRequest({
  required Iterable<LedgerEntry> entries,
  required GuardrailSettings settings,
  required Day today,
  required String language,
  required String question,
  String? previousQuestion,
  Iterable<Metric> metrics = const [],
  BudgetPlan? plan,
  AiContextSanitizer sanitizer = const AiContextSanitizer(),
}) {
  final q = chatQuestion(question, sanitizer);
  if (q == null) return null;
  final before =
      previousQuestion == null ? null : chatQuestion(previousQuestion, sanitizer);
  final list = entries.toList();
  final base = coachRequest(list, settings, today, language, plan: plan);
  final s = SpendingSummaryBuilder(list, settings: settings, today: today);

  // What the home screen calls "spent today" (money paid back is taken off).
  final spentToday = math.max(0, s.todaySummary().spentFils);
  Map<String, Object> period(PeriodKind kind, {int? fils}) {
    final p = Period.of(kind, today);
    return {'fils': fils ?? s.total(p), 'count': s.count(p)};
  }

  final month = Period.of(PeriodKind.month, today);
  final byCategory = <String, int>{};
  for (final b in s.byBucket(month)) {
    final key = sharedBucket(b.bucket);
    byCategory[key] = (byCategory[key] ?? 0) + b.totalFils;
  }
  final monthSum = byCategory.values.fold(0, (a, b) => a + b);
  final categories = byCategory.entries.toList()
    ..sort((x, y) {
      final c = y.value.compareTo(x.value);
      return c != 0 ? c : x.key.compareTo(y.key);
    });

  // Shops of the month: purchases only (no transfers, so no person's name),
  // named by the clean name with every digit taken out.
  final shops = <String, (String, int, int)>{};
  for (final r in s.items(month)) {
    final a = r.amountFils;
    if (a == null || a <= 0 || isTransferOut(r) || bucketOf(r) == kTransferBucket) {
      continue;
    }
    final name = coachShopName(r.merchantNorm ?? r.merchantRaw);
    if (name == null) continue;
    final key = name.toUpperCase();
    final (shown, fils, count) = shops[key] ?? (name, 0, 0);
    shops[key] = (shown, fils + a, count + 1);
  }
  final topShops = shops.values.toList()
    ..sort((x, y) {
      final c = y.$2.compareTo(x.$2);
      return c != 0 ? c : x.$1.compareTo(y.$1);
    });

  return {
    ...base,
    'consent': kChatConsentVersion,
    'question': q,
    if (before != null) 'previous_question': before,
    'today_spent_fils': spentToday,
    'periods': {
      'today': period(PeriodKind.today, fils: spentToday),
      'yesterday': period(PeriodKind.yesterday),
      'week': period(PeriodKind.week),
      'last_week': period(PeriodKind.lastWeek),
      'month': period(PeriodKind.month),
      'last_month': period(PeriodKind.lastMonth),
    },
    'month_categories': [
      for (final c in categories)
        {
          'category': c.key,
          'fils': c.value,
          'percent': percentOf(c.value, monthSum),
        },
    ],
    'month_shops': [
      for (final (name, fils, count) in topShops.take(kCoachMaxShops))
        {'name': name, 'fils': fils, 'count': count},
    ],
    'metrics': chatMetrics(metrics),
  };
}
