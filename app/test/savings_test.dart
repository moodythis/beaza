import 'package:beaza/app.dart';
import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/preferences_store.dart';
import 'package:beaza/data/repositories/savings_repository.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/domain/use_cases/subscriptions.dart';
import 'package:beaza/ui/features/home/view_models/home_view_model.dart';
import 'package:beaza/ui/features/savings/view_models/savings_view_model.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

int _n = 0;
ExtractionResult tx(int fils, DateTime at, String shop) => ExtractionResult(
      status: ExtractionStatus.transaction,
      amountFils: fils,
      currency: 'BHD',
      type: TxnType.purchase,
      direction: TxDirection.outgoing,
      merchantNorm: shop,
      reference: 'R${_n++}',
      timestamp: at,
    );

List<LedgerEntry> ledger(List<ExtractionResult> rs) =>
    const Reconciler().reconcile(rs, OwnAccounts());

DateTime d(int month, int day) => DateTime.utc(2026, month, day, 9);

void main() {
  group('findSubscriptions', () {
    test('monthly and weekly repeats; largest monthly cost first', () {
      final subs = findSubscriptions(ledger([
        tx(3500, d(8, 5), 'Sample Stream'),
        tx(3500, d(9, 4), 'Sample Stream'),
        tx(3500, d(10, 5), 'Sample Stream'),
        tx(1000, d(10, 20), 'Sample Club'),
        tx(1000, d(10, 27), 'Sample Club'),
      ]));
      expect(subs.map((s) => '${s.name}:${s.times}:${s.weekly}:${s.monthlyFils}'),
          ['Sample Club:2:true:4333', 'Sample Stream:3:false:3500']);
      // Gaps of 30 and 31 days: the next one is expected 30.5 days later.
      expect(subs.last.next, d(10, 5).add(const Duration(hours: 732)));
    });

    test('not repeating: other gaps, or a different amount', () {
      expect(
          findSubscriptions(ledger([
            tx(3500, d(10, 1), 'Cafe'),
            tx(3500, d(10, 11), 'Cafe'),
            tx(2000, d(9, 1), 'Shop'),
            tx(3000, d(10, 1), 'Shop'),
          ])),
          isEmpty);
    });

    test('a known subscription service counts after one charge', () {
      final subs = findSubscriptions(ledger([tx(4000, d(10, 3), 'Netflix')]));
      expect(subs.single.knownByName, isTrue);
      expect(subs.single.times, 1);
    });
  });

  group('cooling-off and goal', () {
    late DateTime now;
    late SavingsRepository repo;
    setUp(() {
      now = DateTime.utc(2026, 11, 4, 9);
      repo = SavingsRepository(MemoryPreferencesStore(), clock: () => now);
    });

    test('a hold can only be decided after 24 hours', () async {
      final h = await repo.addHold('Headphones', 25000);
      await repo.decide(h.id, 'skipped');
      expect((await repo.holds()).single.decision, isNull);

      now = now.add(const Duration(hours: 23));
      expect((await repo.holds()).single.leftAt(now), const Duration(hours: 1));

      now = now.add(const Duration(hours: 1));
      await repo.decide(h.id, 'skipped');
      final after = (await repo.holds()).single;
      expect(after.decision, 'skipped');
      expect(skippedFils(await repo.holds()), 25000);
    });

    test('the goal counts money put aside and purchases skipped after it was set',
        () async {
      final early = await repo.addHold('Old', 1000);
      now = now.add(const Duration(days: 1));
      await repo.decide(early.id, 'skipped'); // before the goal
      now = now.add(const Duration(minutes: 1));
      await repo.setGoal('iPad', 200000);
      await repo.addToGoal(5000);
      final h = await repo.addHold('Shoes', 30000);
      now = now.add(const Duration(days: 1));
      await repo.decide(h.id, 'skipped');
      final bought = await repo.addHold('Book', 4000);
      now = now.add(const Duration(days: 1));
      await repo.decide(bought.id, 'bought');

      final goal = (await repo.goal())!;
      expect(goal.name, 'iPad');
      expect(goalSavedFils(goal, await repo.holds()), 35000);
      await repo.clearGoal();
      expect(await repo.goal(), isNull);
    });

    test('bad amounts are refused', () async {
      expect(() => repo.addHold('x', 0), throwsArgumentError);
      expect(() => repo.setGoal('x', -1), throwsArgumentError);
    });
  });

  testWidgets('from the home card: set a goal and put something on hold',
      (tester) async {
    final now = DateTime.utc(2026, 11, 4, 9);
    final ledgerRepo = InMemoryLedgerRepository(initial: [
      tx(3500, d(9, 4), 'Sample Stream'),
      tx(3500, d(10, 5), 'Sample Stream'),
    ]);
    final savings = SavingsViewModel(
      repo: SavingsRepository(MemoryPreferencesStore(), clock: () => now),
      ledger: ledgerRepo,
      clock: () => now,
    );
    await savings.load();
    final home = HomeViewModel(
      ledger: ledgerRepo,
      settings: InMemorySettingsRepository(
          const GuardrailSettings(dailyLimitFils: 10000)),
      savings: savings,
      clock: () => now,
    );
    await home.load();
    await tester.pumpWidget(BeazaApp(homeViewModel: home));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('savingsCard')), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Subscriptions BHD 3.500 a month'), findsOneWidget);
    await tester.tap(find.byKey(const Key('savingsCard')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('goalSet')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('nameField')), 'Laptop');
    await tester.enterText(find.byKey(const Key('amountField')), '300');
    await tester.tap(find.byKey(const Key('dialogSave')));
    await tester.pumpAndSettle();
    expect(find.text('Laptop'), findsOneWidget);
    expect(find.text('BHD 0.000 of BHD 300.000'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('holdAdd')));
    await tester.tap(find.byKey(const Key('holdAdd')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('nameField')), 'Sneakers');
    await tester.enterText(find.byKey(const Key('amountField')), '45');
    await tester.tap(find.byKey(const Key('dialogSave')));
    await tester.pumpAndSettle();
    expect(find.text('Sneakers'), findsOneWidget);
    expect(find.text('24 h left'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('subsCard')), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Sample Stream'), findsOneWidget);
  });
}
