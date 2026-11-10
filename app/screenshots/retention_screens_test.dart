// Pictures of the daily close card, the coin flight and the leaderboard,
// to look at (see pace_screens_test.dart). Text shows as boxes.
import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/preferences_store.dart';
import 'package:beaza/data/repositories/rewards_repository.dart';
import 'package:beaza/data/repositories/savings_repository.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/domain/use_cases/daily_close.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/core/coin_flight.dart';
import 'package:beaza/ui/features/home/views/close_card.dart';
import 'package:beaza/ui/features/savings/view_models/savings_view_model.dart';
import 'package:beaza/ui/features/savings/views/leaderboard_card.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget frame(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF13804C)),
      home: Scaffold(
        body: RepaintBoundary(key: const Key('shot'), child: child),
      ),
    );

void main() {
  testWidgets('close_card_en', (tester) async {
    tester.view.physicalSize = const Size(400, 330) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(frame(SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: CloseCard(
        offer: const CloseOffer(
            day: Day(2026, 11, 10),
            surplusFils: 7000,
            yesterday: false,
            noSpending: false),
        goalName: 'Laptop',
        baseLimitFils: 10000,
        onClose: (_) async => 0,
      ),
    )));
    await tester.pumpAndSettle();
    await expectLater(
        find.byKey(const Key('shot')), matchesGoldenFile('close_card_en.png'));
  });

  for (final (name, t, rtl) in [
    ('flight_30', 0.30, false),
    ('flight_55', 0.55, false),
    ('flight_80', 0.80, false),
    ('flight_55_ar', 0.55, true),
  ]) {
    testWidgets(name, (tester) async {
      tester.view.physicalSize = const Size(360, 640) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      const size = Size(360, 640);
      const from = Rect.fromLTWH(16, 150, 328, 170);
      final to = Offset(rtl ? size.width / 8 : size.width * 7 / 8, size.height - 52);
      await tester.pumpWidget(frame(
        Stack(children: [
          // Where the card and the bottom bar are.
          Positioned.fromRect(
              rect: from,
              child: const DecoratedBox(
                  decoration: BoxDecoration(
                      color: Color(0xFFD7EFE1),
                      borderRadius: BorderRadius.all(Radius.circular(12))))),
          const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 80,
              child: ColoredBox(color: Color(0xFFEDF2EE))),
          Positioned(
              left: to.dx - 12,
              top: to.dy - 12,
              child: const Icon(Icons.savings_outlined)),
          Positioned.fill(
            child: CustomPaint(
              painter: CoinFlightPainter(
                t: t,
                from: from,
                to: to,
                label: '+BHD 7.000',
                accent: const Color(0xFF13804C),
                labelStyle: const TextStyle(
                    color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
              ),
            ),
          ),
        ]),
        locale: rtl ? const Locale('ar') : const Locale('en'),
      ));
      await tester.pump();
      await expectLater(
          find.byKey(const Key('shot')), matchesGoldenFile('$name.png'));
    });
  }

  for (final (name, locale) in [
    ('board_en', const Locale('en')),
    ('board_ar', const Locale('ar')),
  ]) {
    testWidgets(name, (tester) async {
      tester.view.physicalSize = const Size(400, 900) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final now = DateTime.utc(2026, 11, 10, 9);
      final prefs = MemoryPreferencesStore();
      var n = 0;
      final vm = SavingsViewModel(
        repo: SavingsRepository(prefs, clock: () => now),
        ledger: InMemoryLedgerRepository(initial: [
          for (var d = 1; d <= 9; d++)
            ExtractionResult(
              status: ExtractionStatus.transaction,
              amountFils: 3000,
              currency: 'BHD',
              type: TxnType.purchase,
              direction: TxDirection.outgoing,
              merchantNorm: 'Cafe',
              reference: 'B${n++}',
              timestamp: DateTime.utc(2026, 11, d, 9),
            ),
        ]),
        rewards: RewardsRepository(prefs, clock: () => now),
        settings: InMemorySettingsRepository(
            const GuardrailSettings(dailyLimitFils: 10000)),
        clock: () => now,
      );
      await vm.load();
      await tester.pumpWidget(frame(
        SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            StreakRow(viewModel: vm),
            const SizedBox(height: 12),
            LeaderboardCard(viewModel: vm),
          ]),
        ),
        locale: locale,
      ));
      await tester.pumpAndSettle();
      await expectLater(
          find.byKey(const Key('shot')), matchesGoldenFile('$name.png'));
    });
  }
}
