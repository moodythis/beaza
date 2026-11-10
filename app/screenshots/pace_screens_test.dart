// Not part of the normal test run: CI runs it with --update-goldens and
// uploads the pictures, so the chart can be looked at. Text shows as
// boxes (the test font); the drawing is what is checked by eye.
import 'package:beaza/domain/use_cases/day_pace.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/features/home/views/pace_card.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

int _n = 0;
ExtractionResult tx(int fils, DateTime at) => ExtractionResult(
      status: ExtractionStatus.transaction,
      amountFils: fils,
      currency: 'BHD',
      type: TxnType.purchase,
      direction: TxDirection.outgoing,
      merchantNorm: 'Shop',
      reference: 'S${_n++}',
      timestamp: at,
    );

DateTime bh(int hour, {int minute = 0, int daysBack = 0}) =>
    DateTime.utc(2026, 11, 4, hour - 3, minute).subtract(Duration(days: daysBack));

void main() {
  final entries = const Reconciler().reconcile([
    for (var d = 1; d <= 10; d++) ...[
      tx(1200, bh(8, minute: 10, daysBack: d)),
      tx(800 + d * 50, bh(13, daysBack: d)),
      tx(2500, bh(d.isEven ? 22 : 20, minute: 30, daysBack: d)),
    ],
    tx(1500, bh(8, minute: 20)),
    tx(1800, bh(13, minute: 5)),
  ], OwnAccounts());
  final pace = dayPace(entries, bh(15, minute: 30), limitFils: 5000)!;

  for (final (name, locale, brightness) in [
    ('pace_en_light', const Locale('en'), Brightness.light),
    ('pace_en_dark', const Locale('en'), Brightness.dark),
    ('pace_ar_light', const Locale('ar'), Brightness.light),
  ]) {
    testWidgets(name, (tester) async {
      tester.view.physicalSize = const Size(400, 520) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
            colorSchemeSeed: const Color(0xFF13804C), brightness: brightness),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
            padding: const EdgeInsets.all(12),
            child: RepaintBoundary(
                key: const Key('shot'), child: PaceCard(pace: pace)),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await expectLater(find.byKey(const Key('shot')), matchesGoldenFile('$name.png'));
    });
  }
}
