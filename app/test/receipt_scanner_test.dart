// The native part (camera, ML Kit, deleting the temporary photo in
// MainActivity.kt) cannot run in `flutter test`; it is checked on a phone.
// Here: what happens to the text, the duplicate check and the review sheet.
import 'package:beaza/app.dart';
import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/data/services/receipt_scanner.dart';
import 'package:beaza/domain/use_cases/same_payment.dart';
import 'package:beaza/ui/features/home/view_models/home_view_model.dart';
import 'package:beaza/ui/features/receipt/view_models/receipt_view_model.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeScanner implements ReceiptScanner {
  FakeScanner(this.text, {this.failCode});
  final String? text;
  final String? failCode;
  final List<ReceiptSource> sources = [];

  @override
  Future<String?> scan(ReceiptSource source) async {
    sources.add(source);
    if (failCode != null) throw PlatformException(code: failCode!);
    return text;
  }
}

final DateTime now = DateTime.utc(2026, 11, 4, 9); // 12:00 in Bahrain

// 3 Nov 2026, 14:32 in Bahrain = 11:32 UTC.
const cafe = '''SAMPLE CAFE W.L.L
Date: 03/11/2026  Time: 14:32
Latte            1.800
Croissant        1.500
TOTAL BHD        3.300
''';

ExtractionResult sms(int fils, DateTime at) => ExtractionResult(
      status: ExtractionStatus.transaction,
      amountFils: fils,
      currency: 'BHD',
      type: TxnType.purchase,
      direction: TxDirection.outgoing,
      merchantRaw: 'SAMPLE CAFE MANAMA',
      reference: 'R$fils',
      timestamp: at,
    );

void main() {
  group('ReceiptViewModel', () {
    test('a read receipt goes to review, then saves what was confirmed',
        () async {
      final ledger = InMemoryLedgerRepository();
      final vm = ReceiptViewModel(
          scanner: FakeScanner(cafe), ledger: ledger, clock: () => now);
      await vm.scan(ReceiptSource.camera);
      expect(vm.step, ReceiptStep.review);
      expect(vm.result!.amountFils, 3300);
      expect(vm.duplicate, isNull);

      await vm.save(amountFils: 3300, merchant: 'Sample Cafe', category: 'food');
      expect(vm.step, ReceiptStep.saved);
      final saved = (await ledger.entries()).single.result;
      expect(saved.amountFils, 3300);
      expect(saved.category, 'food');
      expect(saved.timestamp, DateTime.utc(2026, 11, 3, 11, 32));
    });

    test('the same payment already read from a bank SMS is found', () async {
      final ledger = InMemoryLedgerRepository(initial: [
        sms(3300, DateTime.utc(2026, 11, 3, 11, 33)),
      ]);
      final vm = ReceiptViewModel(
          scanner: FakeScanner(cafe), ledger: ledger, clock: () => now);
      await vm.scan(ReceiptSource.gallery);
      expect(vm.duplicate, isNotNull);
      expect(vm.duplicate!.result.amountFils, 3300);
    });

    test('cancelled: back to the choice; a failure keeps its code', () async {
      final ledger = InMemoryLedgerRepository();
      final cancelled = ReceiptViewModel(
          scanner: FakeScanner(null), ledger: ledger, clock: () => now);
      await cancelled.scan(ReceiptSource.camera);
      expect(cancelled.step, ReceiptStep.choose);

      final failed = ReceiptViewModel(
          scanner: FakeScanner(null, failCode: 'no_camera'),
          ledger: ledger,
          clock: () => now);
      await failed.scan(ReceiptSource.camera);
      expect(failed.step, ReceiptStep.failed);
      expect(failed.error, 'no_camera');
      expect(await ledger.entries(), isEmpty);
    });
  });

  group('likelySamePayment', () {
    LedgerEntry? check(ExtractionResult receipt, List<ExtractionResult> existing) =>
        likelySamePayment(
            const Reconciler().reconcile(existing, OwnAccounts()), receipt);

    final receipt = sms(3300, DateTime.utc(2026, 11, 3, 11, 32));

    test('same amount within 30 minutes', () {
      expect(check(receipt, [sms(3300, DateTime.utc(2026, 11, 3, 11, 50))]),
          isNotNull);
      expect(check(receipt, [sms(3300, DateTime.utc(2026, 11, 3, 13, 0))]),
          isNull);
      expect(check(receipt, [sms(3400, DateTime.utc(2026, 11, 3, 11, 32))]),
          isNull);
    });

    test('a receipt with no printed time matches the same day', () {
      final noTime = ExtractionResult(
        status: ExtractionStatus.transaction,
        amountFils: 3300,
        currency: 'BHD',
        timestamp: DateTime.utc(2026, 11, 3, 18),
        flags: const [ExtractionFlag.timestampFromReceipt],
      );
      expect(check(noTime, [sms(3300, DateTime.utc(2026, 11, 3, 6))]), isNotNull);
      expect(check(noTime, [sms(3300, DateTime.utc(2026, 11, 2, 6))]), isNull);
    });
  });

  group('review sheet', () {
    Future<InMemoryLedgerRepository> open(WidgetTester tester, ReceiptScanner scanner,
        {List<ExtractionResult> initial = const []}) async {
      final ledger = InMemoryLedgerRepository(initial: initial);
      final vm = HomeViewModel(
        ledger: ledger,
        settings: InMemorySettingsRepository(
            const GuardrailSettings(dailyLimitFils: 10000)),
        receipts: scanner,
        clock: () => now,
      );
      await vm.load();
      await tester.pumpWidget(BeazaApp(homeViewModel: vm));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('addReceipt')));
      await tester.pumpAndSettle();
      return ledger;
    }

    testWidgets('pick a picture, check the amount, add', (tester) async {
      final scanner = FakeScanner(cafe);
      final ledger = await open(tester, scanner);
      await tester.tap(find.byKey(const Key('receiptGallery')));
      await tester.pumpAndSettle();
      expect(scanner.sources, [ReceiptSource.gallery]);
      String field(String key) =>
          tester.widget<TextField>(find.byKey(Key(key))).controller!.text;
      expect(field('receiptAmount'), '3.300');
      expect(field('receiptShop'), 'Sample Cafe');
      expect(find.byKey(const Key('receiptDuplicate')), findsNothing);

      await tester.enterText(find.byKey(const Key('receiptAmount')), '3.500');
      await tester.ensureVisible(find.byKey(const Key('receiptSave')));
      await tester.tap(find.byKey(const Key('receiptSave')));
      await tester.pumpAndSettle();
      expect((await ledger.entries()).single.result.amountFils, 3500);
      expect(find.byKey(const Key('receiptAmount')), findsNothing);
    });

    testWidgets('a payment already in the ledger is pointed out',
        (tester) async {
      await open(tester, FakeScanner(cafe),
          initial: [sms(3300, DateTime.utc(2026, 11, 3, 11, 33))]);
      await tester.tap(find.byKey(const Key('receiptCamera')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('receiptDuplicate')), findsOneWidget);
      expect(find.text('Add anyway'), findsOneWidget);
    });

    testWidgets('a receipt in another currency cannot be added',
        (tester) async {
      await open(tester, FakeScanner('SAMPLE STORE\nTotal USD 22.00\n'));
      await tester.tap(find.byKey(const Key('receiptGallery')));
      await tester.pumpAndSettle();
      final save = tester.widget<FilledButton>(find.byKey(const Key('receiptSave')));
      expect(save.onPressed, isNull);
    });

    testWidgets('a bad amount is refused', (tester) async {
      final ledger = await open(tester, FakeScanner('SAMPLE SHOP\nThank you\n'));
      await tester.tap(find.byKey(const Key('receiptGallery')));
      await tester.pumpAndSettle();
      expect(find.text('No amount found. Type it from the receipt.'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('receiptSave')));
      await tester.tap(find.byKey(const Key('receiptSave')));
      await tester.pumpAndSettle();
      expect(find.text('Type a valid amount'), findsOneWidget);
      expect(await ledger.entries(), isEmpty);
    });
  });
}
