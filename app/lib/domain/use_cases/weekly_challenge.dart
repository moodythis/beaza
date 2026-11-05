import 'package:beaza/domain/use_cases/savings_tips.dart';
import 'package:beaza/domain/use_cases/spending_by_category.dart';
import 'package:beaza_extraction/beaza_extraction.dart';

/// What a weekly challenge is about. Each one comes from the biggest weak
/// spot of the last 7 days, worked out by rules on the phone.
enum ChallengeKind {
  /// Fewer visits to the shop visited most.
  shop,

  /// No purchases late at night (22:00 to 03:00).
  lateNight,

  /// Fewer small purchases.
  small,

  /// Less on the biggest discretionary category.
  category,
}

/// One challenge: a target over 7 days starting on [start]. [target] is a
/// count for shop, late night and small purchases, and fils for a category.
class Challenge {
  const Challenge({
    required this.kind,
    required this.target,
    required this.savingFils,
    required this.start,
    this.shop,
    this.category,
  });

  final ChallengeKind kind;
  final int target;

  /// About what keeping to it saves (from last week's numbers).
  final int savingFils;
  final Day start;
  final String? shop;
  final String? category;

  /// The last day of the challenge.
  Day get end => start.addDays(6);

  bool get countsMoney => kind == ChallengeKind.category;

  Challenge startingOn(Day day) => Challenge(
        kind: kind,
        target: target,
        savingFils: savingFils,
        start: day,
        shop: shop,
        category: category,
      );

  Map<String, Object> toJson() => {
        'kind': kind.name,
        'target': target,
        'saving': savingFils,
        'start': start.toString(),
        if (shop != null) 'shop': shop!,
        if (category != null) 'category': category!,
      };

  /// Null for anything that does not read back (an older format, say).
  static Challenge? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = ChallengeKind.values
        .where((k) => k.name == json['kind'])
        .firstOrNull;
    final target = json['target'];
    final saving = json['saving'];
    final start = json['start'];
    if (kind == null || target is! int || saving is! int || start is! String) {
      return null;
    }
    final parts = start.split('-').map(int.tryParse).toList();
    if (parts.length != 3 || parts.contains(null)) return null;
    return Challenge(
      kind: kind,
      target: target,
      savingFils: saving,
      start: Day(parts[0]!, parts[1]!, parts[2]!),
      shop: json['shop'] as String?,
      category: json['category'] as String?,
    );
  }
}

/// The challenge for the coming week from the last 7 days ending on
/// [today], or null when nothing stands out. The order is the order of
/// what a person can most easily change: one shop, then late nights, then
/// small purchases, then a whole category.
Challenge? suggestChallenge(
  Iterable<LedgerEntry> entries,
  Day today, {
  int microThresholdFils = 5000,
}) {
  final list = entries.toList();
  final start = today.addDays(1);

  final shops = weekShops(list, today);
  if (shops.isNotEmpty && shops.first.count >= kTipsMinShopVisits) {
    final s = shops.first;
    return Challenge(
      kind: ChallengeKind.shop,
      shop: s.name,
      target: s.count - 2,
      savingFils: s.fils * 2 ~/ s.count,
      start: start,
    );
  }

  final (:lateCount, :lateFils, weekendFils: _) = weekPatterns(list, today);
  if (lateCount >= kTipsMinLateCount && lateFils >= kTipsMinLateFils) {
    return Challenge(
      kind: ChallengeKind.lateNight,
      target: 0,
      savingFils: lateFils,
      start: start,
    );
  }

  final (count: smallCount, fils: smallFils) =
      _small(list, today.addDays(-6), today, microThresholdFils);
  if (smallCount >= kTipsMinSmallCount) {
    final target = smallCount ~/ 2;
    return Challenge(
      kind: ChallengeKind.small,
      target: target,
      savingFils: smallFils * (smallCount - target) ~/ smallCount,
      start: start,
    );
  }

  for (final t in spendingByCategory(list, today.addDays(-6), today)) {
    if (!kDiscretionary.contains(t.bucket) || t.totalFils < kTipsMinTrimFils) {
      continue;
    }
    final target = t.totalFils * 4 ~/ 5;
    return Challenge(
      kind: ChallengeKind.category,
      category: t.bucket,
      target: target,
      savingFils: t.totalFils - target,
      start: start,
    );
  }
  return null;
}

/// How a challenge stands on [today].
class ChallengeProgress {
  const ChallengeProgress({
    required this.value,
    required this.daysLeft,
    required this.finished,
  });

  /// Visits, late purchases or small purchases so far, or fils spent in
  /// the category.
  final int value;

  /// Days left including today; 0 once it is over.
  final int daysLeft;

  /// The 7 days are over.
  final bool finished;
}

ChallengeProgress challengeProgress(
  Challenge c,
  Iterable<LedgerEntry> entries,
  Day today, {
  int microThresholdFils = 5000,
}) {
  final list = entries.toList();
  final last = today.compareTo(c.end) < 0 ? today : c.end;
  var value = 0;
  if (today.compareTo(c.start) >= 0) {
    switch (c.kind) {
      case ChallengeKind.shop:
        final key = c.shop?.toUpperCase();
        for (final s in _shopsBetween(list, c.start, last)) {
          if (s.name.toUpperCase() == key) value = s.count;
        }
      case ChallengeKind.lateNight:
        value = _lateBetween(list, c.start, last);
      case ChallengeKind.small:
        value = _small(list, c.start, last, microThresholdFils).count;
      case ChallengeKind.category:
        for (final t in spendingByCategory(list, c.start, last)) {
          if (t.bucket == c.category) value = t.totalFils;
        }
    }
  }
  final finished = today.compareTo(c.end) > 0;
  final daysLeft = finished
      ? 0
      : today.compareTo(c.start) < 0
          ? 7
          : _daysBetween(today, c.end) + 1;
  return ChallengeProgress(value: value, daysLeft: daysLeft, finished: finished);
}

/// Kept to it: at most the target.
bool challengeKept(Challenge c, ChallengeProgress p) => p.value <= c.target;

int _daysBetween(Day a, Day b) => DateTime.utc(b.year, b.month, b.day)
    .difference(DateTime.utc(a.year, a.month, a.day))
    .inDays;

bool _counted(LedgerEntry e, Day from, Day to) {
  final t = e.result.timestamp?.toUtc();
  final a = e.result.amountFils;
  if (!e.countsTowardSpending || t == null || a == null || a <= 0) return false;
  return !t.isBefore(from.startUtc) && t.isBefore(to.endUtc);
}

({int count, int fils}) _small(
    List<LedgerEntry> list, Day from, Day to, int microThresholdFils) {
  var count = 0;
  var fils = 0;
  for (final e in list) {
    if (!_counted(e, from, to)) continue;
    final a = e.result.amountFils!;
    if (a <= microThresholdFils) {
      count++;
      fils += a;
    }
  }
  return (count: count, fils: fils);
}

int _lateBetween(List<LedgerEntry> list, Day from, Day to) {
  var count = 0;
  for (final e in list) {
    if (!_counted(e, from, to)) continue;
    final h = e.result.timestamp!.toUtc().add(kBahrainOffset).hour;
    if (h >= 22 || h < 3) count++;
  }
  return count;
}

List<ShopWeek> _shopsBetween(List<LedgerEntry> list, Day from, Day to) {
  // weekShops looks at the 7 days ending on its day; a challenge window is
  // at most 7 days, so filter to the window first.
  final inWindow = [for (final e in list) if (_counted(e, from, to)) e];
  return weekShops(inWindow, to);
}
