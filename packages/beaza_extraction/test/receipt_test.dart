// Most receipts below are SYNTHETIC, written in the shapes receipts and OCR
// output usually take. Two REAL ones (a games shop, 3 November 2026) are
// marked as such; add more real (masked) ones as they arrive and fix what
// they show.
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

  // The first REAL receipt (4 November 2026, a children's games shop, card
  // payment). Only the shop name, date, time and amounts are kept here. The
  // till prints the date month first; the labels and amounts come out of OCR
  // in two columns.
  group('a real receipt: month-first date, labels and amounts apart', () {
    const columns = '''
KIDS PORT GAMES
CR: 86184-2
Garden 55
Invoice No.
Date
11/03/2026 10:59 PM
#1. Yellow Ticket
1.000 x 0.300
0.300
Subtotal:
Total:
Card (11/03/2026)
Total Paid
BD 0.300
BD 0.300
BD 0.300
BD 0.300
''';
    const rows = '''
KIDS PORT GAMES
Date 11/03/2026 10:59 PM
#1. Yellow Ticket
1.000 x 0.300 0.300
Subtotal: BD 0.300
Total: BD 0.300
Card (11/03/2026) BD 0.300
Total Paid BD 0.300
''';
    for (final (name, text) in [('columns', columns), ('rows', rows)]) {
      test(name, () {
        final x = r.read(text, now: now);
        expect(x.status, ExtractionStatus.transaction);
        expect(x.amountFils, 300);
        expect(x.currency, 'BHD');
        expect(x.merchantRaw, 'KIDS PORT GAMES');
        // 3 November 2026, 22:59 in Bahrain.
        expect(x.timestamp, DateTime.utc(2026, 11, 3, 19, 59));
        expect(x.flags, isEmpty);
      });
    }
  });

  test('day first stays the default when both readings fit', () {
    // 05/11/2026 on 6 November: 5 November, not 11 May.
    final x = r.read('SHOP\n05/11/2026 10:00\nTOTAL 1.500\n',
        now: DateTime.utc(2026, 11, 6, 9));
    expect(x.timestamp, DateTime.utc(2026, 11, 5, 7));
    // Both readings are old: day first.
    final old = r.read('SHOP\n04/03/2026 10:00\nTOTAL 1.500\n', now: now);
    expect(old.timestamp, DateTime.utc(2026, 3, 4, 7));
  });

  test('the second real receipt: labels misread, the repeated amount is the total', () {
    // 4 November 2026, same shop, two items. The photo was taken at an angle
    // and the app found no "total" line: it took 8.000 (a quantity) instead
    // of 1.100. Labels are misspelt below to stand for that.
    final x = r.read('''
KIDS PORT GAMES
Date 11/03/2026 10:56 PM
#1. SmallFrisc
1.000 x 0.300
0.300
#2. Snacks
8.000 x 0.100
0.800
Subtotai:
Totai:
Card (11/03/2026)
Totai Paid
BD 1.100
BD 1.100
BD 1.100
BD 1.100
''', now: now);
    expect(x.amountFils, 1100);
    expect(x.timestamp, DateTime.utc(2026, 11, 3, 19, 56));
    expect(x.merchantRaw, 'KIDS PORT GAMES');
    expect(x.flags, contains(ExtractionFlag.totalGuessed));
  });

  test('a quantity line is never taken as the total', () {
    final x = r.read('SHOP\n2.000 x 0.500\n1.000\n', now: now);
    expect(x.amountFils, 1000);
  });

  // 20 SYNTHETIC samples written by another AI to look like the OCR text of
  // Bahraini payment screens, card slips and receipts (nothing here is a
  // real person's data). Checked: amount, shop, currency, the cash trap, a
  // printed date, and that a failed payment or a timetable gives no amount.
  // Not built (the reader does not need them): VAT and line-item fields, a
  // line-item sum check, channel and last four digits.
  group('20 synthetic Bahraini samples', () {
    void check(
      String name,
      String text, {
      int? amount,
      Object? shop,
      String currency = 'BHD',
      ExtractionStatus status = ExtractionStatus.transaction,
      List<ExtractionFlag> noFlags = const [],
    }) {
      test(name, () {
        final x = r.read(text, now: now);
        expect(x.status, status);
        expect(x.amountFils, amount);
        if (status == ExtractionStatus.transaction) {
          expect(x.currency, currency);
          if (shop != null) expect(x.merchantRaw, shop);
        }
        for (final f in noFlags) {
          expect(x.flags, isNot(contains(f)));
        }
      });
    }

    check('1 BenefitPay Fawri+ transfer: no name leaks into the shop', '''
BenefitPay
Transaction Approved
FAWRI+ Payment
BHD 4.500
Paid to: AHMED ALI HUSAIN
Mobile Number: +973 39123456
From IBAN: BH35BIBB00000012347204
To IBAN: BH40ALSA00000011110000
Reference No: 6234022698-BP1793642549H31K
Date & Time: 04/11/2026 14:22:10
Remarks: Lunch split
''', amount: 4500, shop: isNull);

    check('2 BenefitPay merchant QR: shop from its label', '''
BenefitPay
Payment Successful
Merchant Payment
BHD 0.600
Merchant Name: KARAK EXPRESS CAFE
Merchant ID: 00982341
Paid By: BenefitPay Wallet
Account / Card: BH35BIBB**********7204
Reference No: 8839201928-BP9928374610M12A
04/11/2026 08:15 AM
''', amount: 600, shop: 'KARAK EXPRESS CAFE');

    check('3 BenefitPay Fawri+ in Arabic', '''
بنفت بي
عملية ناجحة
تحويل فوري+
12.000 د.ب
اسم المستلم: محمد جاسم عبدالله
من حساب: BH77NBOB00000099881122
إلى حساب: BH21BBKU00000055447788
رقم المرجع: 1122334455-BP5544332211K99Z
التاريخ والوقت: 03/11/2026 21:40
''', amount: 12000, shop: isNull);

    check('4 BenefitPay bill (Zain): the biller is the shop', '''
BenefitPay
Fawateer Payment
Transaction Successful
BHD 11.550
Biller: ZAIN BAHRAIN B.S.C
Service: Postpaid Mobile
Subscriber No: 36000000
From Card/IBAN: **** 5517
Reference No: FT263089912344
Date: 01/11/2026 19:05
''', amount: 11550, shop: 'ZAIN BAHRAIN B.S.C');

    test('5 ila Bank transfer: a date written with a month name', () {
      final x = r.read('''
ila Bank
Transfer Completed!
BHD 25.000
Transfer Type: Fawri+
To: HASSAN AHMED
To IBAN: BH62ILAB00000011228400
From Account: BHD Account (****3381)
Reference: ILA103KAR0098123
Date: 03 Nov 2026, 16:30
''', now: now);
      expect(x.amountFils, 25000);
      expect(x.timestamp, DateTime.utc(2026, 11, 3, 13, 30));
      expect(x.flags, isNot(contains(ExtractionFlag.timestampFromReceipt)));
    });

    check('6 NBB app: the "Amount:" line', '''
NBB Digital Banking
Transaction Successful
Amount: BHD 7.250
Transfer Type: Fawri+ Payment
From Account: 0012-345678-001 (ending 8001)
Beneficiary Name: ALI SALMAN
Beneficiary IBAN: BH11NBOB00000012349900
Transaction Reference: NBB2026110488219
Date: 04/11/2026 11:12
''', amount: 7250, noFlags: [ExtractionFlag.totalGuessed]);

    check('7 BisB app in Arabic', '''
بنك البحرين الإسلامي BisB
تمت عملية التحويل بنجاح
المبلغ: BHD 15.500
الخدمة: فوري+
من الحساب المنتهي بـ: 7204
إلى الآيبان المنتهي بـ: 5476
رقم المرجع: BIB103KAN0099881
التاريخ: 2026/11/02 18:45
''', amount: 15500);

    check('8 AFS slip: the shop is not the card company', '''
AFS - ARAB FINANCIAL SERVICES
AL JAZIRA SUPERMARKET
ZINJ - BAHRAIN
TID: 88210492   MID: 001928374
DATE: 04/11/26  TIME: 13:45:22
VISA DEBIT      CONTACTLESS
CARD: **** **** **** 5517
PURCHASE
AMOUNT:         BHD 3.450
APPROVED        AUTH: 849201
RRN: 630813849201
THANK YOU
CUSTOMER COPY
''', amount: 3450, shop: 'AL JAZIRA SUPERMARKET', noFlags: [ExtractionFlag.totalGuessed]);

    check('9 CrediMax slip', '''
CREDIMAX BAHRAIN
COSTA COFFEE - SEEF MALL
TERM ID: 44109281
03/11/2026      17:20
MASTERCARD      ****8823
SALE
TOTAL           BD 1.800
TRANSACTION APPROVED
REF NO: 004918273612
AUTH CODE: 192834
''', amount: 1800, shop: 'COSTA COFFEE - SEEF MALL');

    check('10 petrol station slip: unit price and volume are not the total', '''
BAPCO TAZWEED
HAMAD TOWN SERVICE STATION
02/11/2026 22:10
PRODUCT: MUMTAZ 95
VOLUME: 30.00 L
UNIT PRICE: 0.200 BHD
TOTAL AMOUNT: BHD 6.000
PAID BY: BENEFIT DEBIT **** 7204
RRN: 991827364510
APPROVED
''', amount: 6000, shop: 'BAPCO TAZWEED');

    check('11 hypermarket with items and VAT', '''
LULU HYPERMARKET - RIFFA
VAT REG NO: 200000123400002
DATE: 04/11/2026 15:10
RECEIPT NO: 98122
--------------------------------
1. AWAL MILK 1L          0.600
2. CHICKEN BREAST 1KG    2.400
3. ARABIC BREAD          0.100
4. WATER 6x1.5L          0.900
--------------------------------
SUBTOTAL (EXCL VAT)      4.000
VAT 10%                  0.400
NET TOTAL BHD            4.400
--------------------------------
VISA CARD **** 5517      4.400
''', amount: 4400, shop: 'LULU HYPERMARKET - RIFFA');

    check('12 restaurant: cash tendered and change are not the total', '''
AL SHOALA RESTAURANT
HAMAD TOWN, BAHRAIN
TRN: 200009876500002
03/11/2026 20:15
--------------------------------
2 SHAWARMA SAROOKH       1.400
1 PEPSI CAN              0.250
--------------------------------
TOTAL (INCL 10% VAT)     1.650 BHD
VAT AMOUNT (10%)         0.150 BHD
CASH TENDERED            5.000 BHD
CHANGE DUE               3.350 BHD
THANK YOU FOR VISITING
''', amount: 1650, shop: 'AL SHOALA RESTAURANT', noFlags: [ExtractionFlag.totalGuessed]);

    check('13 specialty cafe, bilingual', '''
ROAST SPECIALTY COFFEE
مقهى روست المختص
Manama, Bahrain
Date: 04/11/2026 10:05
1x Iced Spanish Latte    2.200
1x Cheese Croissant      1.100
Subtotal                 3.000
VAT (10%)                0.300
Total Due              BHD 3.300
Payment Method: BenefitPay QR
''', amount: 3300, shop: 'ROAST SPECIALTY COFFEE');

    check('14 cold store in Arabic: paid and change are not the total', '''
برادة النورين
مدينة حمد - الدوار 10
التاريخ: 2026/11/04 16:00
--------------------------------
لبن المراعي               0.450
خبز رقاق                  0.500
بطاطس ليز                 0.300
--------------------------------
الإجمالي المطلوب:          1.250 د.ب
المدفوع نقداً:             2.000 د.ب
الباقي للعميل:             0.750 د.ب
''', amount: 1250, shop: 'برادة النورين');

    check('15 pharmacy with 0% VAT', '''
AL ROYAN PHARMACY
ISA TOWN, BAHRAIN
Date: 02/11/2026 19:30
1x PANADOL ADVANCE       0.850
1x VITAMIN C 1000MG      3.350
VAT (0% ZERO RATED)      0.000
TOTAL                  BHD 4.200
PAID CARD ****8823
''', amount: 4200, shop: 'AL ROYAN PHARMACY');

    check('16 Talabat order: delivery and service fees are inside the total', '''
talabat
Order Receipt #99481203
Restaurant: Chicket - Riffa
01/11/2026 at 22:40
1x Twister Meal          BHD 2.100
1x Garlic Mayo           BHD 0.200
Subtotal                 BHD 2.300
Delivery Fee             BHD 0.600
Service Fee              BHD 0.150
Total                    BHD 3.050
Paid with: BenefitPay
''', amount: 3050, shop: 'Chicket - Riffa');

    // The printed total is used even when the items add up to less.
    check('17 items do not add up to the total: the printed total is kept', '''
ALOSRA SUPERMARKET
SAAR, BAHRAIN
04/11/2026 12:00
1. ORANGE JUICE          1.200
2. BAKERY ITEM           0.600
--------------------------------
TOTAL BHD                2.100
CARD **** 5517
''', amount: 2100, shop: 'ALOSRA SUPERMARKET');

    test('18 Saudi riyals are flagged as a foreign currency', () {
      final x = r.read('''
JARIR BOOKSTORE - AL KHOBAR KSA
DATE: 01/11/2026 18:20
1x USB-C HUB ADAPTER     130.43
VAT 15%                   19.57
TOTAL                   SAR 150.00
VISA CARD **** 5517
''', now: now);
      expect(x.currency, 'SAR');
      expect(x.amountFils, 150000);
      expect(x.flags, contains(ExtractionFlag.foreignCurrency));
    });

    test('19 a declined payment is not a purchase and has no amount', () {
      final x = r.read('''
BenefitPay
Transaction Failed / Declined
FAWRI+ Payment
BHD 15.000
Reason: Insufficient Funds / الرصيد غير كاف
From IBAN: BH35BIBB**********7204
Date: 04/11/2026 14:20
''', now: now);
      expect(x.status, ExtractionStatus.nonTransaction);
      expect(x.kind, MessageKind.declined);
      expect(x.amountFils, isNull);
    });

    test('20 a university timetable gives no amount', () {
      final x = r.read('''
University of Bahrain
ITCS 389 - Software Engineering
Assignment 2 Submission Deadline
Room S40-1021 at 10:00 AM
Total Marks: 20
''', now: now);
      expect(x.status, ExtractionStatus.unparsed);
      expect(x.amountFils, isNull);
    });
  });
}
