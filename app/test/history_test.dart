import 'package:beaza/app.dart';
import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/ui/features/history/view_models/history_view_model.dart';
import 'package:beaza/ui/features/home/view_models/home_view_model.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime bh(int day, int hour, [int minute = 0]) =>
    DateTime.utc(2026, 11, day, hour, minute).subtract(kBahrainOffset);

ExtractionResult spend(int fils, DateTime at,
        {String? shop, String? category, String? ref}) =>
    ExtractionResult(
      status: ExtractionStatus.transaction,
      amountFils: fils,
      currency: 'BHD',
      type: TxnType.purchase,
      direction: TxDirection.outgoing,
      merchantRaw: shop,
      merchantNorm: shop,
      category: category,
      reference: ref,
      timestamp: at,
    );

ExtractionResult received(int fils, DateTime at) => ExtractionResult(
      status: ExtractionStatus.transaction,
      amountFils: fils,
      currency: 'BHD',
      type: TxnType.transferIn,
      channel: Channel.transfer,
      direction: TxDirection.incoming,
      reference: 'in1',
      timestamp: at,
    );

void main() {
  test('days are newest first, with their counted spending', () async {
    final ledger = InMemoryLedgerRepository(initial: [
      spend(3900, bh(1, 14), shop: 'Abed Bakery', category: 'food'),
      spend(1000, bh(1, 9), shop: 'Redtag', category: 'shopping'),
      spend(5000, bh(3, 21), shop: 'Day To Day', category: 'groceries'),
      received(9000, bh(2, 12)),
    ]);
    final vm = HistoryViewModel(ledger: ledger);
    await vm.load();
    expect(vm.days.map((d) => d.day.toString()),
        ['2026-11-03', '2026-11-02', '2026-11-01']);
    expect(vm.days.map((d) => d.spentFils), [5000, 0, 4900]);
    // Newest first inside a day.
    expect(vm.days.last.entries.map((e) => e.result.amountFils), [3900, 1000]);
    // Income is listed but not counted as spending.
    expect(vm.days[1].entries.single.role, EntryRole.income);
  });

  test('a change in the ledger refreshes the history', () async {
    final ledger = InMemoryLedgerRepository();
    final vm = HistoryViewModel(ledger: ledger);
    await vm.load();
    expect(vm.days, isEmpty);
    await ledger.addManual(amountFils: 2500, at: bh(2, 9));
    await Future<void>.delayed(Duration.zero);
    expect(vm.days, hasLength(1));
  });

  testWidgets('history screen: open from home, pick a category for a shop',
      (tester) async {
    final ledger = InMemoryLedgerRepository(initial: [
      spend(2050, bh(1, 16), shop: 'Waleed Al Kabah', ref: 'a'),
      spend(3000, bh(2, 9), shop: 'Waleed Al Kabah', ref: 'b'),
    ]);
    final vm = HomeViewModel(
      ledger: ledger,
      settings: InMemorySettingsRepository(
          const GuardrailSettings(dailyLimitFils: 10000)),
      clock: () => bh(2, 12),
    );
    await vm.load();
    await tester.pumpWidget(BeazaApp(homeViewModel: vm, locale: const Locale('en')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('historyButton')));
    await tester.pumpAndSettle();
    expect(find.text('History'), findsWidgets);
    expect(find.byKey(const Key('day_2026-11-02')), findsOneWidget);
    expect(find.byKey(const Key('day_2026-11-01')), findsOneWidget);
    expect(find.text('Spent BHD 2.050'), findsOneWidget);

    // Tap the older purchase, then "Change category": the list says it
    // applies to the whole shop.
    await tester.tap(find.text('Waleed Al Kabah').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('entryCategory')));
    await tester.pumpAndSettle();
    expect(find.text('Applies to every purchase from Waleed Al Kabah'),
        findsOneWidget);
    await tester.scrollUntilVisible(
        find.byKey(const Key('pick_health')), 100,
        scrollable: find.descendant(
            of: find.byType(BottomSheet), matching: find.byType(Scrollable)));
    await tester.tap(find.byKey(const Key('pick_health')));
    await tester.pumpAndSettle();

    final cats = (await ledger.entries()).map((e) => e.result.category);
    expect(cats, ['health', 'health']);
  });

  test('the unsorted filter shows only purchases without a category',
      () async {
    final ledger = InMemoryLedgerRepository(initial: [
      spend(3900, bh(1, 14), shop: 'Abed Bakery', category: 'food'),
      spend(1000, bh(1, 9), shop: 'ZZ UNKNOWN 123'),
      received(9000, bh(2, 12)),
    ]);
    final vm = HistoryViewModel(ledger: ledger, unsortedOnly: true);
    await vm.load();
    expect(vm.unsortedCount, 1);
    expect(vm.days.single.entries.single.result.amountFils, 1000);
    await vm.setCategory(vm.days.single.entries.single, 'shopping');
    await Future<void>.delayed(Duration.zero);
    await vm.load();
    expect(vm.unsortedCount, 0);
    expect(vm.days, isEmpty);
    await vm.showUnsortedOnly(false);
    expect(vm.days.expand((d) => d.entries), hasLength(3));
  });

  testWidgets('a transaction can be edited and deleted from the history',
      (tester) async {
    final ledger = InMemoryLedgerRepository(initial: [
      spend(2050, bh(2, 9), shop: 'Waleed Al Kabah', ref: 'a'),
      spend(3000, bh(2, 10), shop: 'Jasmis', ref: 'b'),
    ]);
    final vm = HomeViewModel(
      ledger: ledger,
      settings: InMemorySettingsRepository(
          const GuardrailSettings(dailyLimitFils: 10000)),
      clock: () => bh(2, 12),
    );
    await vm.load();
    await tester.pumpWidget(BeazaApp(homeViewModel: vm, locale: const Locale('en')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('historyButton')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Jasmis'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('entryEdit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('amountField')), '2.500');
    await tester.enterText(find.byKey(const Key('merchantField')), 'Jasmis Riffa');
    await tester.tap(find.byKey(const Key('saveAmount')));
    await tester.pumpAndSettle();
    expect(find.text('Jasmis Riffa'), findsOneWidget);
    expect((await ledger.entries()).map((e) => e.result.amountFils),
        [2050, 2500]);

    await tester.tap(find.text('Waleed Al Kabah'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('entryDelete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmDelete')));
    await tester.pumpAndSettle();
    expect(find.text('Waleed Al Kabah'), findsNothing);
    expect((await ledger.entries()).single.result.merchantRaw, 'Jasmis Riffa');
  });
}
