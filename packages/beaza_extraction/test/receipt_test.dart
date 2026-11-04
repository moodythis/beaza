// The receipts below are SYNTHETIC, written in the shapes receipts and OCR
// output usually take. No real receipt has been collected yet; add real
// (masked) ones here as they arrive and fix what they show.
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:test/test.dart';

void main() {
  const r = ReceiptReader();
  final now = DateTime.utc(2026, 11, 4, 9); // 12:00 in Bahrain

  test('a cafe receipt: total, shop, category, printed time', () {
    final x = r.read('''
SAMPLE CAFE W.L.L
Seef Mall, Manama
TAX INVOICE
VAT No 200000000000002
Date: 03/11/2026  Time: 14:32
Latte            1.800
Croissant        1.200
Sub Total        3.000
VAT 10%          0.300
TOTAL BHD        3.300
CASH             5.000
CHANGE           1.700
Thank you
''', now: now);
    expect(x.status, ExtractionStatus.transaction);
    expect(x.amountFils, 3300);
    expect(x.currency, 'BHD');
    expect(x.merchantRaw, 'SAMPLE CAFE W.L.L');
    expect(x.merchantNorm, 'Sample Cafe');
    expect(x.category, 'food');
    expect(x.timestamp, DateTime.utc(2026, 11, 3, 11, 32));
    expect(x.flags, isEmpty);
    expect(x.confidence, 0.9);
  });

  test('labels and amounts in separate columns', () {
    final x = r.read('''
LULU HYPERMARKET
Bahrain
TOTAL
NET AMOUNT
BD
12.450
''', now: now);
    expect(x.amountFils, 12450);
    expect(x.merchantNorm, 'Lulu');
    expect(x.category, 'groceries');
    expect(x.confidence, 0.8);
    expect(x.flags, contains(ExtractionFlag.timestampFromReceipt));
  });

  test('the total including VAT is not skipped as a VAT line', () {
    final x = r.read('SHOP\nSub Total 5.000\nVAT 0.500\nTotal incl. VAT 5.500\n', now: now);
    expect(x.amountFils, 5500);
  });

  test('Arabic labels and Arabic-Indic digits', () {
    final x = r.read('صيدلية النموذج\nالإجمالي ١٢٫٥٠٠ د.ب\n', now: now);
    expect(x.amountFils, 12500);
    expect(x.category, 'health');
    expect(x.currency, 'BHD');
  });

  test('no total line: the largest amount, marked as a guess', () {
    final x = r.read('SAMPLE PHARMACY\n2.750\n0.250\n', now: now);
    expect(x.amountFils, 2750);
    expect(x.confidence, 0.4);
    expect(x.flags, containsAll([ExtractionFlag.totalGuessed, ExtractionFlag.currencyAssumed]));
  });

  test('cash given and change are never taken as the total', () {
    final x = r.read('SHOP\nCASH 20.000\nCHANGE 15.000\n4.500\n', now: now);
    expect(x.amountFils, 4500);
  });

  test('a foreign currency is flagged', () {
    final x = r.read('SAMPLE STORE\nTotal USD 22.00\n', now: now);
    expect(x.amountFils, 22000);
    expect(x.currency, 'USD');
    expect(x.flags, contains(ExtractionFlag.foreignCurrency));
  });

  test('a date that is not a price, and a misread date far away', () {
    final x = r.read('SHOP\n03.11.2026\nTOTAL 1.500\n', now: now);
    expect(x.amountFils, 1500);
    expect(x.timestamp, DateTime.utc(2026, 11, 3, 9));
    final far = r.read('SHOP\n03/11/2019 10:00\nTOTAL 1.500\n', now: now);
    expect(far.flags, contains(ExtractionFlag.timestampFromReceipt));
  });

  test('pm times', () {
    final x = r.read('SHOP\n2026-11-03 08:15 PM\nTOTAL 1.500\n', now: now);
    expect(x.timestamp, DateTime.utc(2026, 11, 3, 17, 15));
  });

  test('nothing that looks like an amount', () {
    final x = r.read('SAMPLE SHOP\nThank you for visiting\n', now: now);
    expect(x.status, ExtractionStatus.unparsed);
    expect(x.amountFils, isNull);
    expect(x.merchantRaw, 'SAMPLE SHOP');
  });
}
