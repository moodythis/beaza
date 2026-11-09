import 'package:beaza/app.dart';
import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/preferences_store.dart';
import 'package:beaza/data/repositories/seen_message_store.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/domain/use_cases/message_intake.dart';
import 'package:beaza/ui/core/language_controller.dart';
import 'package:beaza/ui/features/home/view_models/home_view_model.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'message_intake_test.dart' as fixtures;

/// A Bahrain local time on 2 Nov 2026, as the stored UTC instant.
DateTime bh(int hour, [int minute = 0]) =>
    DateTime.utc(2026, 11, 2, hour, minute).subtract(kBahrainOffset);

ExtractionResult purchase(int fils, DateTime at,
        {String? merchant, String? category}) =>
    ExtractionResult(
      status: ExtractionStatus.transaction,
      amountFils: fils,
      currency: 'BHD',
      type: TxnType.purchase,
      direction: TxDirection.outgoing,
      merchantRaw: merchant,
      category: category,
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
  // A tall screen, so the whole home list is built and can be found.
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(BeazaApp(homeViewModel: vm, locale: locale));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the week card shows where the money went', (tester) async {
    await pumpHome(tester, results: [
      purchase(3900, bh(9), merchant: 'BAKERY', category: 'food'),
      purchase(13200, bh(10), merchant: 'SHOP', category: 'shopping'),
    ]);
    expect(find.text('Where did my money go?'), findsOneWidget);
    expect(find.text('Last 7 days · BHD 17.100'), findsOneWidget);
    expect(find.byKey(const Key('cat_shopping')), findsOneWidget);
    expect(find.byKey(const Key('cat_food')), findsOneWidget);
    expect(find.text('77%'), findsOneWidget);
    expect(find.text('23%'), findsOneWidget);
  });

  testWidgets('saving tips appear from the last 7 days, in English', (tester) async {
    await pumpHome(tester, results: [
      purchase(3900, bh(9), merchant: 'BAKERY', category: 'food'),
      purchase(13200, bh(10), merchant: 'SHOP', category: 'shopping'),
    ]);
    await tester.tap(find.byKey(const Key('tabInsights')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('tipsCard')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Saving tips'), findsOneWidget);
    expect(find.text("Shopping is 77% of this week's spending (BHD 13.200)"),
        findsOneWidget);
    expect(find.byKey(const Key('tip_0')), findsOneWidget);
  });

  testWidgets('saving tips are in Arabic too, and absent with little spending',
      (tester) async {
    await pumpHome(tester, locale: const Locale('ar'), results: [
      purchase(13200, bh(10), merchant: 'SHOP', category: 'shopping'),
    ]);
    await tester.tap(find.byKey(const Key('tabInsights')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('tipsCard')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('نصائح للتوفير'), findsOneWidget);
  });

  testWidgets('from 50% of the limit a short tip shows on its own', (tester) async {
    await pumpHome(tester, results: [
      purchase(6000, bh(10), merchant: 'SHOP', category: 'bills'),
    ]);
    await tester.tap(find.byKey(const Key('tabInsights')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('tipsCard')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('tip_level')), findsOneWidget);
    expect(find.text("Tip: think twice before anything you don't need today."),
        findsOneWidget);
  });

  testWidgets('no tips card when almost nothing was spent', (tester) async {
    await pumpHome(tester, results: [
      purchase(1500, bh(10), merchant: 'BAKERY', category: 'food'),
    ]);
    expect(find.byKey(const Key('tipsCard')), findsNothing);
  });

  testWidgets('tapping a transaction changes its category', (tester) async {
    await pumpHome(tester, results: [
      purchase(3900, bh(9), merchant: 'MYSTERY SHOP'),
    ]);
    expect(find.byKey(const Key('cat_unsorted')), findsOneWidget);
    await tester.ensureVisible(find.text('MYSTERY SHOP'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MYSTERY SHOP'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a category'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.byKey(const Key('pick_health')), 100,
        scrollable: find.descendant(
            of: find.byType(BottomSheet), matching: find.byType(Scrollable)));
    await tester.tap(find.byKey(const Key('pick_health')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cat_health')), findsOneWidget);
    expect(find.byKey(const Key('cat_unsorted')), findsNothing);
  });

  testWidgets('the week card is in Arabic too', (tester) async {
    await pumpHome(tester,
        locale: const Locale('ar'),
        results: [purchase(3900, bh(9), category: 'food')]);
    expect(find.text('أين ذهبت أموالي؟'), findsOneWidget);
    expect(find.text('أكل ومشروبات'), findsWidgets);
  });

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
    expect(find.text('خصم من حسابك'), findsOneWidget);
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

  testWidgets('SMS card asks for permission, then bank messages appear',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final sms = fixtures.FakeSms([('1', 'BisB', bh(16, 32), fixtures.bisbCard)])
      ..granted = false;
    final ledger = InMemoryLedgerRepository();
    final vm = HomeViewModel(
      ledger: ledger,
      settings: InMemorySettingsRepository(
          const GuardrailSettings(dailyLimitFils: 10000)),
      intake: MessageIntake(
        sms: sms,
        ledger: ledger,
        seen: MemorySeenMessageStore(),
        clock: () => bh(20),
      ),
      clock: () => bh(20),
    );
    await vm.load();
    await vm.checkMessages();
    await tester.pumpWidget(BeazaApp(homeViewModel: vm, locale: const Locale('en')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('smsCard')), findsOneWidget);
    expect(find.text('BHD 10.000'), findsOneWidget);

    sms.granted = true;
    await tester.tap(find.byKey(const Key('smsAllow')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('smsCard')), findsNothing);
    expect(find.text('Sample Bakery - Mal Bah'), findsOneWidget);
    expect(find.text('BHD 9.700'), findsOneWidget);
  });

  testWidgets('turning messages on starts from now; earlier ones only if asked',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final sms = fixtures.FakeSms([('1', 'BisB', bh(16, 32), fixtures.bisbCard)])
      ..granted = false;
    final ledger = InMemoryLedgerRepository();
    final vm = HomeViewModel(
      ledger: ledger,
      settings: InMemorySettingsRepository(
          const GuardrailSettings(dailyLimitFils: 10000)),
      intake: MessageIntake(
        sms: sms,
        ledger: ledger,
        seen: MemorySeenMessageStore(),
        preferences: MemoryPreferencesStore(),
        clock: () => bh(20),
      ),
      clock: () => bh(20),
    );
    await vm.load();
    await vm.checkMessages();
    await tester.pumpWidget(BeazaApp(homeViewModel: vm, locale: const Locale('en')));
    await tester.pumpAndSettle();

    sms.granted = true;
    await tester.tap(find.byKey(const Key('smsAllow')));
    await tester.pumpAndSettle();
    // The 16:32 message is from before: not added, and the question shows.
    expect(find.text('Sample Bakery - Mal Bah'), findsNothing);
    expect(find.byKey(const Key('earlierCard')), findsOneWidget);

    await tester.tap(find.byKey(const Key('earlier7')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Found 1 purchases'), findsOneWidget);
    expect(await ledger.entries(), isEmpty); // the preview stores nothing
    await tester.tap(find.byKey(const Key('earlierAdd')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('earlierCard')), findsNothing);
    expect(find.text('Sample Bakery - Mal Bah'), findsOneWidget);
  });

  testWidgets('"Can I buy it?" shows what it does and saves nothing',
      (tester) async {
    await pumpHome(tester, limit: 10000, results: [
      purchase(4000, bh(9), merchant: 'CAFE', category: 'food'),
    ]);
    await tester.tap(find.byKey(const Key('canIBuy')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('amountField')), '3');
    await tester.tap(find.byKey(const Key('saveAmount')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('buyResult')), findsOneWidget);
    expect(find.textContaining("It fits in what is left of today's limit (BHD 6.000)"),
        findsOneWidget);
    expect(find.textContaining('Work out your limit from your income'),
        findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('BHD 6.000'), findsOneWidget); // remaining unchanged
  });

  testWidgets('no SMS card when there is no SMS support', (tester) async {
    await pumpHome(tester);
    expect(find.byKey(const Key('smsCard')), findsNothing);
  });

  testWidgets('the not-understood line opens the review screen',
      (tester) async {
    final sms = fixtures.FakeSms(
        [('7', 'BisB', bh(10), fixtures.unknownFormat)]);
    final ledger = InMemoryLedgerRepository();
    final vm = HomeViewModel(
      ledger: ledger,
      settings: InMemorySettingsRepository(
          const GuardrailSettings(dailyLimitFils: 10000)),
      intake: MessageIntake(
        sms: sms,
        ledger: ledger,
        seen: MemorySeenMessageStore(),
        clock: () => bh(20),
      ),
      clock: () => bh(20),
    );
    await vm.load();
    await vm.checkMessages();
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(BeazaApp(homeViewModel: vm, locale: const Locale('en')));
    await tester.pumpAndSettle();

    expect(find.text('1 bank message could not be read'), findsOneWidget);
    await tester.tap(find.byKey(const Key('notUnderstood')));
    await tester.pumpAndSettle();

    expect(find.text('Messages not understood'), findsOneWidget);
    expect(find.text(fixtures.unknownFormat), findsOneWidget);
  });

  testWidgets('the language button switches and remembers the choice',
      (tester) async {
    final prefs = MemoryPreferencesStore();
    final language = LanguageController(prefs);
    await language.load();
    final vm = HomeViewModel(
      ledger: InMemoryLedgerRepository(),
      settings: InMemorySettingsRepository(
          const GuardrailSettings(dailyLimitFils: 10000)),
      clock: () => bh(12),
    );
    await vm.load();
    // The test device is English.
    await tester.pumpWidget(BeazaApp(homeViewModel: vm, language: language));
    await tester.pumpAndSettle();
    expect(find.text('Left to spend today'), findsOneWidget);
    expect(find.text('عربي'), findsOneWidget);

    await tester.tap(find.byKey(const Key('languageButton')));
    await tester.pumpAndSettle();
    expect(find.text('المتبقي للصرف اليوم'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(prefs.values['language'], 'ar');

    // A new start reads the saved choice.
    final again = LanguageController(prefs);
    await again.load();
    expect(again.code, 'ar');
  });

  test('effective language: choice, then English phone, otherwise Arabic', () {
    expect(effectiveLanguage('ar', const Locale('en')), 'ar');
    expect(effectiveLanguage(null, const Locale('en', 'US')), 'en');
    expect(effectiveLanguage(null, const Locale('fr')), 'ar');
  });
}
