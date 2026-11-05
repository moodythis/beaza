import 'package:beaza/data/repositories/preferences_store.dart';
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

/// "Can I buy it?": what a purchase would do to today and to the rest of
/// the month. Worked out on the phone in fils; nothing is saved, the person
/// decides.
class PurchaseCheck {
  const PurchaseCheck({
    required this.itemFils,
    required this.leftTodayFils,
    required this.daysOfLimit,
    this.monthLeftFils,
    this.limitFromTomorrowFils,
    this.limitIfBoughtFils,
  });

  final int itemFils;

  /// Today's limit minus today's spending (negative when already over).
  final int leftTodayFils;

  /// How many days of the daily limit the price equals (rounded up); 0
  /// when no limit is set.
  final int daysOfLimit;

  /// Free money left in the month after today's spending; null without a
  /// budget plan.
  final int? monthLeftFils;

  /// The limit from tomorrow if the person does not buy it, and if they
  /// do. Null without a plan, or on the last day of the month.
  final int? limitFromTomorrowFils;
  final int? limitIfBoughtFils;

  bool get fitsToday => itemFils <= leftTodayFils;

  /// More than all the free money left this month.
  bool get beyondMonth => monthLeftFils != null && itemFils > monthLeftFils!;
}

PurchaseCheck checkPurchase({
  required int itemFils,
  required int dailyLimitFils,
  required int spentTodayFils,
  required Iterable<LedgerEntry> entries,
  required Day today,
  BudgetPlan? plan,
}) {
  assert(itemFils > 0);
  final days = dailyLimitFils > 0
      ? (itemFils + dailyLimitFils - 1) ~/ dailyLimitFils
      : 0;
  if (plan == null) {
    return PurchaseCheck(
      itemFils: itemFils,
      leftTodayFils: dailyLimitFils - spentTodayFils,
      daysOfLimit: days,
    );
  }
  final guardrail = Guardrail(const GuardrailSettings(dailyLimitFils: 0));
  var spent = 0;
  for (var d = Day(today.year, today.month, 1);
      d.compareTo(today) <= 0;
      d = d.addDays(1)) {
    spent += guardrail.spentOn(entries, d);
  }
  final monthLeft = plan.freeFils - spent;
  final daysInMonth = Day(today.year, today.month + 1, 1).addDays(-1).day;
  final daysAfter = daysInMonth - today.day;
  int perDay(int left) => left <= 0 ? 1 : (left ~/ daysAfter).clamp(1, left);
  return PurchaseCheck(
    itemFils: itemFils,
    leftTodayFils: dailyLimitFils - spentTodayFils,
    daysOfLimit: days,
    monthLeftFils: monthLeft,
    limitFromTomorrowFils: daysAfter == 0 ? null : perDay(monthLeft),
    limitIfBoughtFils: daysAfter == 0 ? null : perDay(monthLeft - itemFils),
  );
}

/// Where the plan is kept (PreferencesStore), in fils.
const String kBudgetIncomeKey = 'budget.income';
const String kBudgetFixedKey = 'budget.fixed';

/// The saved plan, or null while the limit is set by hand.
Future<BudgetPlan?> readBudgetPlan(PreferencesStore prefs) async {
  final income = int.tryParse(await prefs.read(kBudgetIncomeKey) ?? '');
  if (income == null || income <= 0) return null;
  final fixed = int.tryParse(await prefs.read(kBudgetFixedKey) ?? '') ?? 0;
  return BudgetPlan(incomeFils: income, fixedFils: fixed < 0 ? 0 : fixed);
}

/// Free money left in the month after today's spending, and the days after
/// today. Null on the last day of the month.
({int leftFils, int daysAfter})? monthLeft(
    BudgetPlan plan, Iterable<LedgerEntry> entries, Day today) {
  final guardrail = Guardrail(const GuardrailSettings(dailyLimitFils: 0));
  var spent = 0;
  for (var d = Day(today.year, today.month, 1);
      d.compareTo(today) <= 0;
      d = d.addDays(1)) {
    spent += guardrail.spentOn(entries, d);
  }
  final daysInMonth = Day(today.year, today.month + 1, 1).addDays(-1).day;
  final daysAfter = daysInMonth - today.day;
  if (daysAfter == 0) return null;
  return (leftFils: plan.freeFils - spent, daysAfter: daysAfter);
}

