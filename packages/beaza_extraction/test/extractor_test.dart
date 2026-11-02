import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:test/test.dart';

// End-to-end tests. Messages follow real Bahraini formats; names, balances
// and numbers are invented. Senders are the real sender IDs.
void main() {
  final x = BeazaExtractor();

  String sum(ExtractionResult r) =>
      '${r.status.name}|${r.type?.name}|${r.channel?.name}|${r.amountFils}|'
      '${r.currency}|${r.last4}|${r.merchantRaw}|'
      '${r.timestamp?.toIso8601String()}';

  ExtractionResult run(String sender, String text, DateTime received) =>
      x.process(RawMessage(text: text, sender: sender, receivedAt: received));

  test('BisB Fawri+ out', () {
    final r = run(
        'BisB',
        'Fawri+ payment BHD2.900, ref: BIB103KAA000AAAA was credited to IBAN ending 4411 on 2026/10/30 00:59. Balance BHD9.999. Tel: 17515151',
        DateTime.utc(2026, 10, 29, 22, 0));
    expect(sum(r),
        'transaction|transferOut|transfer|2900|BHD|null|null|2026-10-29T21:59:00.000Z');
  });

  test('BisB Fawri+ in', () {
    final r = run(
        'BisB',
        'Fawri+ payment BHD8.800 received from IBAN 5522 to IBAN 6633 ref. BIB103KAB000BBBB on 2026/10/25 06:15. Balance BHD9.999. Tel 17515151',
        DateTime.utc(2026, 10, 25, 3, 20));
    expect(sum(r),
        'transaction|transferIn|transfer|8800|BHD|6633|null|2026-10-25T03:15:00.000Z');
  });

  test('BisB card purchase, no year in the message', () {
    final r = run(
        'BisB',
        'Dear CLIENT, thank you for using your Debit card 7744 for BHD 0.300 at SAMPLE BAKERY - MAL BAH BH-000001 on 15/10 @16:31. Avail Bal BHD 9.999. Tel 17515151',
        DateTime.utc(2026, 10, 15, 13, 40));
    expect(sum(r),
        'transaction|purchase|card|300|BHD|7744|SAMPLE BAKERY - MAL BAH BH-000001|2026-10-15T13:31:00.000Z');
  });

  test('ila card purchase', () {
    final r = run(
        'ilabank',
        'Success! Purchase at SAMPLE TRADING CO W using card ****8855 for BHD 1.500 on 29/10/2026 15:42 debited from BHD Ac Balance BHD 9.999 Enquiry 17123456',
        DateTime.utc(2026, 10, 29, 12, 50));
    expect(sum(r),
        'transaction|purchase|card|1500|BHD|8855|SAMPLE TRADING CO W|2026-10-29T12:42:00.000Z');
  });

  test('ila promo sender name also maps to ila; &amp; is cleaned', () {
    final r = run(
        'ila Bank',
        'Success! Purchase at INFO &amp; SAMPLE AUTHOR using card ****8855 for BHD 5.000 on 14/10/2026 17:16 debited from BHD Ac Balance BHD 9.999 Enquiry 17123456',
        DateTime.utc(2026, 10, 14, 14, 20));
    expect(sum(r),
        'transaction|purchase|card|5000|BHD|8855|INFO & SAMPLE AUTHOR|2026-10-14T14:16:00.000Z');
  });

  test('Al Salam debit: usable, but the type stays unknown', () {
    final r = run(
        'AlSalamBank',
        'Dear Client, BHD 0.400 has been debited from your account XXXX10100777. Your balance is BHD 9.999 on 30/10/26 at 01:27. Thank you, Al Salam Bank.',
        DateTime.utc(2026, 10, 29, 22, 30));
    expect(sum(r),
        'transaction|null|null|400|BHD|0777|null|2026-10-29T22:27:00.000Z');
    expect(r.direction, TxDirection.outgoing);
  });

  test('BenefitPay notification: multi-line text and BD currency', () {
    final r = run(
        'BenefitPay',
        'FAWRI+ Payment - BD 0.1 received from: Test Person\nFrom IBAN: BH40ALSA**********0777\nTo IBAN: BH35BIBB**********6633\nReference no: 6200000001-BP1000000001TEST-R\nCredited on: 02/11/2026 21:02',
        DateTime.utc(2026, 11, 2, 18, 5));
    expect(sum(r),
        'transaction|transferIn|transfer|100|BHD|6633|null|2026-11-02T18:02:00.000Z');
    expect(r.toString().contains('Test Person'), false);
  });

  test('BenefitPay "was credited to": direction unknown goes to review', () {
    final r = run(
        'BenefitPay',
        'FAWRI+ Payment - BD 0.1 was credited to:.\nFrom IBAN: BH40ALSA**********0777\nTo IBAN: BH35BIBB**********6633\nTel: +00000000\nReference no: 6200000002-BP1000000001TEST\nCredited on: 02/11/2026 21:02',
        DateTime.utc(2026, 11, 2, 18, 5));
    expect(r.status, ExtractionStatus.unparsed);
    expect(r.issues, [ValidationIssue.directionUnknown]);
    expect(r.needsReview, true);
  });

  test('ila DECLINED is not a transaction', () {
    final r = run(
        'ilabank',
        'DECLINED. Your BHD account has insufficient funds. Please fund it and try again. Card ****8855 for BHD 1.500 on 29/10/2026 15:41 Enquiry 17123456',
        DateTime.utc(2026, 10, 29, 12, 45));
    expect(r.status, ExtractionStatus.nonTransaction);
    expect(r.kind, MessageKind.declined);
  });

  test('ila promotion is not a transaction', () {
    final r = run('ila Bank', 'Win Up to BHD 2,000 Cashback on your ila card',
        DateTime.utc(2026, 11, 2, 11, 14));
    expect(r.status, ExtractionStatus.nonTransaction);
    expect(r.kind, MessageKind.promotion);
  });

  test('OTP from a bank is not a transaction', () {
    final r = run('BisB', 'Your OTP for card payment BHD 5.000 at SHOP is 123456. Do not share it.',
        DateTime.utc(2026, 11, 2, 11, 14));
    expect(r.kind, MessageKind.otp);
    expect(r.amountFils, null);
  });

  test('Unknown bank message from a supported sender goes to review', () {
    final r = run('BisB', 'Hello from your bank', DateTime.utc(2026, 11, 2, 11, 14));
    expect(r.status, ExtractionStatus.unparsed);
    expect(r.issues, [ValidationIssue.unclassified]);
  });

  test('Transaction text with no template goes to review', () {
    final r = run(
        'BisB',
        'ATM withdrawal of BHD 20.000 from card 7744 on 01/11/2026 10:00',
        DateTime.utc(2026, 11, 1, 7, 5));
    expect(r.status, ExtractionStatus.unparsed);
    expect(r.issues, [ValidationIssue.noTemplate]);
  });

  test('Privacy: messages from other senders are dropped unread', () {
    final r = run(
        'ZainBH',
        'Dear Customer, Your outgoing calls have been restricted. Pay BHD 5.000 payment now',
        DateTime.utc(2026, 11, 2, 11, 14));
    expect(r.status, ExtractionStatus.nonTransaction);
    expect(r.kind, null);
    expect(r.amountFils, null);
  });

  test('Unknown sender can be allowed for evaluation runs', () {
    final eval = BeazaExtractor(requireKnownSender: false);
    final r = eval.process(RawMessage(
        text:
            'Fawri+ payment BHD2.900, ref: BIB103KAA000AAAA was credited to IBAN ending 4411 on 2026/10/30 00:59. Balance BHD9.999. Tel: 17515151',
        sender: 'SomethingElse',
        receivedAt: DateTime.utc(2026, 10, 29, 22, 0)));
    expect(r.status, ExtractionStatus.transaction);
    expect((r.confidence * 1000).round(), 900);
  });

  test('The same message twice gives the same result (no hidden state)', () {
    const text =
        'Success! Fawri+ transfer of BHD 50.000 from IBAN ****0777 credited to BHD Ac on 02/11/2026 12:11 Ref ALS103KAC000CCCC Balance BHD 9.999 Enquiry 17123456';
    final t = DateTime.utc(2026, 11, 2, 9, 15);
    expect(sum(run('ilabank', text, t)), sum(run('ilabank', text, t)));
    expect(sum(run('ilabank', text, t)),
        'transaction|transferIn|transfer|50000|BHD|null|null|2026-11-02T09:11:00.000Z');
  });
}
