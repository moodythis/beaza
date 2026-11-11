// Small-screen audit: a 360x640 phone with text at 120%, in Arabic (right
// to left) and English. Opens every tab and the add-expense, quick-add and
// transaction sheets, and scrolls each screen to the end so every card is
// laid out. Any overflow ("A RenderFlex overflowed") fails the test.
import 'package:beaza/app.dart';
import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/preferences_store.dart';
import 'package:beaza/data/repositories/rewards_repository.dart';
import 'package:beaza/data/repositories/savings_repository.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/ui/features/home/view_models/home_view_model.dart';
import 'package:beaza/ui/features/savings/view_models/savings_view_model.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 20:30 Bahrain time on 10 November 2026 (the daily close is offered).
final DateTime now = DateTime.utc(2026, 11, 10, 17, 30);

int _n = 0;
ExtractionResult tx(int fils, DateTime at, String shop, String category) =>
    ExtractionResult(
      status: ExtractionStatus.transaction,
      amountFils: fils,
      currency: 'BHD',
      type: TxnType.purchase,
      direction: TxDirection.outgoing,
      merchantRaw: shop,
      merchantNorm: shop,
      category: category,
      reference: 'L${_n++}',
      timestamp: at,
    );

/// Three weeks of ordinary spending, with long shop names on purpose.
List<ExtractionResult> data() => [
      for (var d = 0; d < 21; d++) ...[
        tx(1250, now.subtract(Duration(days: d, hours: 10)),
            'Starbucks Seef Mall Branch', 'food'),
        tx(8900 + d * 13, now.subtract(Duration(days: d, hours: 4)),
            'Lulu Hypermarket Juffair', 'groceries'),
        if (d.isEven)
          tx(650, now.subtract(Duration(days: d, hours: 1)),
              'Talabat', 'food'),
      ],
    ];

/// Scrolls the main vertical list to its end, a screen at a time.
Future<void> scrollToEnd(WidgetTester tester) async {
  final list = find.byWidgetPredicate((w) =>
      w is Scrollable && axisDirectionToAxis(w.axisDirection) == Axis.vertical);
  if (list.evaluate().isEmpty) return;
  for (var i = 0; i < 20; i++) {
    await tester.drag(list.first, const Offset(0, -500), warnIfMissed: false);
    await tester.pumpAndSettle();
  }
}

Future<void> closeSheet(WidgetTester tester) async {
  await tester.tapAt(const Offset(180, 20));
  await tester.pumpAndSettle();
  final nav = tester.state<NavigatorState>(find.byType(Navigator).last);
  if (nav.canPop()) {
    nav.pop();
    await tester.pumpAndSettle();
  }
}

void main() {
  for (final lang in ['ar', 'en']) {
    testWidgets('360x640, text at 120%, $lang: every tab and sheet fits',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640) * 3;
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = 1.2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final prefs = MemoryPreferencesStore();
      final ledger = InMemoryLedgerRepository(initial: data());
      final settings = InMemorySettingsRepository(
          const GuardrailSettings(dailyLimitFils: 12000));
      final savings = SavingsViewModel(
        repo: SavingsRepository(prefs, clock: () => now),
        ledger: ledger,
        rewards: RewardsRepository(prefs, clock: () => now),
        settings: settings,
        clock: () => now,
      );
      final home = HomeViewModel(
        ledger: ledger,
        settings: settings,
        savings: savings,
        preferences: prefs,
        clock: () => now,
      );
      await savings.load();
      await home.load();

      await tester.pumpWidget(BeazaApp(homeViewModel: home, locale: Locale(lang)));
      await tester.pumpAndSettle();

      // Today, scrolled to the end.
      await scrollToEnd(tester);

      // The add-expense dialog and the quick-add sheet.
      await tester.drag(
          find.byWidgetPredicate((w) =>
              w is Scrollable &&
              axisDirectionToAxis(w.axisDirection) == Axis.vertical).first,
          const Offset(0, 5000),
          warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('addExpense')));
      await tester.pumpAndSettle();
      await closeSheet(tester);
      await tester.tap(find.byKey(const Key('quickAdd')));
      await tester.pumpAndSettle();
      await closeSheet(tester);

      // History, and the sheet for one transaction.
      await tester.tap(find.byKey(const Key('historyButton')));
      await tester.pumpAndSettle();
      final row = find.byType(ListTile);
      if (row.evaluate().isNotEmpty) {
        await tester.tap(row.first, warnIfMissed: false);
        await tester.pumpAndSettle();
        await closeSheet(tester);
      }
      await scrollToEnd(tester);

      // Insights and Saving.
      await tester.tap(find.byKey(const Key('tabInsights')));
      await tester.pumpAndSettle();
      await scrollToEnd(tester);
      await tester.tap(find.byKey(const Key('tabSavings')));
      await tester.pumpAndSettle();
      await scrollToEnd(tester);

      expect(tester.takeException(), isNull);
    });
  }
}
