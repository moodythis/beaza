import 'package:beaza/app.dart';
import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/ui/features/home/view_models/home_view_model.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A Bahrain local time on 2 Nov 2026, as the stored UTC instant.
DateTime bh(int hour, [int minute = 0]) =>
    DateTime.utc(2026, 11, 2, hour, minute).subtract(kBahrainOffset);

ExtractionResult purchase(int fils, DateTime at, {String? merchant}) =>
    ExtractionResult(
      status: ExtractionStatus.transaction,
      amountFils: fils,
      currency: 'BHD',
      type: TxnType.purchase,
      direction: TxDirection.outgoing,
      merchantRaw: merchant,
      timestamp: at,
    );

Future<void> pumpHome(
  WidgetTester tester, {
  int limit = 10000,
  List<ExtractionResult> results = const [],
  Locale locale = const Locale('en'),
}) async {
  final vm = HomeViewModel(
    ledger: InMemoryLedgerRepository(initial: results),
    settings: InMemorySettingsRepository(GuardrailSettings(dailyLimitFils: limit)),
    clock: () => bh(12),
  );
  await vm.load();
  await tester.pumpWidget(BeazaApp(homeViewModel: vm, locale: locale));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('remaining amount, bar text and level 1 in English',
      (tester) async {
    await pumpHome(tester, results: [purchase(6000, bh(9), merchant: 'CAFE')]);

    expect(find.text('Left to spend today'), findsOneWidget);
    expect(find.text('BHD 4.000'), findsOneWidget);
    expect(find.text('BHD 6.000 spent of BHD 10.000'), findsOneWidget);
    expect(find.text("Half of today's limit used"), findsOneWidget);
    expect(find.text('No small expenses today'), findsOneWidget);
    expect(find.text('CAFE'), findsOneWidget);
    expect(find.text('09:00'), findsOneWidget);
  });

  testWidgets('Arabic is right to left with Arabic labels', (tester) async {
    await pumpHome(tester,
        results: [purchase(6000, bh(9))], locale: const Locale('ar'));

    expect(Directionality.of(tester.element(find.byType(ListView))),
        TextDirection.rtl);
    expect(find.text('المتبقي للصرف اليوم'), findsOneWidget);
    expect(find.text('4.000 د.ب'), findsOneWidget);
    expect(find.text('استخدمت نصف حد اليوم'), findsOneWidget);
    expect(find.text('مصروف'), findsOneWidget);
  });

  testWidgets('over the limit shows the overrun', (tester) async {
    await pumpHome(tester, results: [purchase(12500, bh(9))]);

    expect(find.text("Over today's limit by"), findsOneWidget);
    expect(find.text('BHD 2.500'), findsOneWidget);
    expect(find.text("Today's limit reached"), findsOneWidget);
  });

  testWidgets('no limit set asks for one', (tester) async {
    await pumpHome(tester, limit: 0, results: [purchase(3500, bh(9))]);

    expect(find.byKey(const Key('setLimit')), findsOneWidget);
    expect(find.text('Set a daily spending limit'), findsOneWidget);
    expect(find.text('Spent today: BHD 3.500'), findsOneWidget);
  });

  testWidgets('empty day', (tester) async {
    await pumpHome(tester);

    expect(find.text('Nothing spent today'), findsOneWidget);
    expect(find.text('BHD 10.000'), findsOneWidget);
    expect(find.text('On track'), findsOneWidget);
  });

  testWidgets('adding an expense updates the screen', (tester) async {
    await pumpHome(tester);

    await tester.tap(find.byKey(const Key('addExpense')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('amountField')), '2.5');
    await tester.enterText(find.byKey(const Key('merchantField')), 'Bakery');
    await tester.tap(find.byKey(const Key('saveAmount')));
    await tester.pumpAndSettle();

    expect(find.text('Bakery'), findsOneWidget);
    expect(find.text('BHD 7.500'), findsOneWidget);
    expect(find.text('1 small expense today · BHD 2.500'), findsOneWidget);
  });

  testWidgets('an invalid amount keeps the dialog open', (tester) async {
    await pumpHome(tester);

    await tester.tap(find.byKey(const Key('addExpense')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('amountField')), '1.2345');
    await tester.tap(find.byKey(const Key('saveAmount')));
    await tester.pumpAndSettle();

    expect(find.text('Enter an amount like 1.250'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('editing the limit recomputes what is left', (tester) async {
    await pumpHome(tester, results: [purchase(6000, bh(9))]);

    await tester.tap(find.byKey(const Key('editLimit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('amountField')), '20');
    await tester.tap(find.byKey(const Key('saveAmount')));
    await tester.pumpAndSettle();

    expect(find.text('BHD 14.000'), findsOneWidget);
    expect(find.text('On track'), findsOneWidget);
  });
}
