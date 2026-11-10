import 'package:beaza_extraction/beaza_extraction.dart';

/// Finished days in a row, ending yesterday, whose net spending stayed
/// within [limitFils] (a day with no spending counts). At most [max]; 0
/// when no limit is set. Uses today's limit for every day, as the points do
/// (FR-9.4): a worked-out limit that changed during the month is not
/// replayed.
int streakDays(
  Iterable<LedgerEntry> entries,
  Day today,
  int limitFils, {
  int max = 30,
}) {
  if (limitFils <= 0) return 0;
  final list = entries.toList();
  final guardrail = Guardrail(GuardrailSettings(dailyLimitFils: limitFils));
  var n = 0;
  for (var d = today.addDays(-1); n < max; d = d.addDays(-1)) {
    if (guardrail.spentOn(list, d) > limitFils) break;
    n++;
  }
  return n;
}

/// Points a streak freeze costs.
const int kFreezeCost = 50;

/// What the streak is, and what happened to the freeze while working it
/// out.
class StreakResult {
  const StreakResult({
    required this.days,
    required this.frozen,
    required this.freezeHeld,
    this.usedOn,
  });

  /// Finished days in a row within the limit. A frozen day keeps the row
  /// going but is not counted.
  final int days;

  /// Days over the limit that a freeze covered.
  final Set<Day> frozen;

  /// A freeze is still held after this.
  final bool freezeHeld;

  /// The day a held freeze was just used on, if it was.
  final Day? usedOn;
}

/// The streak ending yesterday, with the streak freeze.
///
/// Each day is judged against the limit the app showed on that day
/// ([limitOn]); a day the app did not see uses [limitFils]. A day over its
/// limit ends the streak unless it is in [frozen], or a freeze is held and
/// was bought on or before that day ([freezeBoughtOn]): then the freeze is
/// used on it. A freeze bought later cannot repair an older break. Days
/// before the first recorded entry are not counted.
StreakResult streakWithFreeze(
  Iterable<LedgerEntry> entries,
  Day today,
  int limitFils, {
  Map<Day, int> limitOn = const {},
  Set<Day> frozen = const {},
  Day? freezeBoughtOn,
  int max = 365,
}) {
  final list = entries.toList();
  const g = Guardrail(GuardrailSettings(dailyLimitFils: 0));
  final covered = {...frozen};
  var held = freezeBoughtOn != null;
  Day? usedOn;
  var n = 0;
  var steps = 0;
  // The streak cannot start before the first thing the app recorded: days
  // before that are unknown, not days within the limit.
  Day? first;
  for (final e in list) {
    final t = e.result.timestamp;
    if (t == null) continue;
    final d = Day.of(t);
    if (first == null || d.compareTo(first) < 0) first = d;
  }
  if (first == null || (limitFils <= 0 && limitOn.isEmpty)) {
    return StreakResult(days: 0, frozen: covered, freezeHeld: held);
  }
  for (var d = today.previous;
      steps < max && d.compareTo(first) >= 0;
      d = d.previous, steps++) {
    final limit = limitOn[d] ?? limitFils;
    if (limit <= 0) break;
    if (g.spentOn(list, d) <= limit) {
      n++;
      continue;
    }
    if (covered.contains(d)) continue;
    if (held && d.compareTo(freezeBoughtOn!) >= 0) {
      covered.add(d);
      held = false;
      usedOn = d;
      continue;
    }
    break;
  }
  return StreakResult(
      days: n, frozen: covered, freezeHeld: held, usedOn: usedOn);
}
