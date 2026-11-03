import 'dart:convert';

import 'package:beaza/app.dart';
import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/seen_message_store.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/data/services/device_service.dart';
import 'package:beaza/domain/use_cases/data_export.dart';
import 'package:beaza/domain/use_cases/message_intake.dart';
import 'package:beaza/ui/features/home/view_models/home_view_model.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'account_view_test.dart' show FakeAccounts;
import 'message_intake_test.dart' as fixtures;

class FakeDevice implements DeviceService {
  bool? restricted = true;
  int settingsOpened = 0;

  /// What [saveText] answers: true saved, false cancelled, null throws.
  bool? saveAnswer = true;
  final saved = <String, String>{};

  @override
  Future<bool?> batteryRestricted() async => restricted;

  @override
  Future<void> openAppSettings() async => settingsOpened++;

  @override
  Future<bool> saveText({
    required String fileName,
    required String text,
  }) async {
    final answer = saveAnswer;
    if (answer == null) throw Exception('disk full');
    if (answer) saved[fileName] = text;
    return answer;
  }
}

DateTime bh(int day, int hour) =>
    DateTime.utc(2026, 11, day, hour).subtract(kBahrainOffset);

ExtractionResult card(int fils, DateTime at) => ExtractionResult(
      status: ExtractionStatus.transaction,
      amountFils: fils,
      currency: 'BHD',
      type: TxnType.purchase,
      direction: TxDirection.outgoing,
      merchantRaw: 'Cafe',
      channel: Channel.card,
      last4: '1234',
      timestamp: at,
      confidence: 0.9,
      templateVersion: 'bisb.card@1',
    );

void main() {
  group('data export', () {
    late InMemoryLedgerRepository ledger;
    late FakeDevice device;
    late DataExport export;

    setUp(() {
      ledger = InMemoryLedgerRepository(initial: [card(1250, bh(3, 9))]);
      device = FakeDevice();
      export = DataExport(
        ledger: ledger,
        settings: InMemorySettingsRepository(
            const GuardrailSettings(dailyLimitFils: 7000)),
        device: device,
        // 23:30 on 3 Nov in Bahrain is still 3 Nov there, 20:30 UTC.
        clock: () => bh(3, 23).add(const Duration(minutes: 30)),
      );
    });

    test('holds every transaction and the settings, money without floats',
        () async {
      await ledger.addManual(amountFils: 500, merchant: 'Bakery', at: bh(3, 10));
      final data = await export.build();
      expect(data['format'], 'beaza-export');
      expect(data['version'], 1);
      expect((data['settings']! as Map)['dailyLimitFils'], 7000);

      final txns = (data['transactions']! as List).cast<Map<String, Object?>>();
      expect(txns, hasLength(2));
      final first = txns.firstWhere((t) => t['source'] == 'message');
      expect(first['amountFils'], 1250);
      expect(first['amount'], '1.250');
      expect(first['merchant'], 'Cafe');
      expect(first['channel'], 'card');
      expect(first['cardLast4'], '1234');
      expect(first['role'], 'spending');
      expect(first['countsTowardSpending'], isTrue);
      expect(first['time'], '2026-11-03T06:00:00.000Z');
      final manual = txns.firstWhere((t) => t['source'] == 'manual');
      expect(manual['amount'], '0.500');
    });

    test('amount text keeps three decimals', () {
      expect(DataExport.amountText(0), '0.000');
      expect(DataExport.amountText(5), '0.005');
      expect(DataExport.amountText(1000), '1.000');
      expect(DataExport.amountText(-1250), '-1.250');
    });

    test('saves one JSON file named after the Bahrain date', () async {
      expect(await export.save(), isTrue);
      final text = device.saved['beaza-export-2026-11-03.json']!;
      final decoded = jsonDecode(text) as Map<String, Object?>;
      expect((decoded['transactions']! as List), hasLength(1));
    });

    test('cancelling the save dialog saves nothing', () async {
      device.saveAnswer = false;
      expect(await export.save(), isFalse);
      expect(device.saved, isEmpty);
    });
  });

  group('battery saving', () {
    HomeViewModel viewModel(FakeDevice device, {bool sms = true}) {
      final ledger = InMemoryLedgerRepository();
      final smsSource = fixtures.FakeSms([])..granted = sms;
      return HomeViewModel(
        ledger: ledger,
        settings: InMemorySettingsRepository(
            const GuardrailSettings(dailyLimitFils: 5000)),
        intake: MessageIntake(
          sms: smsSource,
          ledger: ledger,
          seen: MemorySeenMessageStore(),
          clock: () => bh(3, 12),
        ),
        device: device,
        clock: () => bh(3, 12),
      );
    }

    test('is checked with the messages, and cleared when lifted', () async {
      final device = FakeDevice();
      final vm = viewModel(device);
      addTearDown(vm.dispose);
      await vm.checkMessages();
      expect(vm.batteryRestricted, isTrue);

      device.restricted = false;
      await vm.checkMessages();
      expect(vm.batteryRestricted, isFalse);

      device.restricted = null;
      await vm.checkMessages();
      expect(vm.batteryRestricted, isFalse, reason: 'unknown is not shown');
    });

    testWidgets('the home card appears only when SMS reading is on, and '
        'opens the settings', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final device = FakeDevice();
      final vm = viewModel(device);
      await vm.load();
      await vm.checkMessages();
      await tester.pumpWidget(
          BeazaApp(homeViewModel: vm, locale: const Locale('en')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('batteryCard')), findsOneWidget);
      await tester.tap(find.byKey(const Key('batteryOpen')));
      expect(device.settingsOpened, 1);

      device.restricted = false;
      await vm.checkMessages();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('batteryCard')), findsNothing);
    });

    testWidgets('no card without SMS reading (it would not help)',
        (tester) async {
      final vm = viewModel(FakeDevice(), sms: false);
      await vm.load();
      await vm.checkMessages();
      await tester.pumpWidget(
          BeazaApp(homeViewModel: vm, locale: const Locale('en')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('batteryCard')), findsNothing);
      expect(find.byKey(const Key('smsCard')), findsOneWidget);
    });
  });

  group('export on the account screen', () {
    Future<FakeDevice> open(WidgetTester tester, {required bool signedIn}) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final device = FakeDevice();
      final ledger = InMemoryLedgerRepository(initial: [card(1250, bh(3, 9))]);
      final settings = InMemorySettingsRepository();
      final vm = HomeViewModel(
        ledger: ledger,
        settings: settings,
        export: DataExport(ledger: ledger, settings: settings, device: device),
      );
      await vm.load();
      final accounts = FakeAccounts();
      if (signedIn) accounts.signIn('me@example.com');
      await tester.pumpWidget(BeazaApp(
          homeViewModel: vm, locale: const Locale('en'), account: accounts));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('accountButton')));
      await tester.pumpAndSettle();
      return device;
    }

    for (final signedIn in [false, true]) {
      testWidgets('saves the file (signed ${signedIn ? 'in' : 'out'})',
          (tester) async {
        final device = await open(tester, signedIn: signedIn);
        expect(find.byKey(const Key('exportCard')), findsOneWidget);
        await tester.tap(find.byKey(const Key('exportButton')));
        await tester.pumpAndSettle();
        expect(device.saved, hasLength(1));
        expect(find.text('Your data was saved'), findsOneWidget);
      });
    }

    testWidgets('a failed save is shown; a cancelled one is not',
        (tester) async {
      final device = await open(tester, signedIn: false);
      device.saveAnswer = null;
      await tester.tap(find.byKey(const Key('exportButton')));
      await tester.pumpAndSettle();
      expect(find.text('Could not save the file'), findsOneWidget);

      ScaffoldMessenger.of(tester.element(find.byKey(const Key('exportCard'))))
          .clearSnackBars();
      await tester.pumpAndSettle();
      device.saveAnswer = false;
      await tester.tap(find.byKey(const Key('exportButton')));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
