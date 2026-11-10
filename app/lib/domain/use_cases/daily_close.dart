import 'package:beaza_extraction/beaza_extraction.dart';

/// Where the unspent part of a day's limit went.
enum CloseKind {
  /// Sent to the savings goal.
  goal,

  /// Carried to the next day's limit, once.
  rollover,
}

/// One closed day: what was left of its limit and where it went.
class DayClose {
  const DayClose(this.day, this.kind, this.fils);

  final Day day;
  final CloseKind kind;

  /// What was moved (for [CloseKind.rollover], after the cap).
  final int fils;

  Map<String, Object?> toJson() => {
        'day': dayKey(day),
        'kind': kind.name,
        'fils': fils,
      };

  static DayClose fromJson(Map<String, Object?> j) => DayClose(
        parseDayKey(j['day']! as String),
        CloseKind.values.byName(j['kind']! as String),
        j['fils']! as int,
      );
}

/// "2026-11-10".
String dayKey(Day d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Day parseDayKey(String s) {
  final p = s.split('-').map(int.parse).toList();
  return Day(p[0], p[1], p[2]);
}

/// The close is offered from 20:00 Bahrain time.
const int kCloseFromMinute = 20 * 60;

/// The reminder goes out at 21:30 Bahrain time.
const int kCloseReminderMinute = 21 * 60 + 30;

/// A carried-over surplus is at most this share of the next day's own
/// limit (FR-5.8).
const int kCloseRolloverCapPercent = 50;

/// Points for sending a day's surplus to the goal.
const int kClosePoints = 10;

/// A day that can be closed now.
class CloseOffer {
  const CloseOffer({
    required this.day,
    required this.surplusFils,
    required this.yesterday,
    required this.noSpending,
  });

  final Day day;

  /// What is left of that day's limit, above 0.
  final int surplusFils;

  /// It is yesterday that was left open, not today.
  final bool yesterday;

  /// Nothing was recorded that day: closing it is the person saying so.
  final bool noSpending;

  /// What carrying it over adds to the next day: the surplus, at most
  /// half of [baseLimitFils].
  int rolloverFils(int baseLimitFils) {
    final cap = baseLimitFils * kCloseRolloverCapPercent ~/ 100;
    return surplusFils < cap ? surplusFils : cap;
  }
}

int _minuteOf(DateTime t) {
  final local = t.toUtc().add(kBahrainOffset);
  return local.hour * 60 + local.minute;
}

/// What can be closed at [now]: yesterday, if it was left open with money
/// unspent (only when the app saw that day's limit, [yesterdayLimitFils]);
/// otherwise today from 20:00 with money unspent. Null when there is
/// nothing to close.
CloseOffer? closeOffer({
  required Iterable<LedgerEntry> entries,
  required DateTime now,
  required int todayLimitFils,
  required int? yesterdayLimitFils,
  required List<DayClose> closes,
}) {
  final list = entries.toList();
  final today = Day.of(now);
  const g = Guardrail(GuardrailSettings(dailyLimitFils: 0));
  bool closed(Day d) => closes.any((c) => c.day == d);
  CloseOffer? offer(Day d, int limit, bool yesterday) {
    if (limit <= 0 || closed(d)) return null;
    final net = g.spentOn(list, d);
    final left = limit - (net < 0 ? 0 : net);
    if (left <= 0) return null;
    return CloseOffer(
      day: d,
      surplusFils: left,
      yesterday: yesterday,
      noSpending: g.spendingOn(list, d).isEmpty,
    );
  }

  final y = yesterdayLimitFils == null
      ? null
      : offer(today.previous, yesterdayLimitFils, true);
  if (y != null) return y;
  if (_minuteOf(now) < kCloseFromMinute) return null;
  return offer(today, todayLimitFils, false);
}

/// The one-day addition to [day]'s limit from closing the day before with
/// "carry over", capped again against [baseLimitFils] (the limit can have
/// changed since).
int boostFor(List<DayClose> closes, Day day, int baseLimitFils) {
  if (baseLimitFils <= 0) return 0;
  final before = day.previous;
  final cap = baseLimitFils * kCloseRolloverCapPercent ~/ 100;
  for (final c in closes) {
    if (c.kind == CloseKind.rollover && c.day == before) {
      return c.fils < cap ? c.fils : cap;
    }
  }
  return 0;
}

/// Money sent to the goal from days of [today]'s month before [today]:
/// taken off the month's free money, so it is not handed out again as a
/// daily limit.
int sweptThisMonth(List<DayClose> closes, Day today) => closes
    .where((c) =>
        c.kind == CloseKind.goal &&
        c.day.year == today.year &&
        c.day.month == today.month &&
        c.day.compareTo(today) < 0)
    .fold(0, (a, c) => a + c.fils);

/// Goal sweeps in the 30 days before [today] (each earns [kClosePoints]).
int sweepsInLast30(List<DayClose> closes, Day today) => closes
    .where((c) =>
        c.kind == CloseKind.goal &&
        c.day.compareTo(today.addDays(-30)) >= 0 &&
        c.day.compareTo(today) <= 0)
    .length;

/// The next 21:30 Bahrain time after [now] on a day that is not closed
/// yet, as a UTC instant.
DateTime nextCloseReminder(DateTime now, {required bool closedToday}) {
  final local = now.toUtc().add(kBahrainOffset);
  var at = DateTime.utc(local.year, local.month, local.day,
      kCloseReminderMinute ~/ 60, kCloseReminderMinute % 60);
  if (closedToday || !at.isAfter(local)) at = at.add(const Duration(days: 1));
  return at.subtract(kBahrainOffset);
}
