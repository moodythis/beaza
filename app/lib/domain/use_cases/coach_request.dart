import 'package:beaza/domain/use_cases/custom_categories.dart';
import 'package:beaza/domain/use_cases/daily_budget.dart';
import 'package:beaza/domain/use_cases/savings_tips.dart';
import 'package:beaza/domain/use_cases/shop_name.dart';
import 'package:beaza/domain/use_cases/spending_by_category.dart';
import 'package:beaza_extraction/beaza_extraction.dart';

/// The version of the AI consent text (server: COACH_CONSENT_VERSION).
const String kCoachConsentVersion = '2026-11-06.1';

/// Everything the AI savings plan sends, worked out on the phone in integer
/// fils: totals of the last 7 days and the 7 before, the daily limit, how
/// many days passed it, small purchases, a total per category, and the
/// names of the shops where most was spent (at most [kCoachMaxShops]), the
/// purchases of the last 7 days one by one (weekday, hour, amount,
/// category, shop; at most [kCoachMaxRecent]), late-night and weekend totals, and, when the limit
/// is worked out from income, the free money and days left in the month
/// (never the income itself). What identifies the person is never in it:
/// no message text, account or card digit, phone number, CPR, reference,
/// calendar date or transfer recipient (names lose every digit, and
/// transfers are left out). The server refuses any other field.
Map<String, Object> coachRequest(
  Iterable<LedgerEntry> entries,
  GuardrailSettings settings,
  Day today,
  String language, {
  BudgetPlan? plan,
}) {
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
  // The week's purchases one by one, newest first, for advice about
  // habits (a late order every night, the same café each morning).
  final recent = <Map<String, Object>>[];
  final weekItems = [
    for (final e in list)
      if (e.countsTowardSpending &&
          e.result.timestamp != null &&
          (e.result.amountFils ?? 0) > 0 &&
          !e.result.timestamp!.toUtc().isBefore(start) &&
          e.result.timestamp!.toUtc().isBefore(end) &&
          bucketOf(e.result) != kTransferBucket)
        e,
  ]..sort((a, b) => b.result.timestamp!.compareTo(a.result.timestamp!));
  for (final e in weekItems.take(kCoachMaxRecent)) {
    final local = e.result.timestamp!.toUtc().add(kBahrainOffset);
    final shop = coachShopName(e.result.merchantNorm ?? e.result.merchantRaw);
    recent.add({
      'weekday': _weekdays[local.weekday - 1],
      'hour': local.hour,
      'fils': e.result.amountFils!,
      'category': sharedBucket(bucketOf(e.result)),
      if (shop != null) 'shop': shop,
    });
  }

  final topShops = shops.values.toList()
    ..sort((x, y) => y.$2.compareTo(x.$2));

  final (:lateCount, :lateFils, :weekendFils) = weekPatterns(list, today);
  final month = plan == null ? null : monthLeft(plan, list, today);

  return {
    'consent': kCoachConsentVersion,
    'language': language == 'ar' ? 'ar' : 'en',
    'week_total_fils': weekTotal,
    'previous_week_total_fils': before,
    'daily_limit_fils': settings.dailyLimitFils,
    'days_over_limit': overDays,
    'small_purchases_count': smallCount,
    'small_purchases_fils': smallFils,
    'late_night_count': lateCount,
    'late_night_fils': lateFils,
    'weekend_fils': weekendFils,
    if (month != null) ...{
      'month_left_fils': month.leftFils < 0 ? 0 : month.leftFils,
      'days_left_in_month': month.daysAfter,
    },
    'shops': [
      for (final (name, fils, count) in topShops.take(kCoachMaxShops))
        {'name': name, 'fils': fils, 'count': count},
    ],
    'recent': recent,
    'categories': [
      for (final (bucket, fils) in _shared(week))
        {
          'category': bucket,
          'fils': fils,
          'percent':
              weekTotal == 0 ? 0 : (fils * 100 + weekTotal ~/ 2) ~/ weekTotal,
        },
    ],
  };
}

/// At most this many shops are sent (server: COACH_MAX_SHOPS).
const int kCoachMaxShops = 5;

/// At most this many recent purchases are sent (server: COACH_MAX_RECENT).
const int kCoachMaxRecent = 40;

const List<String> _weekdays = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

/// A shop name as it may be sent (see [cleanShopName]).
String? coachShopName(String? raw) => cleanShopName(raw);

/// The week's totals with every custom category counted as "other" (the
/// only names the server takes), largest first.
List<(String, int)> _shared(List<CategoryTotal> week) {
  final totals = <String, int>{};
  for (final c in week) {
    final b = sharedBucket(c.bucket);
    totals[b] = (totals[b] ?? 0) + c.totalFils;
  }
  return [for (final e in totals.entries) (e.key, e.value)]
    ..sort((x, y) {
      final c = y.$2.compareTo(x.$2);
      return c != 0 ? c : x.$1.compareTo(y.$1);
    });
}
