import 'dart:convert';

import 'package:beaza/app.dart';
import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/preferences_store.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/data/services/coach_api.dart';
import 'package:beaza/domain/use_cases/coach_request.dart';
import 'package:beaza/domain/use_cases/custom_categories.dart';
import 'package:beaza/domain/use_cases/daily_budget.dart';
import 'package:beaza/ui/features/account/legal_text.dart';
import 'package:beaza/ui/features/account/views/account_widgets.dart';
import 'package:beaza/ui/features/coach/view_models/coach_view_model.dart';
import 'package:beaza/ui/features/home/view_models/home_view_model.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final DateTime now = DateTime.utc(2026, 11, 14, 9); // 12:00 in Bahrain
DateTime bh(int day, [int hour = 12]) =>
    DateTime.utc(2026, 11, day, hour).subtract(kBahrainOffset);

int _n = 0;
ExtractionResult tx(int fils, DateTime at, {String? category, String? shop}) =>
    ExtractionResult(
      status: ExtractionStatus.transaction,
      amountFils: fils,
      currency: 'BHD',
      type: TxnType.purchase,
      direction: TxDirection.outgoing,
      category: category,
      merchantRaw: shop,
      last4: '4810',
      reference: 'NBB${_n++}REF',
      timestamp: at,
    );

List<ExtractionResult> sample() => [
      tx(3900, bh(14, 9), category: 'food', shop: 'COSTA COFFEE SEEF'),
      tx(13200, bh(12, 20), category: 'shopping', shop: 'REDTAG MANAMA'),
      tx(2050, bh(10, 16), shop: 'Waleed Al Kabah MANAMA'),
      tx(12000, bh(3, 10), category: 'food'), // the week before
    ];

class FakeCoach implements CoachApi {
  final List<Map<String, Object>> sent = [];
  CoachException? fail;

  @override
  Future<CoachPlan> plan(Map<String, Object> request) async {
    sent.add(request);
    if (fail != null) throw fail!;
    return const CoachPlan(text: '1. خفّف التسوق.', fromModel: true);
  }
}

Future<(CoachViewModel, FakeCoach, MemoryPreferencesStore)> make() async {
  final api = FakeCoach();
  final prefs = MemoryPreferencesStore();
  final vm = CoachViewModel(
    api: api,
    preferences: prefs,
    ledger: InMemoryLedgerRepository(initial: sample()),
    settings: InMemorySettingsRepository(
        const GuardrailSettings(dailyLimitFils: 10000)),
    clock: () => now,
  );
  await vm.load();
  return (vm, api, prefs);
}

void main() {
  group('what is sent', () {
    test('own categories go as "other", added to it, never by name',
        () async {
      final ledger = InMemoryLedgerRepository(initial: [
        tx(3000, bh(14, 9), category: 'custom:Gifts for Sara'),
        tx(2000, bh(13, 9), category: 'other'),
        tx(1000, bh(12, 9), category: 'food'),
      ]);
      final r = coachRequest(await ledger.entries(),
          const GuardrailSettings(dailyLimitFils: 10000), const Day(2026, 11, 14), 'en');
      expect(r['categories'], [
        {'category': 'other', 'fils': 5000, 'percent': 83},
        {'category': 'food', 'fils': 1000, 'percent': 17},
      ]);
      for (final x in (r['recent'] as List).cast<Map<String, Object>>()) {
        expect(x['category'], isNot(startsWith('custom:')));
      }
      expect(jsonEncode(r), isNot(contains('Sara')));
    });

    test('custom category names are cleaned and listed from the ledger',
        () async {
      expect(customCategory('  Car\n  wash '), 'custom:Car wash');
      expect(customCategory('   '), isNull);
      expect(customCategoryName(customCategory('x' * 40)!).length, 24);
      final ledger = InMemoryLedgerRepository(initial: [
        tx(100, bh(14), category: 'custom:Car'),
        tx(100, bh(13), category: 'custom:Car'),
        tx(100, bh(12), category: 'custom:Baby'),
        tx(100, bh(11), category: 'food'),
      ]);
      expect(customCategoriesIn(await ledger.entries()),
          ['custom:Baby', 'custom:Car']);
    });

    test('totals and top shop names; no text, digits, reference or date',
        () async {
      final ledger = InMemoryLedgerRepository(initial: sample());
      final r = coachRequest(await ledger.entries(),
          const GuardrailSettings(dailyLimitFils: 10000), const Day(2026, 11, 14), 'ar');
      expect(r.keys.toSet(), {
        'consent', 'language', 'week_total_fils', 'previous_week_total_fils',
        'daily_limit_fils', 'days_over_limit', 'small_purchases_count',
        'small_purchases_fils', 'categories', 'shops', 'recent',
        'late_night_count', 'late_night_fils', 'weekend_fils',
      });
      expect(r['week_total_fils'], 19150);
      expect(r['previous_week_total_fils'], 12000);
      expect(r['days_over_limit'], 1);
      expect(r['small_purchases_count'], 2);
      expect(r['small_purchases_fils'], 5950);
      expect(r['categories'], [
        {'category': 'shopping', 'fils': 13200, 'percent': 69},
        {'category': 'food', 'fils': 3900, 'percent': 20},
        {'category': 'unsorted', 'fils': 2050, 'percent': 11},
      ]);
      expect(r['shops'], [
        {'name': 'REDTAG MANAMA', 'fils': 13200, 'count': 1},
        {'name': 'COSTA COFFEE SEEF', 'fils': 3900, 'count': 1},
        {'name': 'Waleed Al Kabah MANAMA', 'fils': 2050, 'count': 1},
      ]);
      final json = jsonEncode(r);
      for (final secret in ['4810', 'NBB', 'REF', 'timestamp']) {
        expect(json, isNot(contains(secret)), reason: secret);
      }
    });

    test('shop names lose every digit; transfers to people are left out; '
        'at most 5 shops, grouped by name', () async {
      final sent = ExtractionResult(
        status: ExtractionStatus.transaction,
        amountFils: 20000,
        currency: 'BHD',
        type: TxnType.transferOut,
        direction: TxDirection.outgoing,
        merchantRaw: 'AHMED ALI',
        timestamp: bh(12),
      );
      final ledger = InMemoryLedgerRepository(initial: [
        sent,
        tx(1000, bh(9), shop: 'TALABAT 1234 *5678'),
        tx(1500, bh(10), shop: 'talabat'),
        tx(900, bh(11), shop: 'كافيه ٤٥٦ السيف'),
        for (var i = 0; i < 6; i++) tx(500 + i, bh(13, 8 + i), shop: 'SHOP ${'ABCDEF'[i]}'),
      ]);
      final r = coachRequest(await ledger.entries(),
          const GuardrailSettings(dailyLimitFils: 10000), const Day(2026, 11, 14), 'en');
      final shops = (r['shops'] as List).cast<Map<String, Object>>();
      expect(shops, hasLength(kCoachMaxShops));
      expect(shops.first, {'name': 'TALABAT', 'fils': 2500, 'count': 2});
      expect(shops[1]['name'], 'كافيه السيف');
      final json = jsonEncode(r);
      expect(json, isNot(contains('AHMED')));
      expect(RegExp(r'[0-9\u0660-\u0669]').hasMatch(
          shops.map((x) => x['name']).join()), isFalse);
    });

    test('late-night and weekend totals; month left only with a plan',
        () async {
      // 13 Nov 2026 is a Friday; 14 Nov (today) a Saturday.
      final ledger = InMemoryLedgerRepository(initial: [
        tx(1500, bh(9, 23)),
        tx(1200, bh(10, 1)),
        tx(4000, bh(13, 15)),
        tx(30000, bh(2, 10)), // earlier this month, outside the week
      ]);
      final entries = await ledger.entries();
      final r = coachRequest(entries,
          const GuardrailSettings(dailyLimitFils: 10000), const Day(2026, 11, 14), 'en');
      expect(r['late_night_count'], 2);
      expect(r['late_night_fils'], 2700);
      expect(r['weekend_fils'], 4000);
      expect(r.containsKey('month_left_fils'), isFalse);

      final withPlan = coachRequest(entries,
          const GuardrailSettings(dailyLimitFils: 10000), const Day(2026, 11, 14), 'en',
          plan: const BudgetPlan(incomeFils: 300000, fixedFils: 105000));
      // 195.000 free - 36.700 spent so far = 158.300, for 16 days after today.
      expect(withPlan['month_left_fils'], 158300);
      expect(withPlan['days_left_in_month'], 16);
      expect(jsonEncode(withPlan), isNot(contains('300000')));
    });

    test('this week\'s purchases one by one: weekday, hour, amount, '
        'category, shop; no transfers, newest first', () async {
      final sent = ExtractionResult(
        status: ExtractionStatus.transaction,
        amountFils: 20000,
        currency: 'BHD',
        type: TxnType.transferOut,
        direction: TxDirection.outgoing,
        merchantRaw: 'AHMED ALI 33445566',
        timestamp: bh(12),
      );
      final ledger = InMemoryLedgerRepository(initial: [...sample(), sent]);
      final r = coachRequest(await ledger.entries(),
          const GuardrailSettings(dailyLimitFils: 10000), const Day(2026, 11, 14), 'en');
      // 14 Nov 2026 is a Saturday, 12 Nov a Thursday, 10 Nov a Tuesday.
      expect(r['recent'], [
        {'weekday': 'sat', 'hour': 9, 'fils': 3900, 'category': 'food', 'shop': 'COSTA COFFEE SEEF'},
        {'weekday': 'thu', 'hour': 20, 'fils': 13200, 'category': 'shopping', 'shop': 'REDTAG MANAMA'},
        {'weekday': 'tue', 'hour': 16, 'fils': 2050, 'category': 'unsorted', 'shop': 'Waleed Al Kabah MANAMA'},
      ]);
      final json = jsonEncode(r);
      for (final secret in ['AHMED', '33445566', '4810', 'NBB']) {
        expect(json, isNot(contains(secret)), reason: secret);
      }
    });

    test('coachShopName', () {
      expect(coachShopName(null), isNull);
      expect(coachShopName('1234'), isNull);
      expect(coachShopName(' - Jasmis 22 - '), 'Jasmis');
      expect(coachShopName('A' * 60)!.length, 40);
    });
  });

  group('consent', () {
    test('nothing is sent before agreeing, or after withdrawing', () async {
      final (vm, api, prefs) = await make();
      await vm.requestPlan('ar');
      expect(api.sent, isEmpty);

      await vm.agree();
      expect(prefs.values[CoachViewModel.prefName], kCoachConsentVersion);
      await vm.requestPlan('ar');
      expect(api.sent, hasLength(1));
      expect(vm.step, CoachStep.ready);
      expect(vm.plan!.text, '1. خفّف التسوق.');

      await vm.withdraw();
      expect(prefs.values, isEmpty);
      await vm.requestPlan('ar');
      expect(api.sent, hasLength(1));
    });

    test('an older consent version counts as no consent', () async {
      final (vm, _, prefs) = await make();
      prefs.values[CoachViewModel.prefName] = '2020-01-01';
      await vm.load();
      expect(vm.consented, isFalse);
    });

    test('a refused request keeps its code', () async {
      final (vm, api, _) = await make();
      await vm.agree();
      api.fail = const CoachException('coach_busy');
      await vm.requestPlan('en');
      expect(vm.step, CoachStep.failed);
      expect(vm.error, 'coach_busy');
    });
  });

  group('HttpCoachApi', () {
    test('posts JSON to /v1/coach and reads the plan', () async {
      late http.Request seen;
      final api = HttpCoachApi(
        baseUrl: 'https://sync.example',
        client: MockClient((req) async {
          seen = req;
          return http.Response(
              jsonEncode({'plan': ' 1. Plan ', 'source': 'rules'}), 200,
              headers: {'content-type': 'application/json'});
        }),
      );
      final plan = await api.plan({'language': 'en'});
      expect(seen.url.toString(), 'https://sync.example/v1/coach');
      expect(jsonDecode(seen.body), {'language': 'en'});
      expect(plan.text, '1. Plan');
      expect(plan.fromModel, isFalse);
    });

    test('server errors become their codes', () async {
      final api = HttpCoachApi(
        baseUrl: 'https://sync.example',
        client: MockClient((_) async => http.Response(
            jsonEncode({'error': 'coach_busy'}), 429)),
      );
      await expectLater(api.plan({}),
          throwsA(isA<CoachException>().having((e) => e.code, 'code', 'coach_busy')));
    });
  });

  testWidgets('the card asks for consent with the exact list, then shows the plan',
      (tester) async {
    final (coach, api, _) = await make();
    final home = HomeViewModel(
      ledger: InMemoryLedgerRepository(initial: sample()),
      settings: InMemorySettingsRepository(
          const GuardrailSettings(dailyLimitFils: 10000)),
      coach: coach,
      clock: () => now,
    );
    await home.load();
    await tester.pumpWidget(BeazaApp(homeViewModel: home));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('coachAsk')), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.byKey(const Key('coachAsk')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('coachAsk')));
    await tester.pumpAndSettle();

    // The list is folded so the buttons stay in view; it opens on a tap.
    expect(find.text('• Spent in the last 7 days: BHD 19.150'), findsNothing);
    await tester.tap(find.byKey(const Key('coachWhat')));
    await tester.pumpAndSettle();
    expect(find.text('• Spent in the last 7 days: BHD 19.150'), findsOneWidget);
    expect(find.text('• Shopping: BHD 13.200 (69%)'), findsOneWidget);
    expect(api.sent, isEmpty);

    await tester.ensureVisible(find.byKey(const Key('coachAgree')));
    await tester.tap(find.byKey(const Key('coachAgree')));
    await tester.pumpAndSettle();
    expect(api.sent, hasLength(1));
    expect(find.byKey(const Key('coachPlan')), findsOneWidget);
    expect(
        find.text('Written by AI from your totals. Every number in it was checked against them.'),
        findsOneWidget);

    await tester.tap(find.byKey(const Key('coachWithdraw')));
    await tester.pumpAndSettle();
    expect(coach.consented, isFalse);
  });

  testWidgets('the consent links to the AI plan part of the privacy notice',
      (tester) async {
    final (coach, _, _) = await make();
    final home = HomeViewModel(
      ledger: InMemoryLedgerRepository(initial: sample()),
      settings: InMemorySettingsRepository(
          const GuardrailSettings(dailyLimitFils: 10000)),
      coach: coach,
      clock: () => now,
    );
    await home.load();
    await tester.pumpWidget(BeazaApp(homeViewModel: home));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('coachAsk')), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.byKey(const Key('coachAsk')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('coachAsk')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('coachPrivacy')));
    await tester.pumpAndSettle();
    final title = privacyNotice.en[kPrivacyCoachSection].title;
    expect(title, startsWith('AI savings plan'));
    expect(find.text(title), findsOneWidget);
    expect(tester.getTopLeft(find.text(title)).dy, lessThan(400));
  });
}
