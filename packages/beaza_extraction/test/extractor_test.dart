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
    final r = run('BisB', 'Your card purchase was successful', DateTime.utc(2026, 11, 2, 11, 14));
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

  group('formats found on the review screen (values invented)', () {
    test('BisB card in US dollars: a transaction flagged as foreign', () {
      final r = run(
          'BisB',
          'Dear CLIENT, thank you for using your Debit card 7744 for USD 22.00 at GOOGLE *SAMPLE APP g #US-000001 on 02/11 @16:19. Avail Bal BHD 99.999. Tel 17515151',
          DateTime.utc(2026, 11, 2, 13, 20));
      expect(r.status, ExtractionStatus.transaction);
      expect(r.currency, 'USD');
      expect(r.flags, contains(ExtractionFlag.foreignCurrency));
      expect(r.amountFils, 22000);
      expect(r.last4, '7744');
      expect(r.merchantRaw, 'GOOGLE *SAMPLE APP g #US-000001');
      expect(r.timestamp, DateTime.utc(2026, 11, 2, 13, 19));
    });

    test('BisB account credited: income, time taken from the receipt', () {
      final r = run(
          'BisB',
          'Your account 0000XXXXXX5566 has been credited with BHD120.000. Available Bal. BHD199.999',
          DateTime.utc(2026, 11, 3, 0, 36));
      expect(r.status, ExtractionStatus.transaction);
      expect(r.direction, TxDirection.incoming);
      expect(r.amountFils, 120000);
      expect(r.last4, '5566');
      expect(r.flags, contains(ExtractionFlag.timestampFromReceipt));
    });

    test('ila loan campaign is a promotion, not a transfer', () {
      final r = run(
          'ila Bank',
          'Apply for an ila loan or transfer your existing loan for a chance to have it paid off, up to BHD20,000. Campaign period: 9 September 2026 to 31 March 2027.',
          DateTime.utc(2026, 11, 2, 8, 36));
      expect(r.status, ExtractionStatus.nonTransaction);
      expect(r.kind, MessageKind.promotion);
    });

    test('ila savings rate news is not a transaction', () {
      final r = run(
          'ila Bank',
          'Our Savings+ rates have increased.\n\nEarn more with a flexible high yield savings account now offering up to 2.80% p.a. paid monthly on BHD and USD accounts, with full flexibility and no lock-in period. Deposit today via the ila Bank app.',
          DateTime.utc(2026, 11, 2, 9, 45));
      expect(r.status, ExtractionStatus.nonTransaction);
    });

    test('Al Salam Fawri credit with the sender\'s name is read', () {
      final r = run(
          'AlSalamBank',
          "Fawri BHD 12.500 Ref. NBB103KAE000EEEE from 'TEST PERSON ONE' credited to Acc. XXXX010100000. Bal: BHD 99.999 on 26/10/26 at 09:19. Tel 17005500",
          DateTime.utc(2026, 10, 26, 6, 20));
      expect(r.status, ExtractionStatus.transaction);
      expect(r.type, TxnType.transferIn);
      expect(r.amountFils, 12500);
      expect(r.reference, 'NBB103KAE000EEEE');
    });

    test('Al Salam VISA prepaid card purchase is read', () {
      final r = run(
          'AlSalamBank',
          'Thank you for using your VISA PREPAID card XXXX1234 for BHD 3.500 at SAMPLE SHOP on 29-Apr ? 19:43 .Bal: AED 99.99',
          DateTime.utc(2026, 4, 29, 16, 50));
      expect(sum(r),
          'transaction|purchase|card|3500|BHD|1234|SAMPLE SHOP|2026-04-29T16:43:00.000Z');
    });

    test('Al Salam maintenance notice is not a transaction', () {
      final r = run(
          'AlSalamBank',
          'To enhance your banking experience, system maintenance will take place on 16 October 2026 from 2:00 to 6:00 AM. Some services may be temporarily unavailable.',
          DateTime.utc(2026, 10, 14, 11, 43));
      expect(r.status, ExtractionStatus.nonTransaction);
      expect(r.kind, MessageKind.information);
    });

    test('a bank message with an amount but no known format still goes to review',
        () {
      final r = run(
          'BisB',
          'Dear Client, your account was debited with BHD 3.000 for service charges on 02/11/2026.',
          DateTime.utc(2026, 11, 2, 10, 0));
      expect(r.status, ExtractionStatus.unparsed);
    });
  });

  group('NBB (real formats, balances and names masked)', () {
    test('card purchase: the account digits stand for the card', () {
      final r = run(
          'NBB',
          'Thank you for using NBB Debit Card at REDTAG                MANAMA for BHD6.930 on 27/10/2026 20:37, A/C ending 4810 balance BHD99.999.',
          DateTime.utc(2026, 10, 27, 17, 38));
      expect(sum(r),
          'transaction|purchase|card|6930|BHD|4810|REDTAG MANAMA|2026-10-27T17:37:00.000Z');
    });

    test('a promotion word inside the merchant name is still a purchase', () {
      final r = run(
          'NBB',
          'Thank you for using NBB Debit Card at DAY TO DAY DISCOUNT CEMANAMA for BHD14.396 on 02/11/2026 23:13, A/C ending 4810 balance BHD99.999.',
          DateTime.utc(2026, 11, 2, 20, 14));
      expect(sum(r),
          'transaction|purchase|card|14396|BHD|4810|DAY TO DAY DISCOUNT CEMANAMA|2026-11-02T20:13:00.000Z');
    });

    test('Fawri+ out', () {
      final r = run(
          'NBB',
          'Successful Fawri+ transfer of BHD1.600 credited to BHXALSAXX9417 on 24/10/2026 11:55, Ref.NBB241026ONH8WCQ, A/C ending 4810 balance BHD99.999.',
          DateTime.utc(2026, 10, 24, 8, 56));
      expect(sum(r),
          'transaction|transferOut|transfer|1600|BHD|4810|null|2026-10-24T08:55:00.000Z');
      expect(r.counterpartyLast4, '9417');
      expect(r.reference, 'NBB241026ONH8WCQ');
    });

    test('Fawri+ in', () {
      final r = run(
          'NBB',
          'Fawri+ transfer of BHD5.000 from BHXBIBBX9307 credited to your account on 30/10/2026 07:14, Ref.NBB301026IN7J3XS, A/C ending 4810 balance BHD99.999.',
          DateTime.utc(2026, 10, 30, 4, 15));
      expect(sum(r),
          'transaction|transferIn|transfer|5000|BHD|4810|null|2026-10-30T04:14:00.000Z');
      expect(r.counterpartyLast4, '9307');
    });

    test('after midnight NBB prints the previous day: the date is moved on', () {
      // Printed 02/11 00:41, received 03/11 00:42 Bahrain time.
      final r = run(
          'NBB',
          'Fawri+ transfer of BHD0.500 from BHXBIBBX3208 credited to your account on 02/11/2026 00:41, Ref.NBB021126IN8PD5G, A/C ending 4810 balance BHD99.999.',
          DateTime.utc(2026, 11, 2, 21, 42));
      expect(r.timestamp, DateTime.utc(2026, 11, 2, 21, 41));
      expect(r.status, ExtractionStatus.transaction);
    });

    test('a message just after midnight received at once keeps its date', () {
      final r = run(
          'NBB',
          'Fawri+ transfer of BHD0.500 from BHXBIBBX3208 credited to your account on 03/11/2026 00:41, Ref.NBB031126INMU8ZJ, A/C ending 4810 balance BHD99.999.',
          DateTime.utc(2026, 11, 2, 21, 42));
      expect(r.timestamp, DateTime.utc(2026, 11, 2, 21, 41));
    });

    test('other banks are not moved', () {
      final r = run(
          'ilabank',
          'Success! Purchase at SAMPLE SHOP using card ****8855 for BHD 1.500 on 02/11/2026 00:30 debited from BHD Ac Balance BHD 9.999 Enquiry 17123456',
          DateTime.utc(2026, 11, 2, 21, 31));
      expect(r.timestamp, DateTime.utc(2026, 11, 1, 21, 30));
    });
  });

  group('KFH (real format, IBAN masked)', () {
    test('Fawri+ payment to an IBAN', () {
      final r = run(
          'KFH',
          'Dear Customer, Fawri+ payment BD 10.054, Ref. AUB103QXT00123FK credited to IBAN BH93BIBBXXXXXXXXXX6142 on 30/10/2025 at 14:36. Call 17221999 for Inquiries',
          DateTime.utc(2025, 10, 30, 11, 37));
      expect(sum(r),
          'transaction|transferOut|transfer|10054|BHD|null|null|2025-10-30T11:36:00.000Z');
      expect(r.counterpartyLast4, '6142');
      expect(r.reference, 'AUB103QXT00123FK');
      expect(r.toString().contains('BH93'), false);
    });
  });
}
