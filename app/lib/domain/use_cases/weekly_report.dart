import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/savings_repository.dart';
import 'package:beaza/domain/use_cases/daily_budget.dart';
import 'package:beaza/domain/use_cases/savings_tips.dart';
import 'package:beaza/domain/use_cases/spending_by_category.dart';
import 'package:beaza/domain/use_cases/weekly_challenge.dart';
import 'package:beaza_extraction/beaza_extraction.dart';

/// How one day of the report went against the daily limit.
enum DayStatus {
  /// Under 80% of the limit.
  good,

  /// 80% to 100%.
  close,

  /// Over the limit.
  over,

  /// Nothing spent, or no limit set.
  none,
}

class ReportDay {
  const ReportDay(this.day, this.spentFils, this.status);
  final Day day;

  /// Net spending (money paid back taken off), never below 0.
  final int spentFils;
  final DayStatus status;
}

class CategoryMove {
  const CategoryMove(this.bucket, this.thisWeekFils, this.lastWeekFils);
  final String bucket;
  final int thisWeekFils;
  final int lastWeekFils;
  int get changeFils => thisWeekFils - lastWeekFils;
}

class Purchase {
  const Purchase(this.shop, this.day, this.fils);
  final String shop;
  final Day day;
  final int fils;
}

enum TimeSlot { morning, afternoon, evening, lateNight }

enum PayChannel { card, wallet, transfer, cash, atm, other }

/// Everything in the weekly report: the 7 days ending on [end] against the
/// 7 before. Worked out on the phone in integer fils, Bahrain time; no
/// model does any arithmetic. Totals are net of money paid back, as the
/// daily limit is; category, shop and channel splits count purchases as
/// made.
class WeeklyReport {
  const WeeklyReport({
    required this.start,
    required this.end,
    required this.totalFils,
    required this.previousFils,
    required this.dailyLimitFils,
    required this.days,
    required this.categories,
    required this.mover,
    required this.topShops,
    required this.largest,
    required this.microCount,
    required this.microFils,
    required this.weekendFils,
    required this.lateCount,
    required this.lateFils,
    required this.peak,
    required this.channels,
    required this.skippedCount,
    required this.skippedFils,
    required this.points,
    required this.focus,
    required this.purchaseCount,
  });

  final Day start;
  final Day end;
  final int totalFils;
  final int previousFils;
  final int dailyLimitFils;
  final List<ReportDay> days;
  final List<CategoryTotal> categories;
  final CategoryMove? mover;
  final List<ShopWeek> topShops;
  final Purchase? largest;
  final int microCount;
  final int microFils;

  /// Thursday to Saturday ([isWeekendWeekday]).
  final int weekendFils;
  final int lateCount;
  final int lateFils;
  final TimeSlot? peak;
  final Map<PayChannel, int> channels;
  final int skippedCount;
  final int skippedFils;
  final int points;

  /// The one thing to do next week (a challenge picked by rules), or null.
  final Challenge? focus;
  final int purchaseCount;

  bool get isEmpty => purchaseCount == 0 && totalFils == 0;
  int get deltaFils => totalFils - previousFils;

  /// Change against last week in whole percent (rounded), null when last
  /// week had nothing to compare with.
  int? get deltaPercent => previousFils <= 0
      ? null
      : ((deltaFils * 100) + (deltaFils >= 0 ? 1 : -1) * previousFils ~/ 2) ~/
          previousFils;
  int get dailyAverageFils => totalFils ~/ 7;
  int get poolFils => dailyLimitFils * 7;

  /// What was left of the 7 days' limits (below 0 when they were passed).
  int get netSavedFils => poolFils - totalFils;
  int get daysWithinLimit =>
      days.where((d) => d.status == DayStatus.good || d.status == DayStatus.close).length;

  int percentOf(int part) => totalFils <= 0 ? 0 : (part * 100 + totalFils ~/ 2) ~/ totalFils;

  ReportDay? get cheapestDay {
    final spent = days.where((d) => d.spentFils > 0).toList();
    if (spent.isEmpty) return null;
    return spent.reduce((a, b) => b.spentFils < a.spentFils ? b : a);
  }

  ReportDay? get heaviestDay {
    final spent = days.where((d) => d.spentFils > 0).toList();
    if (spent.isEmpty) return null;
    return spent.reduce((a, b) => b.spentFils > a.spentFils ? b : a);
  }
}

TimeSlot slotOf(int hour) => hour >= 6 && hour < 12
    ? TimeSlot.morning
    : hour >= 12 && hour < 17
        ? TimeSlot.afternoon
        : hour >= 17 && hour < 22
            ? TimeSlot.evening
            : TimeSlot.lateNight;

PayChannel channelOf(ExtractionResult r) {
  if (r.templateVersion == InMemoryLedgerRepository.manualTemplate) {
    return PayChannel.cash;
  }
  return switch (r.channel) {
    Channel.card => PayChannel.card,
    Channel.wallet => PayChannel.wallet,
    Channel.transfer => PayChannel.transfer,
    Channel.atm => PayChannel.atm,
    null => PayChannel.other,
  };
}

WeeklyReport buildWeeklyReport(
  Iterable<LedgerEntry> entries,
  Day end, {
  required int dailyLimitFils,
  int microThresholdFils = 5000,
  List<Hold> holds = const [],
}) {
  final list = entries.toList();
  final start = end.addDays(-6);
  final g = Guardrail(GuardrailSettings(dailyLimitFils: dailyLimitFils));
  int net(Day d) {
    final s = g.spentOn(list, d);
    return s < 0 ? 0 : s;
  }

  var total = 0;
  var previous = 0;
  final days = <ReportDay>[];
  for (var i = 0; i < 7; i++) {
    final d = start.addDays(i);
    final s = net(d);
    total += s;
    previous += net(d.addDays(-7));
    final status = dailyLimitFils <= 0 || s == 0
        ? DayStatus.none
        : s > dailyLimitFils
            ? DayStatus.over
            : s * 100 >= dailyLimitFils * 80
                ? DayStatus.close
                : DayStatus.good;
    days.add(ReportDay(d, s, status));
  }

  final categories = spendingByCategory(list, start, end);
  final before = {
    for (final c in spendingByCategory(list, start.addDays(-7), end.addDays(-7)))
      c.bucket: c.totalFils,
  };
  CategoryMove? mover;
  for (final b in {...before.keys, ...categories.map((c) => c.bucket)}) {
    if (b == kTransferBucket) continue;
    final now = categories.where((c) => c.bucket == b).fold(0, (a, c) => a + c.totalFils);
    final m = CategoryMove(b, now, before[b] ?? 0);
    if (m.changeFils == 0) continue;
    if (mover == null || m.changeFils.abs() > mover.changeFils.abs()) mover = m;
  }

  final shops = weekShops(list, end)
    ..sort((a, b) => b.fils != a.fils ? b.fils.compareTo(a.fils) : b.count.compareTo(a.count));

  Purchase? largest;
  var micro = 0, microFils = 0, weekend = 0, late = 0, lateFils = 0, count = 0;
  final slots = <TimeSlot, int>{};
  final channels = <PayChannel, int>{};
  for (final e in list) {
    final t = e.result.timestamp?.toUtc();
    final a = e.result.amountFils;
    if (!e.countsTowardSpending || t == null || a == null || a <= 0) continue;
    if (t.isBefore(start.startUtc) || !t.isBefore(end.endUtc)) continue;
    count++;
    final local = t.add(kBahrainOffset);
    final day = Day(local.year, local.month, local.day);
    if (a <= microThresholdFils) {
      micro++;
      microFils += a;
    }
    if (isWeekendWeekday(local.weekday)) {
      weekend += a;
    }
    if (local.hour >= 22 || local.hour < 3) {
      late++;
      lateFils += a;
    }
    final slot = slotOf(local.hour);
    slots[slot] = (slots[slot] ?? 0) + a;
    final ch = channelOf(e.result);
    channels[ch] = (channels[ch] ?? 0) + a;
    if (bucketOf(e.result) != kTransferBucket && (largest == null || a > largest.fils)) {
      largest = Purchase(
          e.result.merchantNorm ?? e.result.merchantRaw ?? '', day, a);
    }
  }
  TimeSlot? peak;
  for (final s in TimeSlot.values) {
    if ((slots[s] ?? 0) > 0 && (peak == null || slots[s]! > slots[peak]!)) peak = s;
  }

  var skipped = 0, skippedFils = 0;
  for (final h in holds) {
    final at = h.decidedAt?.toUtc();
    if (h.decision != 'skipped' || at == null) continue;
    if (at.isBefore(start.startUtc) || !at.isBefore(end.endUtc)) continue;
    skipped++;
    skippedFils += h.amountFils;
  }
  // FR-9.4: 10 for a day with spending within the limit, 20 a skip.
  final pointDays = days.where((d) =>
      d.spentFils > 0 && dailyLimitFils > 0 && d.spentFils <= dailyLimitFils);

  return WeeklyReport(
    start: start,
    end: end,
    totalFils: total,
    previousFils: previous,
    dailyLimitFils: dailyLimitFils,
    days: days,
    categories: categories,
    mover: mover,
    topShops: shops.take(3).toList(),
    largest: largest,
    microCount: micro,
    microFils: microFils,
    weekendFils: weekend,
    lateCount: late,
    lateFils: lateFils,
    peak: peak,
    channels: channels,
    skippedCount: skipped,
    skippedFils: skippedFils,
    points: pointDays.length * 10 + skipped * 20,
    focus: suggestChallenge(list, end, microThresholdFils: microThresholdFils),
    purchaseCount: count,
  );
}

/// A short text that is safe to share: shares and counts only, no shop,
/// bank, card digits or names.
String shareSummary(WeeklyReport r, String language,
    String Function(String bucket) categoryName) {
  final top = r.categories
      .where((c) => c.bucket != kTransferBucket)
      .take(3)
      .map((c) => '${categoryName(c.bucket)} ${r.percentOf(c.totalFils)}%')
      .join(language == 'ar' ? '، ' : ', ');
  return language == 'ar'
      ? 'أسبوعي مع بيزة: التزمت بحدي ${r.daysWithinLimit} من 7 أيام، وجمعت ${r.points} نقطة. وين راحت فلوسي: $top.'
      : 'My week with Beaza: within my limit on ${r.daysWithinLimit} of 7 days, ${r.points} points. Where it went: $top.';
}
