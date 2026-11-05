import 'package:beaza/domain/use_cases/spending_by_category.dart';
import 'package:beaza_extraction/beaza_extraction.dart';

/// The version of the AI consent text (server: COACH_CONSENT_VERSION).
const String kCoachConsentVersion = '2026-11-05';

/// Everything the AI savings plan sends, worked out on the phone in integer
/// fils: totals of the last 7 days and the 7 before, the daily limit, how
/// many days passed it, small purchases, a total per category, and the
/// names of the shops where most was spent (digits removed, at most
/// [kCoachMaxShops]). No message text, account digit, reference, date or
/// transfer recipient is in it, and the server refuses any other field.
Map<String, Object> coachRequest(
  Iterable<LedgerEntry> entries,
  GuardrailSettings settings,
  Day today,
  String language,
) {
  final list = entries.toList();
  int sum(List<CategoryTotal> t) => t.fold(0, (a, c) => a + c.totalFils);
  final week = spendingByCategory(list, today.addDays(-6), today);
  final weekTotal = sum(week);
  final before =
      sum(spendingByCategory(list, today.addDays(-13), today.addDays(-7)));

  var overDays = 0;
  if (settings.dailyLimitFils > 0) {
    for (var i = 0; i < 7; i++) {
      final d = today.addDays(-i);
      if (sum(spendingByCategory(list, d, d)) > settings.dailyLimitFils) {
        overDays++;
      }
    }
  }

  var smallCount = 0;
  var smallFils = 0;
  final start = today.addDays(-6).startUtc;
  final end = today.endUtc;
  for (final e in list) {
    final t = e.result.timestamp?.toUtc();
    final a = e.result.amountFils;
    if (!e.countsTowardSpending || t == null || a == null) continue;
    if (t.isBefore(start) || !t.isBefore(end)) continue;
    if (a > 0 && a <= settings.microThresholdFils) {
      smallCount++;
      smallFils += a;
    }
  }

  // Shops: purchases only (no transfers, so no person's name), named by
  // the clean name, digits taken out so no card, phone or branch number
  // can go.
  final shops = <String, (String, int, int)>{};
  for (final e in list) {
    final t = e.result.timestamp?.toUtc();
    final a = e.result.amountFils;
    if (!e.countsTowardSpending || t == null || a == null || a <= 0) continue;
    if (t.isBefore(start) || !t.isBefore(end)) continue;
    if (bucketOf(e.result) == kTransferBucket) continue;
    final name = coachShopName(e.result.merchantNorm ?? e.result.merchantRaw);
    if (name == null) continue;
    final key = name.toUpperCase();
    final (shown, fils, count) = shops[key] ?? (name, 0, 0);
    shops[key] = (shown, fils + a, count + 1);
  }
  final topShops = shops.values.toList()
    ..sort((x, y) => y.$2.compareTo(x.$2));

  return {
    'consent': kCoachConsentVersion,
    'language': language == 'ar' ? 'ar' : 'en',
    'week_total_fils': weekTotal,
    'previous_week_total_fils': before,
    'daily_limit_fils': settings.dailyLimitFils,
    'days_over_limit': overDays,
    'small_purchases_count': smallCount,
    'small_purchases_fils': smallFils,
    'shops': [
      for (final (name, fils, count) in topShops.take(kCoachMaxShops))
        {'name': name, 'fils': fils, 'count': count},
    ],
    'categories': [
      for (final c in week)
        {
          'category': c.bucket,
          'fils': c.totalFils,
          'percent': weekTotal == 0
              ? 0
              : (c.totalFils * 100 + weekTotal ~/ 2) ~/ weekTotal,
        },
    ],
  };
}

/// At most this many shops are sent (server: COACH_MAX_SHOPS).
const int kCoachMaxShops = 5;

/// A shop name as it may be sent: no digits (Western, Arabic or Persian),
/// one space between words, at most 40 characters. Null when nothing
/// readable is left.
String? coachShopName(String? raw) {
  if (raw == null) return null;
  final s = raw
      .replaceAll(RegExp(r'[0-9\u0660-\u0669\u06F0-\u06F9]'), '')
      .replaceAll(RegExp(r'[*#@+]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[\s\-–.,/]+|[\s\-–.,/]+$'), '')
      .trim();
  if (s.length < 2) return null;
  return s.length <= 40 ? s : s.substring(0, 40).trim();
}

