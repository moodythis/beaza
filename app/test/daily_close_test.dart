import 'package:beaza/app.dart';
import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/preferences_store.dart';
import 'package:beaza/data/repositories/rewards_repository.dart';
import 'package:beaza/data/repositories/savings_repository.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/domain/use_cases/daily_budget.dart';
import 'package:beaza/domain/use_cases/daily_close.dart';
import 'package:beaza/ui/core/formatting.dart';
import 'package:beaza/ui/features/home/view_models/home_view_model.dart';
import 'package:beaza/ui/features/savings/view_models/savings_view_model.dart';
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
      merchantNorm: 'Cafe',
      reference: 'C${_n++}',
      timestamp: at,
    );

List<LedgerEntry> ledger(List<ExtractionResult> rs) =>
    const Reconciler().reconcile(rs, OwnAccounts());

/// [hour]:[minute] Bahrain time on [day] November 2026.
DateTime bh(int day, int hour, [int minute = 0]) =>
    DateTime.utc(2026, 11, day, hour - 3, minute);

class Rig {
  Rig(this.now, List<ExtractionResult> rs, {int limit = 10000})
      : ledgerRepo = InMemoryLedgerRepository(initial: rs),
        settings = InMemorySettingsRepository(
            GuardrailSettings(dailyLimitFils: limit)) {
    repo = SavingsRepository(prefs, clock: () => now);
    savings = SavingsViewModel(
      repo: repo,
      ledger: ledgerRepo,
      rewards: RewardsRepository(prefs, clock: () => now),
      settings: settings,
      clock: () => now,
    );
    home = HomeViewModel(
      ledger: ledgerRepo,
      settings: settings,
      savings: savings,
      clock: () => now,
    );
  }

  DateTime now;
  final prefs = MemoryPreferencesStore();
  final InMemoryLedgerRepository ledgerRepo;
  final InMemorySettingsRepository settings;
  late final SavingsRepository repo;
  late final SavingsViewModel savings;
  late final HomeViewModel home;

  Future<void> load() async {
    await savings.load();
    await home.load();
  }
}

void main() {
  group('closeOffer', () {
    final entries = ledger([tx(3000, bh(4, 10)), tx(2500, bh(3, 12))]);

    test('today from 20:00 with money unspent, not before', () {
      CloseOffer? at(DateTime now) => closeOffer(
            entries: entries,
            now: now,
            todayLimitFils: 10000,
            yesterdayLimitFils: null,
            closes: const [],
          );
      expect(at(bh(4, 19, 59)), isNull);
      final o = at(bh(4, 20))!;
      expect(o.day, const Day(2026, 11, 4));
      expect(o.surplusFils, 7000);
      expect(o.yesterday, isFalse);
      expect(o.noSpending, isFalse);
    });

    test('nothing to close: over the limit, exactly on it, or closed', () {
      CloseOffer? at(int limit, [List<DayClose> closes = const []]) => closeOffer(
            entries: entries,
            now: bh(4, 21),
            todayLimitFils: limit,
            yesterdayLimitFils: null,
            closes: closes,
          );
      expect(at(2000), isNull);
      expect(at(3000), isNull);
      expect(at(0), isNull);
      expect(
          at(10000, const [DayClose(Day(2026, 11, 4), CloseKind.goal, 7000)]),
          isNull);
    });

    test('yesterday left open comes first, with the limit it had', () {
      final o = closeOffer(
        entries: entries,
        now: bh(4, 8),
        todayLimitFils: 10000,
        yesterdayLimitFils: 6000,
        closes: const [],
      )!;
      expect(o.yesterday, isTrue);
      expect(o.day, const Day(2026, 11, 3));
      expect(o.surplusFils, 3500);
      // A day with nothing recorded says so.
      final empty = closeOffer(
        entries: const [],
        now: bh(4, 8),
        todayLimitFils: 10000,
        yesterdayLimitFils: 6000,
        closes: const [],
      )!;
      expect(empty.noSpending, isTrue);
      expect(empty.surplusFils, 6000);
    });

    test('carry-over is capped at half the limit, in integer fils', () {
      const o = CloseOffer(
          day: Day(2026, 11, 4), surplusFils: 7001, yesterday: false, noSpending: false);
      expect(o.rolloverFils(10000), 5000);
      expect(o.rolloverFils(20000), 7001);
      expect(o.rolloverFils(3333), 1666);
      const closes = [DayClose(Day(2026, 11, 4), CloseKind.rollover, 5000)];
      expect(boostFor(closes, const Day(2026, 11, 5), 10000), 5000);
      // The limit shrank overnight: capped again.
      expect(boostFor(closes, const Day(2026, 11, 5), 6000), 3000);
      // One day only.
      expect(boostFor(closes, const Day(2026, 11, 6), 10000), 0);
      expect(boostFor(closes, const Day(2026, 11, 4), 10000), 0);
    });

    test('money sent to the goal leaves the month\'s free money', () {
      const closes = [
        DayClose(Day(2026, 11, 3), CloseKind.goal, 4000),
        DayClose(Day(2026, 11, 9), CloseKind.goal, 6000),
        DayClose(Day(2026, 11, 10), CloseKind.rollover, 2000),
        DayClose(Day(2026, 10, 30), CloseKind.goal, 9000),
        DayClose(Day(2026, 11, 11), CloseKind.goal, 1000),
      ];
      expect(sweptThisMonth(closes, const Day(2026, 11, 11)), 10000);
      const plan = BudgetPlan(incomeFils: 300000);
      // 20 days left from the 11th of a 30-day month.
      expect(safeDailyLimitFils(plan, const [], const Day(2026, 11, 11)), 15000);
      expect(
          safeDailyLimitFils(plan, const [], const Day(2026, 11, 11),
              setAsideFils: 10000),
          14500);
      expect(sweepsInLast30(closes, const Day(2026, 11, 11)), 4);
    });

    test('the boost raises the limit for alerts and the summary', () {
      const g = Guardrail(GuardrailSettings(dailyLimitFils: 10000));
      final s = g.summarize(ledger([tx(9000, bh(5, 10))]), const Day(2026, 11, 5),
          boostFils: 5000);
      expect(s.baseLimitFils, 10000);
      expect(s.limitFils, 15000);
      expect(s.level, AlertLevel.level1);
    });

    test('the reminder is the next 21:30 on a day not yet closed', () {
      expect(nextCloseReminder(bh(4, 12), closedToday: false), bh(4, 21, 30));
      expect(nextCloseReminder(bh(4, 21, 30), closedToday: false), bh(5, 21, 30));
      expect(nextCloseReminder(bh(4, 12), closedToday: true), bh(5, 21, 30));
      // 01:00 Bahrain time is still the evening before in UTC.
      expect(nextCloseReminder(bh(5, 1), closedToday: false), bh(5, 21, 30));
    });
  });

  group('closing a day', () {
    test('to the goal: the goal grows, 10 points, once per day', () async {
      final r = Rig(bh(4, 20, 30), [tx(3000, bh(4, 10))]);
      await r.repo.setGoal('Laptop', 300000);
      await r.load();
      final offer = r.home.state!.close!;
      expect(offer.surplusFils, 7000);
      expect(await r.home.closeDay(offer, CloseKind.goal), 7000);
      expect((await r.repo.goal())!.addedFils, 7000);
      expect(r.home.state!.close, isNull);
      await r.savings.load();
      expect(r.savings.pointsEarned, kClosePoints);
      // A second close of the same day does nothing.
      expect(await r.home.closeDay(offer, CloseKind.goal), 0);
      expect(await r.home.closeDay(offer, CloseKind.rollover), 0);
      expect((await r.repo.goal())!.addedFils, 7000);
    });

    test('without a goal nothing is sent to it', () async {
      final r = Rig(bh(4, 20, 30), [tx(3000, bh(4, 10))]);
      await r.load();
      expect(await r.home.closeDay(r.home.state!.close!, CloseKind.goal), 0);
      expect(await r.repo.closes(), isEmpty);
    });

    test('carried over: tomorrow\'s limit is higher for that day only',
        () async {
      final r = Rig(bh(4, 20, 30), [tx(3000, bh(4, 10))]);
      var reminded = <bool>[];
      r.home.closeReminder =
          ({required bool closedToday}) async => reminded.add(closedToday);
      await r.load();
      expect(await r.home.closeDay(r.home.state!.close!, CloseKind.rollover), 5000);
      expect(reminded, [true]);
      expect(r.home.state!.summary.limitFils, 10000);
      r.now = bh(5, 9);
      await r.home.load();
      expect(r.home.state!.summary.baseLimitFils, 10000);
      expect(r.home.state!.summary.limitFils, 15000);
      r.now = bh(6, 9);
      await r.home.load();
      expect(r.home.state!.summary.limitFils, 10000);
      // No points for carrying over.
      await r.savings.load();
      expect(r.savings.pointsEarned, 10); // the 4th stayed within its limit
    });

    test('yesterday can be closed the next morning, if the app saw it',
        () async {
      final r = Rig(bh(4, 12), [tx(3000, bh(4, 10))]);
      await r.repo.setGoal('Laptop', 300000);
      await r.load();
      expect(r.home.state!.close, isNull); // before 20:00
      r.now = bh(5, 8);
      await r.home.load();
      final offer = r.home.state!.close!;
      expect(offer.yesterday, isTrue);
      expect(offer.surplusFils, 7000);
      await r.home.closeDay(offer, CloseKind.goal);
      expect(r.home.state!.close, isNull);
      // A phone that was not opened yesterday has nothing to close.
      final fresh = Rig(bh(5, 8), [tx(3000, bh(4, 10))]);
      await fresh.load();
      expect(fresh.home.state!.close, isNull);
    });
  });

  group('the close card', () {
    tearDown(() => amountsHidden.value = false);

    Future<Rig> open(WidgetTester tester) async {
      // Tall enough for both buttons to sit above the bottom bar.
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final r = Rig(bh(4, 20, 30), [tx(3000, bh(4, 10))]);
      await r.repo.setGoal('Laptop', 300000);
      await r.load();
      await tester.pumpWidget(
          BeazaApp(homeViewModel: r.home, locale: const Locale('en')));
      await tester.pumpAndSettle();
      return r;
    }

    testWidgets('one tap sends the surplus to the goal; coins fly once',
        (tester) async {
      final r = await open(tester);
      expect(find.byKey(const Key('closeCard')), findsOneWidget);
      expect(find.textContaining('BHD 7.000'), findsWidgets);
      await tester.ensureVisible(find.byKey(const Key('closeGoal')));
      await tester.tap(find.byKey(const Key('closeGoal')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.byKey(const Key('coinFlight')), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.byKey(const Key('coinFlight')), findsNothing);
      expect(find.byKey(const Key('closeCard')), findsNothing);
      expect(find.textContaining('went to your goal'), findsOneWidget);
      expect((await r.repo.goal())!.addedFils, 7000);
    });

    testWidgets('reduced motion: the same result, no flight', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final r = await open(tester);
      await tester.ensureVisible(find.byKey(const Key('closeRollover')));
      await tester.tap(find.byKey(const Key('closeRollover')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.byKey(const Key('coinFlight')), findsNothing);
      expect(find.byKey(const Key('closeCard')), findsNothing);
      expect((await r.repo.closes()).single.fils, 5000);
      expect(find.textContaining("added to tomorrow's limit"), findsOneWidget);
    });

    testWidgets('the eye hides the surplus, in Arabic too', (tester) async {
      amountsHidden.value = true;
      final r = Rig(bh(4, 20, 30), [tx(3000, bh(4, 10))]);
      await r.load();
      await tester.pumpWidget(
          BeazaApp(homeViewModel: r.home, locale: const Locale('ar')));
      await tester.pumpAndSettle();
      expect(find.text('تقفيلة اليوم'), findsOneWidget);
      final left = tester.widget<Text>(find.byKey(const Key('closeLeft'))).data!;
      expect(left, contains(kMaskedAmount));
      expect(left, isNot(contains('7.000')));
      // No goal yet: the first button leads to setting one.
      expect(find.byKey(const Key('closeSetGoal')), findsOneWidget);
      expect(find.byKey(const Key('closeGoal')), findsNothing);
    });
  });
}
