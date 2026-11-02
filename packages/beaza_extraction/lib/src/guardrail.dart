/// Stage 7: the daily spending guardrail (Design section 4).
///
/// Pure functions over the reconciled ledger: the same entries and settings
/// always give the same summary, so the app simply recomputes after every
/// add, edit, exclusion or deletion (FR-5.1). Alerts are advisory and never
/// block a payment (FR-5.4). Texts are left to the app so they can be
/// localized; this file only decides numbers and whether to alert.
library;

import 'dart:math' as math;

import 'reconciler.dart';

/// Bahrain has no daylight saving time, so a fixed offset is exact.
const Duration kBahrainOffset = Duration(hours: 3);

/// A calendar day in Bahrain time, midnight to midnight.
class Day implements Comparable<Day> {
  const Day(this.year, this.month, this.day);

  /// The Bahrain day an instant falls on.
  factory Day.of(DateTime instant) {
    final local = instant.toUtc().add(kBahrainOffset);
    return Day(local.year, local.month, local.day);
  }

  final int year;
  final int month;
  final int day;

  /// First instant of the day, in UTC (21:00 UTC of the day before).
  DateTime get startUtc =>
      DateTime.utc(year, month, day).subtract(kBahrainOffset);

  /// First instant of the next day, in UTC.
  DateTime get endUtc =>
      DateTime.utc(year, month, day + 1).subtract(kBahrainOffset);

  bool contains(DateTime instant) {
    final u = instant.toUtc();
    return !u.isBefore(startUtc) && u.isBefore(endUtc);
  }

  Day addDays(int n) {
    final d = DateTime.utc(year, month, day + n);
    return Day(d.year, d.month, d.day);
  }

  Day get previous => addDays(-1);

  @override
  int compareTo(Day other) => year != other.year
      ? year.compareTo(other.year)
      : month != other.month
          ? month.compareTo(other.month)
          : day.compareTo(other.day);

  @override
  bool operator ==(Object other) =>
      other is Day &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => '$year-${_two(month)}-${_two(day)}';

  static String _two(int n) => n.toString().padLeft(2, '0');
}

class GuardrailSettings {
  const GuardrailSettings({
    required this.dailyLimitFils,
    this.microThresholdFils = 5000,
    this.alertCap = 4,
    this.microCountForTotal = 3,
    this.rollover = false,
    this.rolloverCapPercent = 50,
  })  : assert(dailyLimitFils >= 0),
        assert(microThresholdFils > 0),
        assert(alertCap >= 0),
        assert(microCountForTotal > 0),
        assert(rolloverCapPercent >= 0 && rolloverCapPercent <= 50);

  /// 0 means the user has not set a limit: totals still work, no alerts.
  final int dailyLimitFils;

  /// A counted debit at or below this is a micro-expense (default 5.000 BHD).
  final int microThresholdFils;

  /// At most this many alerts per day (FR-5.6).
  final int alertCap;

  /// After this many micro-expenses in a day, the running total is shown
  /// once (FR-5.3).
  final int microCountForTotal;

  /// Carry yesterday's unspent amount into today (FR-5.8). Off by default.
  final bool rollover;

  /// Rollover is capped at this percentage of the daily limit (at most 50).
  final int rolloverCapPercent;

  /// (income - commitments - savings) / days, rounded down to the fil, never
  /// below zero (SRS 1.4). The app shows this calculation to the user.
  static int suggestedDailyLimitFils({
    required int monthlyIncomeFils,
    required int fixedCommitmentsFils,
    required int savingsTargetFils,
    required int cycleDays,
  }) {
    if (cycleDays < 1) {
      throw ArgumentError.value(cycleDays, 'cycleDays', 'must be at least 1');
    }
    final free = monthlyIncomeFils - fixedCommitmentsFils - savingsTargetFils;
    return free <= 0 ? 0 : free ~/ cycleDays;
  }
}

enum AlertLevel {
  /// Under 50% of the limit.
  normal,

  /// 50% reached: amount spent and remaining.
  level1,

  /// 80% reached: also the latest micro-expenses.
  level2,

  /// 100% reached: the limit-exceeded event is logged.
  level3,
}

class MicroStats {
  const MicroStats(this.count, this.totalFils);

  final int count;
  final int totalFils;
}

class DaySummary {
  const DaySummary({
    required this.day,
    required this.baseLimitFils,
    required this.rolloverFils,
    required this.spentFils,
    required this.spendingCount,
    required this.micro,
    required this.latestMicro,
    required this.level,
  });

  final Day day;
  final int baseLimitFils;
  final int rolloverFils;
  final int spentFils;
  final int spendingCount;
  final MicroStats micro;

  /// Up to three micro-expenses of the day, newest first.
  final List<LedgerEntry> latestMicro;
  final AlertLevel level;

  int get limitFils => baseLimitFils + rolloverFils;

  /// Negative when the limit is exceeded, so the app can show the overrun.
  int get remainingFils => limitFils - spentFils;

  /// Whole percent of the limit used, 0 when no limit is set.
  int get percentUsed => limitFils <= 0 ? 0 : spentFils * 100 ~/ limitFils;
}

class Guardrail {
  const Guardrail(this.settings);

  final GuardrailSettings settings;

  static const int _latestMicroShown = 3;

  bool isMicro(LedgerEntry e) {
    final a = e.result.amountFils;
    return e.countsTowardSpending &&
        a != null &&
        a > 0 &&
        a <= settings.microThresholdFils;
  }

  /// Entries that count toward the limit on [day], oldest first.
  List<LedgerEntry> spendingOn(Iterable<LedgerEntry> entries, Day day) {
    final out = entries.where((e) {
      final t = e.result.timestamp;
      return e.countsTowardSpending && t != null && day.contains(t);
    }).toList();
    out.sort((a, b) {
      final byTime = a.result.timestamp!.compareTo(b.result.timestamp!);
      return byTime != 0 ? byTime : a.index.compareTo(b.index);
    });
    return out;
  }

  int spentOn(Iterable<LedgerEntry> entries, Day day) =>
      Reconciler.spentFils(spendingOn(entries, day));

  /// Yesterday's unspent part of the base limit, capped. Only one day is
  /// carried, so rollover never compounds over a week.
  int rolloverFor(Iterable<LedgerEntry> entries, Day day) {
    final limit = settings.dailyLimitFils;
    if (!settings.rollover || limit == 0) return 0;
    final unspent = limit - spentOn(entries, day.previous);
    if (unspent <= 0) return 0;
    return math.min(unspent, limit * settings.rolloverCapPercent ~/ 100);
  }

  AlertLevel levelFor(int spentFils, int limitFils) {
    if (limitFils <= 0) return AlertLevel.normal;
    final scaled = spentFils * 100;
    if (scaled >= 100 * limitFils) return AlertLevel.level3;
    if (scaled >= 80 * limitFils) return AlertLevel.level2;
    if (scaled >= 50 * limitFils) return AlertLevel.level1;
    return AlertLevel.normal;
  }

  DaySummary summarize(Iterable<LedgerEntry> entries, Day day) {
    final all = entries.toList();
    final spending = spendingOn(all, day);
    final spent = Reconciler.spentFils(spending);
    final micro = spending.where(isMicro).toList();
    final rollover = rolloverFor(all, day);
    return DaySummary(
      day: day,
      baseLimitFils: settings.dailyLimitFils,
      rolloverFils: rollover,
      spentFils: spent,
      spendingCount: spending.length,
      micro: _stats(micro),
      latestMicro: micro.reversed.take(_latestMicroShown).toList(),
      level: levelFor(spent, settings.dailyLimitFils + rollover),
    );
  }

  /// Micro-expenses from [from] to [to], both days included.
  MicroStats microStats(Iterable<LedgerEntry> entries, Day from, Day to) {
    final start = from.startUtc;
    final end = to.endUtc;
    return _stats(entries.where((e) {
      final t = e.result.timestamp?.toUtc();
      return isMicro(e) && t != null && !t.isBefore(start) && t.isBefore(end);
    }));
  }

  /// The seven days ending on [day] (FR-4.4 weekly view).
  MicroStats weeklyMicro(Iterable<LedgerEntry> entries, Day day) =>
      microStats(entries, day.addDays(-6), day);

  static MicroStats _stats(Iterable<LedgerEntry> micro) {
    var count = 0;
    var total = 0;
    for (final e in micro) {
      count++;
      total += e.result.amountFils ?? 0;
    }
    return MicroStats(count, total);
  }
}

/// What was already sent on one day. The app stores it next to the Alerts
/// table and passes it back on the next recompute.
class AlertLog {
  const AlertLog({
    required this.day,
    this.sent = 0,
    this.highestLevel = AlertLevel.normal,
    this.microTotalShown = false,
    this.limitExceededLogged = false,
  });

  final Day day;
  final int sent;
  final AlertLevel highestLevel;
  final bool microTotalShown;
  final bool limitExceededLogged;

  AlertLog copyWith({
    int? sent,
    AlertLevel? highestLevel,
    bool? microTotalShown,
    bool? limitExceededLogged,
  }) =>
      AlertLog(
        day: day,
        sent: sent ?? this.sent,
        highestLevel: highestLevel ?? this.highestLevel,
        microTotalShown: microTotalShown ?? this.microTotalShown,
        limitExceededLogged: limitExceededLogged ?? this.limitExceededLogged,
      );
}

/// One notification. [level] is [AlertLevel.normal] when the only news is
/// the micro-expense total.
class GuardrailAlert {
  const GuardrailAlert({
    required this.summary,
    required this.level,
    required this.includesMicroTotal,
  });

  final DaySummary summary;
  final AlertLevel level;
  final bool includesMicroTotal;
}

enum SuppressReason { snoozed, capReached }

class AlertDecision {
  const AlertDecision({
    required this.log,
    this.alert,
    this.suppressed,
    this.logLimitExceeded = false,
  });

  /// The log to store for the day.
  final AlertLog log;

  /// The notification to show, if any.
  final GuardrailAlert? alert;

  /// Set when an alert was due but not shown.
  final SuppressReason? suppressed;

  /// True the first time the day reaches 100%: the app logs the
  /// limit-exceeded event (pilot data), whether or not an alert is shown.
  final bool logLimitExceeded;
}

/// Decides whether a recompute should notify.
///
/// Rules: a level alerts only when it is higher than any level already
/// alerted that day, so an edit that drops the day to a lower state and
/// back does not repeat the alert. Several levels crossed by one
/// transaction give one alert at the highest. The micro-expense total is
/// shown once per day and rides along with a level alert when both are due.
/// While snoozed, or once the cap is reached, nothing is recorded as sent,
/// so a level still due fires on the first recompute after the snooze.
class AlertPlanner {
  const AlertPlanner(this.settings);

  final GuardrailSettings settings;

  AlertDecision decide(
    DaySummary summary,
    AlertLog? previous, {
    required DateTime now,
    DateTime? snoozedUntil,
  }) {
    var log = previous != null && previous.day == summary.day
        ? previous
        : AlertLog(day: summary.day);

    final logExceeded =
        summary.level == AlertLevel.level3 && !log.limitExceededLogged;
    if (logExceeded) log = log.copyWith(limitExceededLogged: true);

    final newLevel = summary.level.index > log.highestLevel.index;
    final microDue = !log.microTotalShown &&
        summary.micro.count >= settings.microCountForTotal;
    if (!newLevel && !microDue) {
      return AlertDecision(log: log, logLimitExceeded: logExceeded);
    }

    SuppressReason? reason;
    if (snoozedUntil != null && now.isBefore(snoozedUntil)) {
      reason = SuppressReason.snoozed;
    } else if (log.sent >= settings.alertCap) {
      reason = SuppressReason.capReached;
    }
    if (reason != null) {
      return AlertDecision(
          log: log, suppressed: reason, logLimitExceeded: logExceeded);
    }

    final alert = GuardrailAlert(
      summary: summary,
      level: newLevel ? summary.level : AlertLevel.normal,
      includesMicroTotal: microDue,
    );
    return AlertDecision(
      log: log.copyWith(
        sent: log.sent + 1,
        highestLevel: newLevel ? summary.level : null,
        microTotalShown: microDue ? true : null,
      ),
      alert: alert,
      logLimitExceeded: logExceeded,
    );
  }
}
