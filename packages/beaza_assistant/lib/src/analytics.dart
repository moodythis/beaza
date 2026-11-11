/// Totals, shares and the day's guardrail state, in integer fils, on the
/// phone. The only place the assistant does arithmetic on money.
library;

import 'package:beaza_extraction/beaza_extraction.dart';

/// [weekday]: the last day with a given weekday, today included ("يوم الأحد").
enum PeriodKind { today, yesterday, week, month, weekday, lastWeek, lastMonth }

/// Bahrain days, both ends included.
class Period {
  const Period(this.kind, this.from, this.to);

  /// "week" is the last 7 days including today, like the home screen;
  /// "month" is from the 1st of this month to today.
  ///
  /// [weekday] (DateTime.monday..sunday) is used only with
  /// [PeriodKind.weekday]: that day this week, or last week if it is still
  /// to come.
  factory Period.of(PeriodKind kind, Day today, {int? weekday}) => switch (kind) {
        PeriodKind.today => Period(kind, today, today),
        PeriodKind.yesterday => Period(kind, today.previous, today.previous),
        PeriodKind.week => Period(kind, today.addDays(-6), today),
        PeriodKind.month =>
          Period(kind, Day(today.year, today.month, 1), today),
        PeriodKind.lastWeek =>
          Period(kind, today.addDays(-13), today.addDays(-7)),
        PeriodKind.lastMonth => () {
            final end = Day(today.year, today.month, 1).addDays(-1);
            return Period(kind, Day(end.year, end.month, 1), end);
          }(),
        PeriodKind.weekday => () {
            final back = (dayOfWeek(today) - (weekday ?? dayOfWeek(today)) + 7) % 7;
            final d = today.addDays(-back);
            return Period(kind, d, d);
          }(),
      };

  final PeriodKind kind;
  final Day from;
  final Day to;

  bool contains(DateTime t) {
    final u = t.toUtc();
    return !u.isBefore(from.startUtc) && u.isBefore(to.endUtc);
  }

  int get days {
    var n = 1;
    var d = from;
    while (d != to) {
      d = d.addDays(1);
      n++;
    }
    return n;
  }
}

/// DateTime.monday (1) to DateTime.sunday (7) for a Bahrain day.
int dayOfWeek(Day d) => DateTime.utc(d.year, d.month, d.day).weekday;

/// A category's total. [bucket] is a category, 'transfer' or 'unsorted'.
class BucketTotal {
  const BucketTotal(this.bucket, this.totalFils, this.count, this.percent);

  final String bucket;
  final int totalFils;
  final int count;

  /// Whole percent of the period's spending, rounded.
  final int percent;
}

const String kTransfer = 'transfer';
const String kUnsorted = 'unsorted';

/// Same groups as the home screen.
String spendingBucketOf(ExtractionResult r) {
  final c = r.category;
  if (c != null && c.isNotEmpty) return c;
  if (r.type == TxnType.transferOut || r.channel == Channel.transfer) {
    return kTransfer;
  }
  return kUnsorted;
}

/// Rounded whole percent of [part] in [whole]; 0 when [whole] is 0.
int percentOf(int part, int whole) =>
    whole <= 0 ? 0 : (part * 100 + whole ~/ 2) ~/ whole;

class SpendingSummaryBuilder {
  SpendingSummaryBuilder(
    Iterable<LedgerEntry> entries, {
    required this.settings,
    required this.today,
  })  : _all = entries.toList(),
        _spending = entries
            .where((e) =>
                e.countsTowardSpending &&
                e.result.timestamp != null &&
                e.result.amountFils != null)
            .toList();

  final GuardrailSettings settings;
  final Day today;
  final List<LedgerEntry> _all;

  /// Counted spending in BHD only: copies, own-account transfers, money
  /// received and foreign currency are left out, like the daily limit.
  final List<LedgerEntry> _spending;

  Iterable<ExtractionResult> _in(Period p,
          [bool Function(ExtractionResult r)? where]) =>
      _spending
          .map((e) => e.result)
          .where((r) => p.contains(r.timestamp!) && (where?.call(r) ?? true));

  int total(Period p, [bool Function(ExtractionResult r)? where]) =>
      _in(p, where).fold(0, (a, r) => a + r.amountFils!);

  int count(Period p, [bool Function(ExtractionResult r)? where]) =>
      _in(p, where).length;

  /// The counted purchases in [p], oldest first.
  List<ExtractionResult> items(Period p,
          [bool Function(ExtractionResult r)? where]) =>
      _in(p, where).toList();

  /// Days in [p] whose spending passed the daily limit.
  int daysOver(Period p) {
    if (settings.dailyLimitFils <= 0) return 0;
    final g = Guardrail(settings);
    var n = 0;
    for (var d = p.from; d.compareTo(p.to) <= 0; d = d.addDays(1)) {
      if (g.summarize(_all, d).spentFils > settings.dailyLimitFils) n++;
    }
    return n;
  }

  /// Largest first.
  List<BucketTotal> byBucket(Period p) {
    final totals = <String, int>{};
    final counts = <String, int>{};
    for (final r in _in(p)) {
      final b = spendingBucketOf(r);
      totals[b] = (totals[b] ?? 0) + r.amountFils!;
      counts[b] = (counts[b] ?? 0) + 1;
    }
    final sum = totals.values.fold(0, (a, b) => a + b);
    final out = [
      for (final b in totals.keys)
        BucketTotal(b, totals[b]!, counts[b]!, percentOf(totals[b]!, sum)),
    ]..sort((x, y) {
        final c = y.totalFils.compareTo(x.totalFils);
        return c != 0 ? c : x.bucket.compareTo(y.bucket);
      });
    return out;
  }

  DaySummary todaySummary() => Guardrail(settings).summarize(_all, today);

  MicroStats microIn(Period p) {
    final g = Guardrail(settings);
    final micro = _spending.where(
        (e) => g.isMicro(e) && p.contains(e.result.timestamp!));
    return MicroStats(
        micro.length, micro.fold(0, (a, e) => a + e.result.amountFils!));
  }
}
