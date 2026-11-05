import 'package:beaza/app.dart';
import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/preferences_store.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/data/services/categorize_api.dart';
import 'package:beaza/domain/use_cases/auto_categorize.dart';
import 'package:beaza/ui/features/home/view_models/home_view_model.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime bh(int day, [int hour = 12]) =>
    DateTime.utc(2026, 11, day, hour).subtract(kBahrainOffset);

int _n = 0;
ExtractionResult spend(int fils, int day, String shop, {String? category}) =>
    ExtractionResult(
      status: ExtractionStatus.transaction,
      amountFils: fils,
      currency: 'BHD',
      type: TxnType.purchase,
      direction: TxDirection.outgoing,
      merchantRaw: shop,
      category: category,
      last4: '4810',
      reference: 'R${_n++}',
      timestamp: bh(day),
    );

class FakeApi implements CategorizeApi {
  final List<List<String>> sent = [];
  Map<String, String> answer = const {};
  bool fail = false;

  @override
  Future<Map<String, String>> categorize(List<String> names) async {
    sent.add(names);
    if (fail) throw Exception('offline');
    return answer;
  }
}

void main() {
  late InMemoryLedgerRepository ledger;
  late MemoryPreferencesStore prefs;
  late FakeApi api;
  late AutoCategorizer auto;

  setUp(() {
    ledger = InMemoryLedgerRepository(initial: [
      spend(3500, 10, 'ZZ GRILL HOUSE 554'),
      spend(1200, 11, 'zz grill house'),
      spend(9000, 12, 'QQ MOBILE SHOP'),
      spend(2000, 12, 'WEIRD NAME CO'),
      spend(4000, 13, 'KNOWN', category: 'food'),
    ]);
    prefs = MemoryPreferencesStore();
    api = FakeApi()
      ..answer = {'ZZ GRILL HOUSE': 'food', 'QQ MOBILE SHOP': 'shopping', 'WEIRD NAME CO': 'nonsense'};
    auto = AutoCategorizer(ledger: ledger, preferences: prefs, api: api);
  });

  test('does nothing before the person turns it on', () async {
    expect(await auto.run(), 0);
    expect(api.sent, isEmpty);
  });

  test('sends only unsorted shop names, once each, without digits', () async {
    await auto.turnOn();
    expect(await auto.run(), 2);
    expect(api.sent.single, ['ZZ GRILL HOUSE', 'QQ MOBILE SHOP', 'WEIRD NAME CO']);
    final cats = (await ledger.entries()).map((e) => e.result.category).toList();
    // The whole shop follows; an unknown answer stays unsorted.
    expect(cats, ['food', 'food', 'shopping', null, 'food']);

    // Asked once: nothing is sent again for the same names.
    expect(await auto.run(), 0);
    expect(api.sent, hasLength(1));
  });

  test('offline: nothing changes and the names are asked next time', () async {
    await auto.turnOn();
    api.fail = true;
    expect(await auto.run(), 0);
    api.fail = false;
    expect(await auto.run(), 2);
  });

  test('turned off: nothing more is sent', () async {
    await auto.turnOn();
    await auto.turnOff();
    expect(await auto.run(), 0);
    expect(api.sent, isEmpty);
  });

  testWidgets('from the unsorted list: agree, sort, then change one by hand',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final vm = HomeViewModel(
      ledger: ledger,
      settings: InMemorySettingsRepository(
          const GuardrailSettings(dailyLimitFils: 10000)),
      autoSort: auto,
      clock: () => bh(13, 15),
    );
    await vm.load();
    await tester.pumpWidget(BeazaApp(homeViewModel: vm, locale: const Locale('en')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sortUnsorted')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('autoSortOn')));
    await tester.pumpAndSettle();
    expect(api.sent, isEmpty); // not before agreeing
    await tester.tap(find.byKey(const Key('autoSortAgree')));
    await tester.pumpAndSettle();
    expect(find.text('Sorted 2 shops. Tap any purchase to change it.'), findsOneWidget);
    expect(find.byKey(const Key('autoSortOnCard')), findsOneWidget);
    expect((await ledger.entries())[2].result.category, 'shopping');
  });
}
