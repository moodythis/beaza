import 'package:beaza/domain/use_cases/spending_by_category.dart';
import 'package:beaza_extraction/beaza_extraction.dart';

/// The version of the AI consent text (server: COACH_CONSENT_VERSION).
const String kCoachConsentVersion = '2026-11-04';

/// Everything the AI savings plan sends, worked out on the phone in integer
/// fils: totals of the last 7 days and the 7 before, the daily limit, how
/// many days passed it, small purchases, and a total per category. No shop
/// name, message text, account digit, reference or date is in it, and the
/// server refuses any other field.
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

  return {
    'consent': kCoachConsentVersion,
    'language': language == 'ar' ? 'ar' : 'en',
    'week_total_fils': weekTotal,
    'previous_week_total_fils': before,
    'daily_limit_fils': settings.dailyLimitFils,
    'days_over_limit': overDays,
    'small_purchases_count': smallCount,
    'small_purchases_fils': smallFils,
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
