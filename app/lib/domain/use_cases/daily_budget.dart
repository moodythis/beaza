import 'package:beaza_extraction/beaza_extraction.dart';

/// What the person earns in a month and what is already spoken for (rent,
/// subscriptions, installments). Both in fils.
class BudgetPlan {
  const BudgetPlan({required this.incomeFils, this.fixedFils = 0})
      : assert(incomeFils >= 0),
        assert(fixedFils >= 0);

  final int incomeFils;
  final int fixedFils;

  /// What is left to spend freely in the month.
  int get freeFils => incomeFils - fixedFils;
}

/// The safe amount to spend today: what is left of the free money, divided
/// over the days left in the month, today included.
///
/// Spending before today is taken off first, so a day that went over the
/// limit lowers every later day by its share: the shortfall is spread over
/// the rest of the month without any extra rule. Pure and integer-only, so
/// the same ledger always gives the same number.
int safeDailyLimitFils(
  BudgetPlan plan,
  Iterable<LedgerEntry> entries,
  Day today,
) {
  final guardrail = Guardrail(const GuardrailSettings(dailyLimitFils: 0));
  var spentBefore = 0;
  for (var d = Day(today.year, today.month, 1);
      d.compareTo(today) < 0;
      d = d.addDays(1)) {
    spentBefore += guardrail.spentOn(entries, d);
  }
  final daysInMonth = Day(today.year, today.month + 1, 1).addDays(-1).day;
  final daysLeft = daysInMonth - today.day + 1;
  final left = plan.freeFils - spentBefore;
  // 0 would mean "no limit set", so an empty month is 1 fil: any spending
  // is over it.
  return left <= 0 ? 1 : (left ~/ daysLeft).clamp(1, left);
}
