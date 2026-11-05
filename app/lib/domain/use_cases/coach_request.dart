import 'dart:convert';

import 'package:beaza/domain/use_cases/daily_budget.dart';
import 'package:beaza/domain/use_cases/savings_tips.dart';
import 'package:beaza/domain/use_cases/spending_by_category.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:crypto/crypto.dart' show sha256;

/// The version of the AI consent text (server: COACH_CONSENT_VERSION).
const String kCoachConsentVersion = '2026-11-05.3';

/// Everything the AI savings plan sends, worked out on the phone in integer
/// fils: totals of the last 7 days and the 7 before, the daily limit, how
/// many days passed it, small purchases, a total per category, and the
/// shops where most was spent (digits removed, at most [kCoachMaxShops];
/// before sending, [pseudonymizeShops] replaces each name with a code), late-night and weekend totals, and, when the limit
/// is worked out from income, the free money and days left in the month
/// (never the income itself). No message text, account digit, reference, date or
/// transfer recipient is in it, and the server refuses any other field.
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


/// Shop names leave the phone only as codes. Each code is the first 8
/// hex digits of SHA-256(salt + name), written with the letters A to P (so
/// the server's number check is not tripped). The salt is new for every
/// request and never sent, so a code cannot be turned back into a name by
/// hashing a list of shops, and the same shop gets a different code next
/// time. The phone keeps the map and puts the names back into the plan.
({Map<String, Object> request, Map<String, String> names}) pseudonymizeShops(
    Map<String, Object> request, List<int> salt) {
  final shops = (request['shops'] as List?)?.cast<Map<String, Object>>();
  if (shops == null || shops.isEmpty) return (request: request, names: const {});
  final names = <String, String>{};
  final coded = <Map<String, Object>>[];
  for (final s in shops) {
    final name = s['name'] as String;
    final digest = sha256.convert([...salt, ...utf8.encode(name.toUpperCase())]);
    final letters = StringBuffer('SHOP-');
    for (final b in digest.bytes.take(4)) {
      letters
        ..writeCharCode(0x41 + (b >> 4))
        ..writeCharCode(0x41 + (b & 0x0F));
    }
    final code = letters.toString();
    names[code] = name;
    coded.add({...s, 'name': code});
  }
  return (request: {...request, 'shops': coded}, names: names);
}

/// Puts the shop names back into a plan written with their codes (any
/// letter case, as the model may change it).
String restoreShopNames(String text, Map<String, String> names) {
  var out = text;
  names.forEach((code, name) {
    out = out.replaceAll(RegExp(RegExp.escape(code), caseSensitive: false), name);
  });
  return out;
}
