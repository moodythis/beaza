// Start-up speed (NFR-4). Prints "BENCH <name> <ms>" lines that CI copies
// to the run's summary page. The limits are loose on purpose (CI machines
// vary); they catch a change that makes start-up many times slower.
import 'package:beaza/app.dart';
import 'package:beaza/data/repositories/drift_ledger_repository.dart';
import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/data/services/database.dart';
import 'package:beaza/data/services/database_opener.dart';
import 'package:beaza/data/repositories/preferences_store.dart';
import 'package:beaza/data/repositories/rewards_repository.dart';
import 'package:beaza/data/repositories/savings_repository.dart';
import 'package:beaza/domain/use_cases/weekly_report.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/features/history/view_models/history_view_model.dart';
import 'package:beaza/ui/features/history/views/history_view.dart';
import 'package:beaza/ui/features/home/view_models/home_view_model.dart';
import 'package:beaza/ui/features/savings/view_models/savings_view_model.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Noon on 4 November 2026, Bahrain time.
final DateTime now = DateTime.utc(2026, 11, 4, 9);

int _n = 0;
ExtractionResult tx(int fils, DateTime at, String shop) => ExtractionResult(
      status: ExtractionStatus.transaction,
      amountFils: fils,
      currency: 'BHD',
      type: TxnType.purchase,
      direction: TxDirection.outgoing,
      merchantNorm: shop,
      reference: 'P${_n++}',
      timestamp: at,
    );

/// A heavy user's year: 5 purchases a day for 365 days.
List<ExtractionResult> year() => [
      for (var d = 0; d < 365; d++)
        for (var k = 0; k < 5; k++)
          tx(500 + (d * 37 + k * 211) % 6000,
              now.subtract(Duration(days: d, hours: 1 + k * 3)), 'Shop $k'),
    ];

void bench(String name, Duration took) =>
    // ignore: avoid_print
    print('BENCH $name ${took.inMilliseconds} ms');

/// Counts how often the whole ledger is read.
class CountingLedger extends InMemoryLedgerRepository {
  CountingLedger({super.initial});
  int reads = 0;

  @override
  Future<List<LedgerEntry>> entries() {
    reads++;
    return super.entries();
  }
}

void main() {
  group('the stored ledger is read once per change', () {
    late AppDatabase db;
    late DriftLedgerRepository ledger;
    setUp(() {
      db = openMemoryDatabase();
      ledger = DriftLedgerRepository(db, deviceId: 'd', clock: () => now);
    });
    tearDown(() => db.close());

    test('a second read without a change is the same list', () async {
      await ledger.addManual(amountFils: 1000, at: now);
      final a = await ledger.entries();
      final b = await ledger.entries();
      expect(identical(a, b), isTrue);
      expect(() => (a as List).add(a.first), throwsUnsupportedError);
    });

    test('a change is seen by the next read', () async {
      await ledger.addManual(amountFils: 1000, at: now);
      expect(await ledger.entries(), hasLength(1));
      await ledger.addManual(amountFils: 2000, at: now);
      expect(await ledger.entries(), hasLength(2));
      await ledger.remove((await ledger.entries()).first);
      expect(await ledger.entries(), hasLength(1));
    });

    test('a read that started before a change is not kept', () async {
      await ledger.addManual(amountFils: 1000, at: now);
      final early = ledger.entries();
      await ledger.addManual(amountFils: 2000, at: now);
      await early;
      expect(await ledger.entries(), hasLength(2));
    });

    test('a year of messages: first read and cached read', () async {
      await db.batch((b) {
        for (final r in year()) {
          b.insert(
              db.ledgerRows,
              LedgerRowsCompanion.insert(
                id: 'r${r.reference}',
                amountFils: r.amountFils!,
                currency: 'BHD',
                type: Value(r.type!.name),
                direction: r.direction.name,
                timestampMs: r.timestamp!.millisecondsSinceEpoch,
                merchantNorm: Value(r.merchantNorm),
                reference: Value(r.reference),
                templateVersion: 'bench',
                source: 'message',
                deviceId: 'd',
                updatedAtMs: 0,
              ));
        }
      });
      final cold = Stopwatch()..start();
      final first = await ledger.entries();
      cold.stop();
      final warm = Stopwatch()..start();
      await ledger.entries();
      warm.stop();
      expect(first, hasLength(1825));
      bench('ledger_first_read_1825', cold.elapsed);
      bench('ledger_cached_read_1825', warm.elapsed);
      expect(cold.elapsed, lessThan(const Duration(seconds: 3)));
      expect(warm.elapsed, lessThan(const Duration(milliseconds: 20)));
    });
  });

  group('the Today screen', () {
    test('loads called together run at most twice', () async {
      final ledger = CountingLedger(initial: year());
      final vm = HomeViewModel(
        ledger: ledger,
        settings: InMemorySettingsRepository(
            const GuardrailSettings(dailyLimitFils: 8000)),
        clock: () => now,
      );
      await Future.wait([for (var i = 0; i < 5; i++) vm.load()]);
      expect(ledger.reads, lessThanOrEqualTo(2));
      expect(vm.state, isNotNull);
      vm.dispose();
    });

    testWidgets('a year of data: load and first frame', (tester) async {
      final vm = HomeViewModel(
        ledger: InMemoryLedgerRepository(initial: year()),
        settings: InMemorySettingsRepository(
            const GuardrailSettings(dailyLimitFils: 8000)),
        clock: () => now,
      );
      final load = Stopwatch()..start();
      await tester.runAsync(vm.load);
      load.stop();
      expect(vm.state, isNotNull);

      final frame = Stopwatch()..start();
      await tester.pumpWidget(
          BeazaApp(homeViewModel: vm, locale: const Locale('en')));
      frame.stop();
      await tester.pumpAndSettle();
      expect(vm.state!.pace, isNotNull);

      bench('home_load_1825', load.elapsed);
      bench('home_first_frame', frame.elapsed);
      expect(load.elapsed, lessThan(const Duration(seconds: 3)));
      expect(frame.elapsed, lessThan(const Duration(seconds: 3)));
    });
  });

  group('other screens with a year of data', () {
    testWidgets('History: load and first frame', (tester) async {
      final vm = HistoryViewModel(ledger: InMemoryLedgerRepository(initial: year()));
      final load = Stopwatch()..start();
      await tester.runAsync(vm.load);
      load.stop();
      final frame = Stopwatch()..start();
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: HistoryView(viewModel: vm),
      ));
      frame.stop();
      bench('history_load_1825', load.elapsed);
      bench('history_first_frame_1825', frame.elapsed);
      expect(vm.days.length, greaterThan(360));
      expect(frame.elapsed, lessThan(const Duration(seconds: 3)));
    });

    test('Saving tab load and the weekly report', () async {
      final ledger = InMemoryLedgerRepository(initial: year());
      final prefs = MemoryPreferencesStore();
      final vm = SavingsViewModel(
        repo: SavingsRepository(prefs, clock: () => now),
        ledger: ledger,
        rewards: RewardsRepository(prefs, clock: () => now),
        settings: InMemorySettingsRepository(
            const GuardrailSettings(dailyLimitFils: 8000)),
        clock: () => now,
      );
      final load = Stopwatch()..start();
      await vm.load();
      load.stop();
      final entries = await ledger.entries();
      final report = Stopwatch()..start();
      buildWeeklyReport(entries, Day.of(now), dailyLimitFils: 8000);
      report.stop();
      bench('savings_load_1825', load.elapsed);
      bench('weekly_report_1825', report.elapsed);
      expect(load.elapsed, lessThan(const Duration(seconds: 3)));
    });
  });
}
