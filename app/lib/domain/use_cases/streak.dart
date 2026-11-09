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
