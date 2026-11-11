import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/preferences_store.dart';
import 'package:beaza/data/repositories/rewards_repository.dart';
import 'package:beaza/data/repositories/savings_repository.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/domain/use_cases/rewards.dart';
import 'package:beaza/domain/use_cases/spending_by_category.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/features/savings/view_models/savings_view_model.dart';
import 'package:beaza/ui/features/savings/views/savings_view.dart';
import 'package:beaza/ui/features/savings/views/vouchers.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

int _n = 0;
ExtractionResult tx(int fils, DateTime at, {String? category}) => ExtractionResult(
      status: ExtractionStatus.transaction,
      amountFils: fils,
      currency: 'BHD',
      type: TxnType.purchase,
      direction: TxDirection.outgoing,
      category: category,
      reference: 'R${_n++}',
      timestamp: at,
    );

DateTime bh(int day, [int hour = 12]) =>
    DateTime.utc(2026, 11, day, hour).subtract(kBahrainOffset);

void main() {
  test('points: 10 per finished day within the limit, 20 per skipped purchase', () {
    final entries = const Reconciler().reconcile([
      tx(3000, bh(10)), // within
      tx(4000, bh(11)), // within
      tx(12000, bh(12)), // over
      tx(1000, bh(14)), // today: not finished, not counted
    ], OwnAccounts());
    final holds = [
      Hold(id: '1', name: 'a', amountFils: 1, createdAt: DateTime.utc(2026),
          decision: 'skipped', decidedAt: DateTime.utc(2026)),
      Hold(id: '2', name: 'b', amountFils: 1, createdAt: DateTime.utc(2026),
          decision: 'bought', decidedAt: DateTime.utc(2026)),
    ];
    const today = Day(2026, 11, 14);
    expect(pointsEarned(entries, const GuardrailSettings(dailyLimitFils: 10000), holds, today), 40);
    // No limit: only the skipped purchase counts.
    expect(pointsEarned(entries, const GuardrailSettings(dailyLimitFils: 0), holds, today), 20);
  });

  test('offers by spending put the biggest categories first, only when on', () {
    const week = [CategoryTotal('education', 9000, 3), CategoryTotal('food', 1000, 1)];
    expect(rankOffers(week, personal: false), kDemoOffers);
    final ranked = rankOffers(week, personal: true);
    expect(ranked.first.category, 'education');
    expect(ranked[1].category, 'food');
  });

  test('every demo offer is labelled with an invented partner and a DEMO code', () {
    for (final o in kDemoOffers) {
      expect(o.codeFor(1), startsWith('DEMO-'));
      expect(kCategories, contains(o.category));
    }
  });

  test('a coupon shows what it would have saved on the last 7 days', () {
    final entries = const Reconciler().reconcile([
      for (var d = 10; d <= 14; d++)
        ExtractionResult(
          status: ExtractionStatus.transaction, amountFils: 1500, currency: 'BHD',
          type: TxnType.purchase, direction: TxDirection.outgoing,
          merchantRaw: 'KARAK HOUSE', category: 'food', reference: 'K$d',
          timestamp: bh(d, 8)),
      tx(20000, bh(12), category: 'shopping'),
      tx(9000, bh(1), category: 'shopping'), // older than 7 days
    ], OwnAccounts());
    const today = Day(2026, 11, 14);
    final nakhla = kDemoOffers.firstWhere((o) => o.id == 'nakhla');
    final souq = kDemoOffers.firstWhere((o) => o.id == 'souq');
    expect(offerFit(nakhla, entries, today), (spentFils: 7500, count: 5, savingFils: 1500));
    expect(offerFit(souq, entries, today), (spentFils: 20000, count: 1, savingFils: 3000));
    // The coupon that would have saved most comes first.
    final ranked = rankOffers(const [], personal: true,
        savings: {for (final o in kDemoOffers) o.id: offerFit(o, entries, today).savingFils});
    expect(ranked.take(2).map((o) => o.id), ['souq', 'nakhla']);
    for (final o in kDemoOffers) {
      expect(o.cost, 0, reason: 'coupons are free');
    }
  });

  testWidgets('get a free coupon: no points taken, shown again, in My coupons',
      (tester) async {
    final now = DateTime.utc(2026, 11, 14, 9);
    final ledger = InMemoryLedgerRepository(initial: [
      for (var d = 1; d <= 13; d++) tx(2000, bh(d)),
    ]);
    final prefs = MemoryPreferencesStore();
    final vm = SavingsViewModel(
      repo: SavingsRepository(prefs, clock: () => now),
      ledger: ledger,
      rewards: RewardsRepository(prefs, clock: () => now),
      settings: InMemorySettingsRepository(
          const GuardrailSettings(dailyLimitFils: 10000)),
      clock: () => now,
    );
    await vm.load();
    expect(vm.pointsBalance, 130);

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: SavingsView(viewModel: vm),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('redeem_nakhla')), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Nakhla Cafe · demo'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('redeem_nakhla')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('redeem_nakhla')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('voucherDisclaimer')), findsOneWidget);
    expect(find.text('Valid 7 days'), findsOneWidget);
    expect(find.byKey(const Key('voucherQr')), findsOneWidget);
    final code = tester.widget<SelectableText>(find.byKey(const Key('redeemCode'))).data!;
    expect(code, startsWith('DEMO-NAKHLA-'));
    expect(vm.pointsBalance, 130, reason: 'coupons cost no points');

    // Tapping again shows the same coupon, not a second one.
    Navigator.of(tester.element(find.byKey(const Key('voucherSheet')))).pop();
    await tester.pumpAndSettle();
    expect(find.text('Show coupon'), findsOneWidget);
    await tester.tap(find.byKey(const Key('redeem_nakhla')));
    await tester.pumpAndSettle();
    expect(tester.widget<SelectableText>(find.byKey(const Key('redeemCode'))).data, code);
    Navigator.of(tester.element(find.byKey(const Key('voucherSheet')))).pop();
    await tester.pumpAndSettle();
    expect(vm.vouchers, hasLength(1));

    // My coupons lists it; it opens again with its code.
    await tester.ensureVisible(find.byKey(const Key('openWallet')));
    await tester.pumpAndSettle();
    expect(find.text('My coupons (1)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('openWallet')));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('voucher_$code')), findsOneWidget);
    await tester.tap(find.byKey(Key('voucher_$code')));
    await tester.pumpAndSettle();
    expect(find.text(code), findsOneWidget);
  });

  test('a voucher lasts 7 days; the QR stand-in is fixed for a code', () {
    final at = DateTime.utc(2026, 11, 1, 10);
    final r = Redemption('nakhla', 'DEMO-NAKHLA-1234', 50, at);
    expect(r.daysLeft(at), 7);
    expect(r.daysLeft(at.add(const Duration(days: 6, hours: 1))), 1);
    expect(r.activeAt(at.add(const Duration(days: 7))), isFalse);
    expect(r.daysLeft(at.add(const Duration(days: 8))), 0);
    expect(DemoQrPainter.pattern('DEMO-A'), DemoQrPainter.pattern('DEMO-A'));
    expect(DemoQrPainter.pattern('DEMO-A'), isNot(DemoQrPainter.pattern('DEMO-B')));
  });
}
