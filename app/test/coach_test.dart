import 'dart:convert';

import 'package:beaza/app.dart';
import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/preferences_store.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/data/services/coach_api.dart';
import 'package:beaza/domain/use_cases/coach_request.dart';
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
    test('only totals, no shop, text, digits, reference or date', () async {
      final ledger = InMemoryLedgerRepository(initial: sample());
      final r = coachRequest(await ledger.entries(),
          const GuardrailSettings(dailyLimitFils: 10000), const Day(2026, 11, 14), 'ar');
      expect(r.keys.toSet(), {
        'consent', 'language', 'week_total_fils', 'previous_week_total_fils',
        'daily_limit_fils', 'days_over_limit', 'small_purchases_count',
        'small_purchases_fils', 'categories',
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
      final json = jsonEncode(r);
      for (final secret in ['COSTA', 'REDTAG', 'Waleed', '4810', 'NBB', 'timestamp']) {
        expect(json, isNot(contains(secret)), reason: secret);
      }
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
}
