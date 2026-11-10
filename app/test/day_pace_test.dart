import 'package:beaza/app.dart';
import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/domain/use_cases/day_pace.dart';
import 'package:beaza/ui/core/formatting.dart';
import 'package:beaza/ui/features/home/view_models/home_view_model.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

int _n = 0;
ExtractionResult tx(int fils, DateTime at, [String shop = 'Cafe']) =>
    ExtractionResult(
      status: ExtractionStatus.transaction,
      amountFils: fils,
      currency: 'BHD',
      type: TxnType.purchase,
      direction: TxDirection.outgoing,
      merchantNorm: shop,
      reference: 'P${_n++}',
      timestamp: at,
    );

List<LedgerEntry> ledger(List<ExtractionResult> rs) =>
    const Reconciler().reconcile(rs, OwnAccounts());

/// [hour]:[minute] Bahrain time on 4 November 2026 minus [daysBack].
DateTime bh(int hour, {int minute = 0, int daysBack = 0}) =>
    DateTime.utc(2026, 11, 4, hour - 3, minute).subtract(Duration(days: daysBack));

/// [days] past days: 2.000 at 09:00 and 3.000 at [evening]:00.
List<ExtractionResult> history(int days, {int evening = 20}) => [
      for (var d = 1; d <= days; d++) ...[
        tx(2000, bh(9, daysBack: d)),
        tx(3000, bh(evening, daysBack: d), 'Restaurant'),
      ],
    ];

void main() {
  group('dayPace', () {
    test('learns the usual day hour by hour and projects the rest of today', () {
      final p = dayPace(ledger([...history(7), tx(2000, bh(9, minute: 30))]),
          bh(12), limitFils: 4000)!;
      expect(p.historyDays, 7);
      expect(p.usualDayFils, 5000);
      // Nothing before 09:00, 2 of 5 by 10:00, all of it by 21:00.
      expect(p.usualShare[9], 0);
      expect(p.usualShare[10], 400);
      expect(p.usualShare[20], 400);
      expect(p.usualShare[21], 1000);
      expect(p.spentFils, 2000);
      expect(p.stillUsualFils, 3000);
      expect(p.expectedFils, 5000);
      expect(p.status, PaceStatus.willPass);
      expect(p.overByFils, 1000);
      // 2.000 + 5.000 x (share - 40%) passes 4.000 between 20:30 and 20:45.
      expect(p.passMinute, 20 * 60 + 45);
      expect(p.lateFils, 0);
    });

    test('fits: what would be left; close to the limit is tight', () {
      final entries = ledger([...history(7), tx(2000, bh(9, minute: 30))]);
      final roomy = dayPace(entries, bh(12), limitFils: 10000)!;
      expect(roomy.status, PaceStatus.onTrack);
      expect(roomy.leftFils, 5000);
      expect(roomy.passMinute, isNull);
      expect(dayPace(entries, bh(12), limitFils: 6000)!.status, PaceStatus.tight);
    });

    test('already over the limit', () {
      final p = dayPace(ledger([...history(7), tx(5000, bh(9, minute: 30))]),
          bh(12), limitFils: 4000)!;
      expect(p.status, PaceStatus.passed);
      expect(p.passMinute, isNull);
    });

    test('late-night spending after 22:00 is named', () {
      final p = dayPace(ledger(history(7, evening: 23)), bh(12), limitFils: 4000)!;
      expect(p.usualShare[23], 400);
      expect(p.lateFils, 3000);
      expect(p.stillUsualFils, 3000);
    });

    test('no forecast with fewer than 5 past spending days or no limit', () {
      expect(dayPace(ledger(history(4)), bh(12), limitFils: 4000), isNull);
      expect(dayPace(ledger(history(7)), bh(12), limitFils: 0), isNull);
      // Days older than 28 days are not used.
      final old = [
        for (var d = 30; d < 37; d++) tx(5000, bh(9, daysBack: d)),
      ];
      expect(dayPace(ledger(old), bh(12), limitFils: 4000), isNull);
    });

    test('integer fils only: odd amounts never give fractions', () {
      final p = dayPace(
          ledger([
            for (var d = 1; d <= 6; d++) tx(1001 + d, bh(8 + d, daysBack: d)),
          ]),
          bh(7, minute: 59),
          limitFils: 3333)!;
      expect(p.usualDayFils, (1002 + 1003 + 1004 + 1005 + 1006 + 1007) ~/ 6);
      expect(p.expectedFils, p.usualDayFils);
      expect(p.status, PaceStatus.onTrack);
    });
  });

  group('the Today card', () {
    tearDown(() => amountsHidden.value = false);

    Future<HomeViewModel> home(List<ExtractionResult> rs, int limit) async {
      final vm = HomeViewModel(
        ledger: InMemoryLedgerRepository(initial: rs),
        settings: InMemorySettingsRepository(
            GuardrailSettings(dailyLimitFils: limit)),
        clock: () => bh(12),
      );
      await vm.load();
      return vm;
    }

    testWidgets('warns before the limit is crossed, and hides amounts with the eye',
        (tester) async {
      final vm = await home([...history(7), tx(2000, bh(9, minute: 30))], 4000);
      expect(vm.state!.pace!.status, PaceStatus.willPass);
      await tester.pumpWidget(BeazaApp(homeViewModel: vm, locale: const Locale('en')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('paceCard')), findsOneWidget);
      expect(find.byKey(const Key('paceChart')), findsOneWidget);
      final line = tester.widget<Text>(find.byKey(const Key('paceLine'))).data!;
      expect(line, contains('Heads-up'));
      expect(line, contains('BHD 3.000'));
      expect(line, contains('BHD 1.000'));
      expect(line, contains('8:45'));

      amountsHidden.value = true;
      await tester.pumpWidget(BeazaApp(homeViewModel: vm, locale: const Locale('en')));
      await tester.pumpAndSettle();
      final hidden = tester.widget<Text>(find.byKey(const Key('paceLine'))).data!;
      expect(hidden, isNot(contains('3.000')));
      expect(hidden, contains(kMaskedAmount));
    });

    testWidgets('Arabic: the same card, right to left', (tester) async {
      final vm = await home(history(7, evening: 23), 3500);
      await tester.pumpWidget(BeazaApp(homeViewModel: vm, locale: const Locale('ar')));
      await tester.pumpAndSettle();
      expect(find.text('وتيرة اليوم'), findsOneWidget);
      expect(find.byKey(const Key('paceLate')), findsOneWidget);
    });

    testWidgets('a new user sees no card until there are 5 days to learn from',
        (tester) async {
      final vm = await home(history(3), 4000);
      expect(vm.state!.pace, isNull);
      await tester.pumpWidget(BeazaApp(homeViewModel: vm, locale: const Locale('en')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('paceCard')), findsNothing);
    });
  });
}
