import 'package:beaza/app.dart';
import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/ui/features/ask/view_models/ask_view_model.dart';
import 'package:beaza/ui/features/home/view_models/home_view_model.dart';
import 'package:beaza_assistant/beaza_assistant.dart' show AssistantIntent;
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime bh(int day, [int hour = 12]) =>
    DateTime.utc(2026, 11, day, hour).subtract(kBahrainOffset);

ExtractionResult purchase(int fils, DateTime at, {String? category}) =>
    ExtractionResult(
      status: ExtractionStatus.transaction,
      amountFils: fils,
      currency: 'BHD',
      type: TxnType.purchase,
      direction: TxDirection.outgoing,
      category: category,
      timestamp: at,
    );

void main() {
  test('answers from the list on the phone, and adds cash said in words',
      () async {
    final ledger = InMemoryLedgerRepository(initial: [
      purchase(3900, bh(14, 9), category: 'food'),
      purchase(13200, bh(12), category: 'shopping'),
    ]);
    final vm = AskViewModel(
      ledger: ledger,
      settings: InMemorySettingsRepository(
          const GuardrailSettings(dailyLimitFils: 10000)),
      addDrafts: (drafts) async {
        for (final d in drafts) {
          await ledger.addManual(
              amountFils: d.amountFils, merchant: d.merchantRaw, at: d.timestamp);
        }
      },
      clock: () => bh(14, 15),
    );
    await vm.ask('كم صرفت هالأسبوع؟');
    expect(vm.turns.single.answer.replyText, contains('17.100'));

    await vm.ask('شريت كرك بربيتين');
    final log = vm.turns.last;
    expect(log.answer.intent, AssistantIntent.logExpense);
    await vm.add(log);
    expect(log.added, isTrue);
    expect((await ledger.entries()).map((e) => e.result.amountFils),
        contains(200));
    await vm.add(log); // not twice
    expect((await ledger.entries()).where((e) => e.result.amountFils == 200),
        hasLength(1));
    vm.dispose();
  });

  testWidgets('the questions screen opens from home and answers an example',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final vm = HomeViewModel(
      ledger: InMemoryLedgerRepository(
          initial: [purchase(3900, bh(14, 9), category: 'food')]),
      settings: InMemorySettingsRepository(
          const GuardrailSettings(dailyLimitFils: 10000)),
      clock: () => bh(14, 15),
    );
    await vm.load();
    await tester.pumpWidget(BeazaApp(homeViewModel: vm, locale: const Locale('en')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('tabInsights')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askButton')));
    await tester.pumpAndSettle();
    expect(find.text('Ask about your spending'), findsOneWidget);
    await tester.tap(find.byKey(const Key('askExample2'))); // what is left today
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askAnswer')), findsOneWidget);
    expect(find.textContaining('6.100'), findsOneWidget);
  });
}
