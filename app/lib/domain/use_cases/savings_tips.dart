import 'package:beaza/domain/use_cases/spending_by_category.dart';
import 'package:beaza_extraction/beaza_extraction.dart';

/// What a saving tip says. The screen turns it into a sentence in the
/// person's language; nothing here leaves the phone.
enum TipKind {
  /// A category is clearly higher than the week before.
  categorySpike,

  /// The person went over the daily limit on several of the last 7 days.
  overLimitDays,

  /// Many small purchases in the last 7 days.
  smallPurchases,

  /// One category is a large share of the week.
  topCategory,

  /// What 20% less on a category would keep each week.
  trimTarget,
}

class SavingsTip {
  const SavingsTip(
    this.kind, {
    this.bucket,
    this.fils = 0,
    this.otherFils = 0,
    this.count = 0,
  });

  final TipKind kind;

  /// The category, when the tip is about one.
  final String? bucket;

  /// Main amount: this week's spending, or what trimming keeps.
  final int fils;

  /// The week before, for [TipKind.categorySpike].
  final int otherFils;

  /// Days over the limit, small purchases, or the share in percent for
  /// [TipKind.topCategory].
  final int count;
}

/// Spending below this in the last 7 days is too little to say anything.
const int kTipsMinWeekFils = 5000;

/// A category must be at least this much to be called out.
const int kTipsMinCategoryFils = 5000;

/// This many small purchases in 7 days are worth a word.
const int kTipsMinSmallCount = 5;

/// Categories where a person can usually choose to spend less.
const Set<String> kDiscretionary = {'food', 'shopping', 'entertainment'};

bool _tippable(String bucket) =>
    bucket != kTransferBucket && bucket != kUnsortedBucket;

/// Up to [limit] tips from the last 14 Bahrain days ending on [today]:
/// rules only, no model and no network. Comparing 7 days with the 7 before
/// them keeps one big shop from being called a habit.
List<SavingsTip> savingsTips(
  Iterable<LedgerEntry> entries,
  Day today, {
  int dailyLimitFils = 0,
  int microThresholdFils = 5000,
  int limit = 3,
}) {
  final list = entries.toList();
  final now = spendingByCategory(list, today.addDays(-6), today);
  final before = spendingByCategory(list, today.addDays(-13), today.addDays(-7));
  final weekTotal = now.fold<int>(0, (a, t) => a + t.totalFils);
  if (weekTotal < kTipsMinWeekFils) return const [];

  final prev = {for (final t in before) t.bucket: t.totalFils};
  final tips = <SavingsTip>[];
  final used = <String>{};

  // 1. The category that grew the most (at least half as much again).
  CategoryTotal? spike;
  for (final t in now) {
    if (!_tippable(t.bucket) || t.totalFils < kTipsMinCategoryFils) continue;
    final p = prev[t.bucket] ?? 0;
    if (p <= 0 || t.totalFils * 2 < p * 3) continue;
    if (spike == null ||
        t.totalFils - p > spike.totalFils - (prev[spike.bucket] ?? 0)) {
      spike = t;
    }
  }
  if (spike != null) {
    tips.add(SavingsTip(
      TipKind.categorySpike,
      bucket: spike.bucket,
      fils: spike.totalFils,
      otherFils: prev[spike.bucket]!,
    ));
    used.add(spike.bucket);
  }

  // 2. Days over the daily limit.
  if (dailyLimitFils > 0) {
    var over = 0;
    for (var i = 0; i < 7; i++) {
      final d = today.addDays(-i);
      final spent = spendingByCategory(list, d, d)
          .fold<int>(0, (a, t) => a + t.totalFils);
      if (spent > dailyLimitFils) over++;
    }
    if (over >= 2) tips.add(SavingsTip(TipKind.overLimitDays, count: over));
  }

  // 3. Small purchases that add up (at most the micro threshold each).
  final weekStart = today.addDays(-6).startUtc;
  final weekEnd = today.endUtc;
  var smallCount = 0;
  var smallFils = 0;
  for (final e in list) {
    final t = e.result.timestamp?.toUtc();
    final a = e.result.amountFils;
    if (!e.countsTowardSpending || t == null || a == null) continue;
    if (t.isBefore(weekStart) || !t.isBefore(weekEnd)) continue;
    if (a > 0 && a <= microThresholdFils) {
      smallCount++;
      smallFils += a;
    }
  }
  if (smallCount >= kTipsMinSmallCount) {
    tips.add(SavingsTip(TipKind.smallPurchases,
        fils: smallFils, count: smallCount));
  }

  // 4. One category taking a big share of the week.
  if (weekTotal >= 2 * kTipsMinWeekFils) {
    for (final t in now) {
      if (!_tippable(t.bucket) || used.contains(t.bucket)) continue;
      final percent = (100 * t.totalFils / weekTotal).round();
      if (percent >= 40) {
        tips.add(SavingsTip(
          TipKind.topCategory,
          bucket: t.bucket,
          fils: t.totalFils,
          count: percent,
        ));
        used.add(t.bucket);
      }
      break; // the list is largest first: only the first one left can qualify
    }
  }

  // 5. What 20% less on the biggest discretionary category would keep.
  for (final t in now) {
    if (!kDiscretionary.contains(t.bucket) ||
        t.bucket == spike?.bucket ||
        t.totalFils < kTipsMinCategoryFils) {
      continue;
    }
    tips.add(SavingsTip(TipKind.trimTarget,
        bucket: t.bucket, fils: t.totalFils ~/ 5));
    break;
  }

  return tips.length <= limit ? tips : tips.sublist(0, limit);
}
