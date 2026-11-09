import 'package:beaza/data/repositories/preferences_store.dart';
import 'package:beaza_extraction/beaza_extraction.dart';

/// How the person sets money aside before the daily limit is worked out.
/// The percentages are this app's choices for each named way of budgeting;
/// where a source gives its own number (Clason says a tenth) the screen
/// says so.
enum BudgetProfile {
  /// No savings set aside (the old behaviour).
  none,

  /// Pay yourself first: 20% set aside on day one.
  payYourselfFirst,

  /// 50/30/20 (Warren and Tyagi, 2005): 20% set aside; commitments over half
  /// the income get a warning.
  fiftyThirtyTwenty,

  /// 70/20/10 rule of thumb: 20% savings plus 10% buffer set aside.
  seventyTwentyTen,

  /// 20% set aside, and weekend days (Thursday to Saturday) get a bigger
  /// share of each day's limit.
  weekendWeighted,

  /// Kakeibo and zero-based budgeting: 30% set aside for a goal.
  kakeibo,

  /// An amount the person types.
  custom,
}

/// The share of income each profile sets aside, in percent ([custom] uses
/// the typed amount).
int savingsPercent(BudgetProfile p) => switch (p) {
      BudgetProfile.none || BudgetProfile.custom => 0,
      BudgetProfile.payYourselfFirst ||
      BudgetProfile.fiftyThirtyTwenty ||
      BudgetProfile.weekendWeighted =>
        20,
      BudgetProfile.seventyTwentyTen || BudgetProfile.kakeibo => 30,
    };

/// Weight of a weekend day against 100 for a weekday. 135 is this app's
/// assumption, not a published number.
const int kWeekendWeight = 135;

/// Thursday, Friday and Saturday get the weekend weight.
bool isWeightedWeekend(Day d) {
  final w = DateTime.utc(d.year, d.month, d.day).weekday;
  return w == DateTime.thursday || w == DateTime.friday || w == DateTime.saturday;
}

/// What the person earns in a month, what is already spoken for (rent,
/// subscriptions, installments) and what is set aside to save. All in fils.
class BudgetPlan {
  const BudgetPlan({
    required this.incomeFils,
    this.fixedFils = 0,
    this.savingsFils = 0,
    this.profile = BudgetProfile.none,
  })  : assert(incomeFils >= 0),
        assert(fixedFils >= 0),
        assert(savingsFils >= 0);

  /// The plan for [profile]: savings worked out from the income, or
  /// [customSavingsFils] for [BudgetProfile.custom].
  factory BudgetPlan.withProfile({
    required int incomeFils,
    int fixedFils = 0,
    BudgetProfile profile = BudgetProfile.none,
    int customSavingsFils = 0,
  }) =>
      BudgetPlan(
        incomeFils: incomeFils,
        fixedFils: fixedFils,
        savingsFils: profile == BudgetProfile.custom
            ? customSavingsFils
            : incomeFils * savingsPercent(profile) ~/ 100,
        profile: profile,
      );

  final int incomeFils;
  final int fixedFils;

  /// Set aside on day one; never part of the daily limit.
  final int savingsFils;
  final BudgetProfile profile;

  bool get weekendWeighted => profile == BudgetProfile.weekendWeighted;

  /// What is left to spend freely in the month, after commitments and
  /// savings.
  int get freeFils => incomeFils - fixedFils - savingsFils;

  /// The plan can be used only when something is left to spend.
  bool get isValid => incomeFils > 0 && freeFils > 0;

  /// 50/30/20 says needs should take at most half the income.
  bool get commitmentsOverHalf => fixedFils * 2 > incomeFils;
}

/// The limit for [day] out of [leftFils], spread over [day] and the days
/// after it in the month. Weighted plans give each weekend day
/// [kWeekendWeight] against 100. Rounds down, so the days never get more
/// than what is left; 1 fil when nothing is left (0 would mean "no limit").
int dayShareFils(int leftFils, Day day, {bool weighted = false}) {
  if (leftFils <= 0) return 1;
  final daysInMonth = Day(day.year, day.month + 1, 1).addDays(-1).day;
  var total = 0;
  for (var d = day; d.day <= daysInMonth && d.month == day.month; d = d.addDays(1)) {
    total += weighted && isWeightedWeekend(d) ? kWeekendWeight : 100;
  }
  final mine = weighted && isWeightedWeekend(day) ? kWeekendWeight : 100;
  return (leftFils * mine ~/ total).clamp(1, leftFils);
}

/// The safe amount to spend today: what is left of the free money, divided
/// over the days left in the month, today included.
///
/// Spending before today is taken off first, so a day that went over the
/// limit lowers every later day by its share: the shortfall is spread over
/// the rest of the month without any extra rule. Savings are never part of
/// it. Pure and integer-only, so the same ledger always gives the same
/// number.
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
  return dayShareFils(plan.freeFils - spentBefore, today,
      weighted: plan.weekendWeighted);
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
  int perDay(int left) =>
      dayShareFils(left, today.addDays(1), weighted: plan.weekendWeighted);
  return PurchaseCheck(
    itemFils: itemFils,
    leftTodayFils: dailyLimitFils - spentTodayFils,
    daysOfLimit: days,
    monthLeftFils: monthLeft,
    limitFromTomorrowFils: daysAfter == 0 ? null : perDay(monthLeft),
    limitIfBoughtFils: daysAfter == 0 ? null : perDay(monthLeft - itemFils),
  );
}

/// Where the plan is kept (PreferencesStore), in fils. Kept on the phone
/// like the income itself, not synced.
const String kBudgetIncomeKey = 'budget.income';
const String kBudgetFixedKey = 'budget.fixed';
const String kBudgetProfileKey = 'budget.profile';
const String kBudgetCustomSavingsKey = 'budget.savings';

/// The saved plan, or null while the limit is set by hand.
Future<BudgetPlan?> readBudgetPlan(PreferencesStore prefs) async {
  final income = int.tryParse(await prefs.read(kBudgetIncomeKey) ?? '');
  if (income == null || income <= 0) return null;
  final fixed = int.tryParse(await prefs.read(kBudgetFixedKey) ?? '') ?? 0;
  final name = await prefs.read(kBudgetProfileKey);
  final profile = BudgetProfile.values
          .where((p) => p.name == name)
          .firstOrNull ??
      BudgetProfile.none;
  final custom =
      int.tryParse(await prefs.read(kBudgetCustomSavingsKey) ?? '') ?? 0;
  final plan = BudgetPlan.withProfile(
    incomeFils: income,
    fixedFils: fixed < 0 ? 0 : fixed,
    profile: profile,
    customSavingsFils: custom < 0 ? 0 : custom,
  );
  // A plan saved before it became invalid falls back to no savings.
  return plan.isValid
      ? plan
      : BudgetPlan(incomeFils: income, fixedFils: fixed < 0 ? 0 : fixed);
}

/// Saves [plan] ([BudgetPlan.withProfile]'s inputs).
Future<void> writeBudgetPlan(PreferencesStore prefs, BudgetPlan plan) async {
  await prefs.write(kBudgetIncomeKey, '${plan.incomeFils}');
  await prefs.write(kBudgetFixedKey, '${plan.fixedFils}');
  await prefs.write(kBudgetProfileKey, plan.profile.name);
  await prefs.write(kBudgetCustomSavingsKey,
      plan.profile == BudgetProfile.custom ? '${plan.savingsFils}' : null);
}

/// Forgets the plan: the limit is set by hand again.
Future<void> clearBudgetPlan(PreferencesStore prefs) async {
  for (final k in [
    kBudgetIncomeKey,
    kBudgetFixedKey,
    kBudgetProfileKey,
    kBudgetCustomSavingsKey,
  ]) {
    await prefs.write(k, null);
  }
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

