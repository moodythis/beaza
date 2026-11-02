import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/ui/features/home/view_models/home_view_model.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime bh(int day, int hour) =>
    DateTime.utc(2026, 11, day, hour).subtract(kBahrainOffset);

ExtractionResult purchase(int fils, DateTime at, {String? ref}) =>
    ExtractionResult(
      status: ExtractionStatus.transaction,
      amountFils: fils,
      currency: 'BHD',
      type: TxnType.purchase,
      direction: TxDirection.outgoing,
      reference: ref,
      timestamp: at,
    );

/// Lets listener-triggered loads finish.
Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late InMemoryLedgerRepository ledger;
  late InMemorySettingsRepository settings;
  late HomeViewModel vm;

  setUp(() {
    ledger = InMemoryLedgerRepository(initial: [
      purchase(1000, bh(2, 8)),
      purchase(2000, bh(2, 10), ref: 'R1'),
      purchase(2000, bh(2, 10), ref: 'R1'), // duplicate copy
      purchase(9000, bh(1, 23)), // yesterday
    ]);
    settings = InMemorySettingsRepository(
        const GuardrailSettings(dailyLimitFils: 5000));
    vm = HomeViewModel(ledger: ledger, settings: settings, clock: () => bh(2, 12));
  });

  tearDown(() => vm.dispose());

  test('starts empty, then loads today only, newest first', () async {
    expect(vm.state, isNull);
    await vm.load();
    final s = vm.state!;
    expect(s.summary.spentFils, 3000);
    expect(s.today.map((e) => e.result.amountFils), [2000, 1000]);
    expect(s.summary.level, AlertLevel.level1);
    expect(s.weekMicro.count, 2);
    expect(vm.isLoading, isFalse);
  });

  test('a new expense reloads through the repository listener', () async {
    await vm.load();
    await vm.addExpense(amountFils: 2500, merchant: 'Bakery');
    await settle();
    expect(vm.state!.summary.spentFils, 5500);
    expect(vm.state!.summary.level, AlertLevel.level3);
    expect(vm.state!.today.first.result.merchantRaw, 'Bakery');
  });

  test('changing the limit keeps the other settings', () async {
    await vm.load();
    await vm.setDailyLimit(12000);
    await settle();
    expect(vm.state!.summary.limitFils, 12000);
    expect((await settings.load()).microThresholdFils, 5000);
  });

  test('manual amounts must be positive', () async {
    await expectLater(
        ledger.addManual(amountFils: 0, at: bh(2, 9)), throwsArgumentError);
  });
}
