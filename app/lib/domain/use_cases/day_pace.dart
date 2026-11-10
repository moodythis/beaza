import 'package:beaza_extraction/beaza_extraction.dart';

/// How many past days the usual day is learnt from.
const int kPaceHistoryDays = 28;

/// Fewer past spending days than this: no forecast (too little to go on).
const int kPaceMinDays = 5;

/// Minutes in a Bahrain day.
const int kDayMinutes = 24 * 60;

/// Late night starts at 22:00 (the same window as the tips and the report).
const int kLateNightStart = 22 * 60;

enum PaceStatus {
  /// The usual rest of the day still fits, with a fifth of the limit spare.
  onTrack,

  /// It fits, but ends at 80% of the limit or more.
  tight,

  /// Not passed yet, but a usual rest of the day would pass it.
  willPass,

  /// Already over today's limit.
  passed,
}

/// Today's pace against the person's own usual day, worked out on the
/// phone in integer fils, Bahrain time. No model is involved.
///
/// The usual day is learnt from the last [kPaceHistoryDays] days that had
/// spending: for each hour, the share (per mille) of that day's spending
/// already made by then, averaged over the days. The rest of today is
/// expected to follow that shape at the size of an average spending day.
class DayPace {
  const DayPace({
    required this.usualShare,
    required this.usualDayFils,
    required this.todayByHour,
    required this.nowMinute,
    required this.spentFils,
    required this.limitFils,
    required this.historyDays,
  });

  /// usualShare[h] = per mille of a usual day's spending made before hour
  /// h (h = 0..24): usualShare[0] is 0, usualShare[24] is 1000.
  final List<int> usualShare;

  /// An average day with spending, in fils.
  final int usualDayFils;

  /// Today's net spending made before hour h, for h = 0..current hour + 1
  /// (the last value is everything so far).
  final List<int> todayByHour;

  /// Minutes since midnight, Bahrain time.
  final int nowMinute;

  /// Today's net spending so far (never below 0).
  final int spentFils;

  /// Today's limit (with any rollover).
  final int limitFils;

  /// How many past days the usual day comes from.
  final int historyDays;

  /// Share of a usual day made by [minute] (0..1440), per mille, read
  /// straight between the hourly points.
  int shareAt(int minute) {
    final m = minute.clamp(0, kDayMinutes);
    final h = m ~/ 60;
    if (h >= 24) return usualShare[24];
    final into = m - h * 60;
    return usualShare[h] + (usualShare[h + 1] - usualShare[h]) * into ~/ 60;
  }

  /// What a usual day still spends after now.
  int get stillUsualFils =>
      usualDayFils * (1000 - shareAt(nowMinute)) ~/ 1000;

  /// Where today ends if the rest of it is usual.
  int get expectedFils => spentFils + stillUsualFils;

  /// Expected spending from now to [minute] on top of what is spent.
  int projectedAt(int minute) => minute <= nowMinute
      ? spentFils
      : spentFils +
          usualDayFils * (shareAt(minute) - shareAt(nowMinute)) ~/ 1000;

  /// Of [stillUsualFils], the part usually spent from 22:00 to midnight.
  int get lateFils {
    final from = nowMinute > kLateNightStart ? nowMinute : kLateNightStart;
    return usualDayFils * (1000 - shareAt(from)) ~/ 1000;
  }

  PaceStatus get status {
    if (spentFils > limitFils) return PaceStatus.passed;
    if (expectedFils > limitFils) return PaceStatus.willPass;
    if (expectedFils * 100 >= limitFils * 80) return PaceStatus.tight;
    return PaceStatus.onTrack;
  }

  /// By how much a usual rest of the day passes the limit (0 if it fits).
  int get overByFils =>
      expectedFils > limitFils ? expectedFils - limitFils : 0;

  /// What is left at the end of a usual day (0 if it passes).
  int get leftFils =>
      limitFils > expectedFils ? limitFils - expectedFils : 0;

  /// The first quarter hour at which a usual rest of the day passes the
  /// limit; null when it does not, or when it is already passed.
  int? get passMinute {
    if (status != PaceStatus.willPass) return null;
    for (var m = (nowMinute ~/ 15 + 1) * 15; m <= kDayMinutes; m += 15) {
      if (projectedAt(m) > limitFils) return m;
    }
    return null;
  }
}

/// Local Bahrain minute of the day of [t].
int bahrainMinute(DateTime t) {
  final local = t.toUtc().add(kBahrainOffset);
  return local.hour * 60 + local.minute;
}

/// The pace for [now]'s day, or null when there is no limit or fewer than
/// [kPaceMinDays] past days with spending.
DayPace? dayPace(
  Iterable<LedgerEntry> entries,
  DateTime now, {
  required int limitFils,
}) {
  if (limitFils <= 0) return null;
  final today = Day.of(now);
  final first = today.addDays(-kPaceHistoryDays);
  // Net amount per day and hour (spending in, money paid back out).
  final byDay = <Day, List<int>>{};
  for (final e in entries) {
    final t = e.result.timestamp;
    final c = e.countedFils;
    if (t == null || c == 0) continue;
    final d = Day.of(t);
    if (d.compareTo(first) < 0 || d.compareTo(today) > 0) continue;
    (byDay[d] ??= List.filled(24, 0))[bahrainMinute(t) ~/ 60] += c;
  }

  final sums = List.filled(25, 0);
  var days = 0;
  var total = 0;
  for (final MapEntry(key: d, value: hours) in byDay.entries) {
    if (d == today) continue;
    final dayTotal = hours.fold(0, (a, b) => a + b);
    if (dayTotal <= 0) continue;
    days++;
    total += dayTotal;
    var run = 0;
    for (var h = 0; h < 24; h++) {
      sums[h] += (run < 0 ? 0 : run) * 1000 ~/ dayTotal;
      run += hours[h];
    }
    sums[24] += 1000;
  }
  if (days < kPaceMinDays) return null;
  final share = [
    for (var h = 0; h <= 24; h++) (sums[h] ~/ days).clamp(0, 1000),
  ];
  // Never going back down (a refund late in a day can dent one curve).
  for (var h = 1; h <= 24; h++) {
    if (share[h] < share[h - 1]) share[h] = share[h - 1];
  }
  share[24] = 1000;

  final nowMinute = bahrainMinute(now);
  final todayHours = byDay[today] ?? List.filled(24, 0);
  final upTo = nowMinute ~/ 60;
  final byHour = <int>[0];
  var run = 0;
  for (var h = 0; h <= upTo; h++) {
    run += todayHours[h];
    byHour.add(run < 0 ? 0 : run);
  }
  return DayPace(
    usualShare: share,
    usualDayFils: total ~/ days,
    todayByHour: byHour,
    nowMinute: nowMinute,
    spentFils: byHour.last,
    limitFils: limitFils,
    historyDays: days,
  );
}
