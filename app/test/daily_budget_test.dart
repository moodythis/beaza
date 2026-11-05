import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/preferences_store.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/domain/use_cases/daily_budget.dart';
import 'package:beaza/ui/features/home/view_models/home_view_model.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime bh(int day, int hour, {int month = 11}) =>
    DateTime.utc(2026, month, day, hour).subtract(kBahrainOffset);

ExtractionResult purchase(int fils, DateTime at) => ExtractionResult(
      status: ExtractionStatus.transaction,
      amountFils: fils,
      currency: 'BHD',
      type: TxnType.purchase,
      direction: TxDirection.outgoing,
      timestamp: at,
    );

Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  // November 2026 has 30 days. 300.000 income - 150.000 fixed = 150.000 free.
  const plan = BudgetPlan(incomeFils: 300000, fixedFils: 150000);

  Future<int> limit(List<ExtractionResult> spent, Day today,
      [BudgetPlan p = plan]) async {
    final ledger =
        InMemoryLedgerRepository(initial: spent);
    return safeDailyLimitFils(p, await ledger.entries(), today);
  }

  test('first day: free money over the days of the month', () async {
    expect(await limit([], const Day(2026, 11, 1)), 5000);
  });

  test('earlier spending lowers the limit for the days left', () async {
    // 141.000 left over 29 days (Nov 2..30) = 4.862
    expect(await limit([purchase(9000, bh(1, 23))], const Day(2026, 11, 2)),
        4862);
  });

  test('a day over the limit is spread over the days left', () async {
    // 60.000 spent on day 1 (limit was 5.000): 90.000 over 29 days = 3.103
    expect(await limit([purchase(60000, bh(1, 10))], const Day(2026, 11, 2)),
        3103);
  });

  test("today's own spending does not change today's limit", () async {
    expect(await limit([purchase(4000, bh(2, 9))], const Day(2026, 11, 2)),
        await limit([], const Day(2026, 11, 2)));
  });

  test('money used up gives 1 fil, never 0 (0 means no limit)', () async {
    expect(await limit([purchase(200000, bh(1, 10))], const Day(2026, 11, 2)),
        1);
  });

  test('last day of the month and December work', () async {
    expect(await limit([], const Day(2026, 11, 30)), 150000);
    expect(await limit([], const Day(2026, 12, 31)), 150000);
    expect(await limit([], const Day(2026, 12, 1)), 150000 ~/ 31);
  });

  test('commitments lower the limit, never raise it', () async {
    final spent = [purchase(9000, bh(1, 23))];
    const today = Day(2026, 11, 2);
    final without =
        await limit(spent, today, const BudgetPlan(incomeFils: 300000));
    final withFixed = await limit(spent, today,
        const BudgetPlan(incomeFils: 300000, fixedFils: 105000));
    expect(withFixed, lessThan(without));
  });

  test('the view model keeps the saved limit in step with the plan', () async {
    final ledger = InMemoryLedgerRepository(
        initial: [purchase(9000, bh(1, 23))]);
    final settings = InMemorySettingsRepository(
        const GuardrailSettings(dailyLimitFils: 0));
    final prefs = MemoryPreferencesStore();
    final vm = HomeViewModel(
        ledger: ledger,
        settings: settings,
        preferences: prefs,
        clock: () => bh(2, 12));
    await vm.setBudget(plan);
    await settle();
    expect((await settings.load()).dailyLimitFils, 4862);
    expect(vm.state!.summary.baseLimitFils, 4862);
    expect(vm.budget, isNotNull);

    // A new expense today does not move today's limit.
    await vm.addExpense(amountFils: 3000);
    await settle();
    expect((await settings.load()).dailyLimitFils, 4862);

    // Setting a limit by hand replaces the plan.
    await vm.setDailyLimit(7000);
    await settle();
    expect(vm.budget, isNull);
    expect((await settings.load()).dailyLimitFils, 7000);
    expect(prefs.values.containsKey('budget.income'), isFalse);
    vm.dispose();
  });

  group('can I buy it?', () {
    // Plan: 150.000 free in November (30 days). 9.000 spent on the 1st,
    // 4.000 today (the 2nd), whose limit is 4.862.
    Future<PurchaseCheck> check(int item,
        {Day today = const Day(2026, 11, 2), BudgetPlan? p = plan}) async {
      final ledger = InMemoryLedgerRepository(
          initial: [purchase(9000, bh(1, 23)), purchase(4000, bh(2, 9))]);
      return checkPurchase(
        itemFils: item,
        dailyLimitFils: 4862,
        spentTodayFils: 4000,
        entries: await ledger.entries(),
        today: today,
        plan: p,
      );
    }

    test('the limit from tomorrow, with and without it', () async {
      final c = await check(18000);
      expect(c.leftTodayFils, 862);
      expect(c.fitsToday, isFalse);
      expect(c.monthLeftFils, 137000);
      expect(c.limitFromTomorrowFils, 4892); // 137.000 over 28 days
      expect(c.limitIfBoughtFils, 4250); // 119.000 over 28 days
      expect(c.daysOfLimit, 4);
      expect(c.beyondMonth, isFalse);
    });

    test('something small fits today', () async {
      final c = await check(500);
      expect(c.fitsToday, isTrue);
      expect(c.daysOfLimit, 1);
    });

    test('more than the month has left', () async {
      expect((await check(200000)).beyondMonth, isTrue);
    });

    test('last day of the month: no "from tomorrow"', () async {
      final c = await check(1000, today: const Day(2026, 11, 30));
      expect(c.limitFromTomorrowFils, isNull);
      expect(c.limitIfBoughtFils, isNull);
    });

    test('without a plan: only today and days of the limit', () async {
      final c = await check(18000, p: null);
      expect(c.monthLeftFils, isNull);
      expect(c.limitIfBoughtFils, isNull);
      expect(c.daysOfLimit, 4);
    });
  });
}
