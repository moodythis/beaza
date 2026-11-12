import 'package:beaza/app.dart';
import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/savings_repository.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/data/services/hold_reminders.dart';
import 'package:beaza/domain/use_cases/weekly_report.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/core/formatting.dart';
import 'package:beaza/ui/features/home/view_models/home_view_model.dart';
import 'package:beaza/ui/features/report/weekly_report_view.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Bahrain local time in November 2026 as the UTC instant stored.
DateTime bh(int day, int hour, [int minute = 0]) =>
    DateTime.utc(2026, 11, day, hour, minute).subtract(kBahrainOffset);

var _ref = 0;

ExtractionResult buy(int fils, DateTime at,
        {String? shop, String? category, Channel? channel}) =>
    ExtractionResult(
      status: ExtractionStatus.transaction,
      amountFils: fils,
      currency: 'BHD',
      type: TxnType.purchase,
      direction: TxDirection.outgoing,
      merchantRaw: shop,
      merchantNorm: shop,
      category: category,
      channel: channel,
      reference: 'R${_ref++}',
      timestamp: at,
    );

List<LedgerEntry> rec(List<ExtractionResult> r) =>
    const Reconciler().reconcile(r, OwnAccounts());

void main() {
  // 1 November 2026 is a Sunday, 7 November a Saturday.
  const end = Day(2026, 11, 7);

  test('nothing spent: an empty report, no division by zero', () {
    final r = buildWeeklyReport(const [], end, dailyLimitFils: 10000);
    expect(r.isEmpty, isTrue);
    expect(r.deltaPercent, isNull);
    expect(r.percentOf(0), 0);
    expect(r.cheapestDay, isNull);
    expect(r.days.every((d) => d.status == DayStatus.none), isTrue);
    expect(r.points, 0);
  });

  test('week against the week before, average and the limits left', () {
    final w = buildWeeklyReport(
        rec([
          buy(20000, DateTime.utc(2026, 10, 28, 9)), // the week before
          buy(9000, bh(2, 12), shop: 'JASMIS', category: 'food'),
          buy(7000, bh(3, 12), shop: 'JASMIS', category: 'food'),
        ]),
        end,
        dailyLimitFils: 10000);
    expect(w.totalFils, 16000);
    expect(w.previousFils, 20000);
    expect(w.deltaFils, -4000);
    expect(w.deltaPercent, -20);
    expect(w.dailyAverageFils, 16000 ~/ 7);
    expect(w.netSavedFils, 70000 - 16000);
  });

  test('day colours: under 80%, 80 to 100%, over, nothing', () {
    final r = buildWeeklyReport(
        rec([
          buy(5000, bh(1, 12)),
          buy(8000, bh(2, 12)),
          buy(12000, bh(3, 12)),
        ]),
        end,
        dailyLimitFils: 10000);
    expect(r.days.take(4).map((d) => d.status), [
      DayStatus.good,
      DayStatus.close,
      DayStatus.over,
      DayStatus.none,
    ]);
    expect(r.daysWithinLimit, 2);
    expect(r.cheapestDay!.day, const Day(2026, 11, 1));
    expect(r.heaviestDay!.day, const Day(2026, 11, 3));
    expect(r.points, 20); // two days with spending within the limit
  });

  test('late night uses Bahrain time; Thursday to Saturday is the weekend', () {
    final r = buildWeeklyReport(
        rec([
          buy(1000, bh(4, 23, 30)), // 23:30 Bahrain = 20:30 UTC: late
          buy(1000, bh(5, 2, 59)), // Thursday 02:59: late
          buy(1000, bh(5, 3, 0)), // Thursday 03:00: not late
          buy(4000, bh(6, 13)), // Friday
          buy(3000, bh(7, 13)), // Saturday
        ]),
        end,
        dailyLimitFils: 10000);
    expect(r.lateCount, 2);
    expect(r.lateFils, 2000);
    // Thursday 2.000 + Friday 4.000 + Saturday 3.000.
    expect(r.weekendFils, 9000);
    expect(r.percentOf(r.weekendFils), 90);
    expect(r.peak, TimeSlot.afternoon);
  });

  test('small purchases, top shops, largest purchase and channels', () {
    final r = buildWeeklyReport(
        rec([
          buy(1500, bh(1, 9), shop: 'COSTA', channel: Channel.card),
          buy(1700, bh(2, 9), shop: 'COSTA', channel: Channel.card),
          buy(2000, bh(3, 9), shop: 'COSTA', channel: Channel.wallet),
          buy(15000, bh(4, 18), shop: 'IKEA', channel: Channel.card),
        ]),
        end,
        dailyLimitFils: 20000);
    expect(r.microCount, 3);
    expect(r.microFils, 5200);
    expect(r.topShops.first.name, 'IKEA');
    expect(r.topShops[1].count, 3);
    expect(r.largest!.fils, 15000);
    expect(r.channels[PayChannel.card], 18200);
    expect(r.channels[PayChannel.wallet], 2000);
  });

  test('holds skipped this week count; others do not', () {
    Hold h(String id, int fils, String decision, DateTime at) => Hold(
          id: id,
          name: id,
          amountFils: fils,
          createdAt: at.subtract(const Duration(days: 1)),
          decision: decision,
          decidedAt: at,
        );
    final r = buildWeeklyReport(const [], end, dailyLimitFils: 10000, holds: [
      h('a', 11000, 'skipped', bh(3, 12)),
      h('b', 5000, 'bought', bh(3, 12)),
      h('c', 9000, 'skipped', DateTime.utc(2026, 10, 20)),
    ]);
    expect(r.skippedCount, 1);
    expect(r.skippedFils, 11000);
    expect(r.points, 20);
  });

  test('the shared summary has no amounts or shops', () {
    final r = buildWeeklyReport(
        rec([buy(9000, bh(2, 12), shop: 'SECRET SHOP', category: 'food')]),
        end,
        dailyLimitFils: 10000);
    final s = shareSummary(r, 'en', (b) => b);
    expect(s, contains('food 100%'));
    expect(s, isNot(contains('SECRET')));
    expect(s, isNot(contains('9.000')));
  });

  test('the weekly notification is set for Saturday 21:00 Bahrain', () {
    // Monday 9 November 2026, 20:00 Bahrain.
    final at = nextWeekEnd(DateTime.utc(2026, 11, 9, 17));
    expect(at, DateTime.utc(2026, 11, 14, 18));
    // Saturday 21:30: the next Saturday.
    expect(nextWeekEnd(DateTime.utc(2026, 11, 14, 18, 30)),
        DateTime.utc(2026, 11, 21, 18));
  });

  group('screens', () {
    tearDown(() => amountsHidden.value = false);

    Future<HomeViewModel> pump(WidgetTester tester) async {
      final vm = HomeViewModel(
        ledger: InMemoryLedgerRepository(initial: [
          buy(1601, bh(5, 10), shop: 'JASMIS', category: 'food'),
        ]),
        settings: InMemorySettingsRepository(
            const GuardrailSettings(dailyLimitFils: 10000)),
        clock: () => bh(5, 12),
      );
      await vm.load();
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(BeazaApp(homeViewModel: vm, locale: const Locale('ar')));
      await tester.pumpAndSettle();
      return vm;
    }

    testWidgets('a largest purchase without a shop shows no empty name',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final vm = WeeklyReportViewModel(
        // An account debit as Al Salam sends it: amount, no shop.
        ledger: InMemoryLedgerRepository(initial: [
          buy(5200, bh(7, 13)),
          buy(2700, bh(6, 20), shop: 'SHAWARMA', category: 'food'),
        ]),
        settings: InMemorySettingsRepository(
            const GuardrailSettings(dailyLimitFils: 10000)),
        clock: () => bh(7, 18),
      );
      await vm.load();
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('ar'),
        home: WeeklyReportView(viewModel: vm),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('أكبر مشترى: السبت'), findsOneWidget);
      expect(find.textContaining('مشترى: ،'), findsNothing);
      expect(find.textContaining('مشترى: -'), findsNothing);
    });

    testWidgets('the eye hides every amount and shows it again', (tester) async {
      await pump(tester);
      expect(find.textContaining('1.601'), findsWidgets);
      await tester.tap(find.byKey(const Key('privacyButton')));
      await tester.pumpAndSettle();
      expect(find.textContaining('1.601'), findsNothing);
      expect(find.textContaining('•••• د.ب'), findsWidgets);
      await tester.tap(find.byKey(const Key('privacyButton')));
      await tester.pumpAndSettle();
      expect(find.textContaining('1.601'), findsWidgets);
    });

    testWidgets('the weekly report opens from Today and moves between weeks',
        (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('reportOpen')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reportHeadline')), findsOneWidget);
      expect(find.byKey(const Key('reportTotal')), findsOneWidget);
      expect(find.text('1.601 د.ب'), findsWidgets);
      await tester.tap(find.byKey(const Key('reportOlder')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reportEmpty')), findsOneWidget);
      await tester.tap(find.byKey(const Key('reportNewer')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reportHeadline')), findsOneWidget);
    });
  });
}
