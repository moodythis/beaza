import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:test/test.dart';

// Each check becomes one test (arguments are evaluated at registration).
void check(String name, Object? actual, Object? expected) =>
    test(name, () => expect(actual, expected));

void main() {
  const ex = Tier1Extractor();

  String sum(Tier1Result? r) => r == null
      ? 'null'
      : '${r.amountFils}|${r.direction.name}|${r.channel.name}|'
          '${r.accountLast4}|${r.counterpartyLast4}|${r.reference}|'
          '${r.merchant}|${r.occurredAt?.toIso8601String()}';

  int conf(Tier1Result? r) => (r!.confidence * 1000).round();

  // Messages below follow real Bahraini formats. Names, balances and numbers
  // are invented. Text is already normalized (BD -> BHD).
  const bisbOut = 'Fawri+ payment BHD2.900, ref: BIB103KAA000AAAA was credited to IBAN ending 4411 on 2026/10/30 00:59. Balance BHD9.999. Tel: 17515151';
  const bisbIn = 'Fawri+ payment BHD8.800 received from IBAN 5522 to IBAN 6633 ref. BIB103KAB000BBBB on 2026/10/25 06:15. Balance BHD9.999. Tel 17515151';
  const bisbCard = 'Dear CLIENT, thank you for using your Debit card 7744 for BHD 0.300 at SAMPLE BAKERY - MAL BAH BH-000001 on 15/10 @16:31. Avail Bal BHD 9.999. Tel 17515151';
  const ilaCard = 'Success! Purchase at SAMPLE TRADING CO W using card ****8855 for BHD 1.500 on 29/10/2026 15:42 debited from BHD Ac Balance BHD 9.999 Enquiry 17123456';
  const ilaIn = 'Success! Fawri+ transfer of BHD 50.000 from IBAN ****0777 credited to BHD Ac on 02/11/2026 12:11 Ref ALS103KAC000CCCC Balance BHD 9.999 Enquiry 17123456';
  const bpReceived = 'FAWRI+ Payment - BHD 0.1 received from: Test Person From IBAN: BH40ALSA**********0777 To IBAN: BH35BIBB**********6633 Reference no: 6200000001-BP1000000001TEST-R Credited on: 02/11/2026 21:02';
  const bpCredited = 'FAWRI+ Payment - BHD 0.1 was credited to:. From IBAN: BH40ALSA**********0777 To IBAN: BH35BIBB**********6633 Tel: +00000000 Reference no: 6200000002-BP1000000001TEST Credited on: 02/11/2026 21:02';

  // One check per template: amount|direction|channel|account|counterparty|ref|merchant|time(UTC)
  check('BisB Fawri+ out', sum(ex.extract(bisbOut, family: SenderFamily.bisb)),
      '2900|outgoing|fawri|null|4411|BIB103KAA000AAAA|null|2026-10-29T21:59:00.000Z');
  check('BisB Fawri+ in', sum(ex.extract(bisbIn, family: SenderFamily.bisb)),
      '8800|incoming|fawri|6633|5522|BIB103KAB000BBBB|null|2026-10-25T03:15:00.000Z');
  // The wording of a larger credit (a stipend): no "+", "ending", "credited to".
  check('BisB Fawri in, "ending ... credited to" wording',
      sum(ex.extract('Fawri payment BHD400.000 received from IBAN ending 5522 credited to IBAN ending 6633 ref. NBB101126TEST0A1 on 2026/11/10 15:09. Balance BHD9.999. Tel: 17515151', family: SenderFamily.bisb)),
      '400000|incoming|fawri|6633|5522|NBB101126TEST0A1|null|2026-11-10T12:09:00.000Z');
  check('BisB card purchase',
      sum(ex.extract(bisbCard, family: SenderFamily.bisb, receivedAt: DateTime.utc(2026, 10, 15, 13, 40))),
      '300|outgoing|card|7744|null|null|SAMPLE BAKERY - MAL BAH BH-000001|2026-10-15T13:31:00.000Z');
  check('ila card purchase', sum(ex.extract(ilaCard, family: SenderFamily.ila)),
      '1500|outgoing|card|8855|null|null|SAMPLE TRADING CO W|2026-10-29T12:42:00.000Z');
  check('ila merchant with &amp;',
      sum(ex.extract('Success! Purchase at INFO &amp; SAMPLE AUTHOR using card ****8855 for BHD 5.000 on 14/10/2026 17:16 debited from BHD Ac Balance BHD 9.999 Enquiry 17123456', family: SenderFamily.ila)),
      '5000|outgoing|card|8855|null|null|INFO & SAMPLE AUTHOR|2026-10-14T14:16:00.000Z');
  check('ila Fawri+ in', sum(ex.extract(ilaIn, family: SenderFamily.ila)),
      '50000|incoming|fawri|null|0777|ALS103KAC000CCCC|null|2026-11-02T09:11:00.000Z');
  check('ila Fawri+ out',
      sum(ex.extract('Success! Fawri+ transfer of BHD 49.000 to IBAN ****9966 is completed on 01/11/2026 20:45 Ref ABCO260000000001 Balance BHD 9.999 Enquiry 17123456', family: SenderFamily.ila)),
      '49000|outgoing|fawri|null|9966|ABCO260000000001|null|2026-11-01T17:45:00.000Z');
  check('Al Salam debit',
      sum(ex.extract('Dear Client, BHD 0.400 has been debited from your account XXXX10100777. Your balance is BHD 9.999 on 30/10/26 at 01:27. Thank you, Al Salam Bank.', family: SenderFamily.alSalam)),
      '400|outgoing|account|0777|null|null|null|2026-10-29T22:27:00.000Z');
  check('Al Salam Fawri+ in',
      sum(ex.extract('Fawri+ BHD 6.000 ref BIB103KAD000DDDD from IBAN BH35BIBBXXXXXXXXXXXX27 credited to acct XXX10100777. Bal: BHD 9.999 on 26/10/26 at 15:39. Tel 17005500', family: SenderFamily.alSalam)),
      '6000|incoming|fawri|0777|27|BIB103KAD000DDDD|null|2026-10-26T12:39:00.000Z');
  check('Al Salam Fawri in with the sender\'s name',
      sum(ex.extract("Fawri BHD 12.500 Ref. NBB103KAE000EEEE from 'TEST PERSON ONE' credited to Acc. XXXX010100000. Bal: BHD 99.999 on 26/10/26 at 09:19. Tel 17005500", family: SenderFamily.alSalam)),
      '12500|incoming|fawri|0000|null|NBB103KAE000EEEE|null|2026-10-26T06:19:00.000Z');
  check('Al Salam Fawri in with the name, the name is never kept',
      ex.extract("Fawri BHD 12.500 Ref. NBB103KAE000EEEE from 'TEST PERSON ONE' credited to Acc. XXXX010100000. Bal: BHD 99.999 on 26/10/26 at 09:19. Tel 17005500", family: SenderFamily.alSalam).toString(),
      isNot(contains('TEST PERSON')));
  check('Al Salam VISA prepaid card purchase (month name, no year)',
      sum(ex.extract('Thank you for using your VISA PREPAID card XXXX1234 for BHD 3.500 at SAMPLE SHOP on 29-Apr ? 19:43 .Bal: AED 99.99', family: SenderFamily.alSalam, receivedAt: DateTime.utc(2026, 4, 29, 16, 50))),
      '3500|outgoing|card|1234|null|null|SAMPLE SHOP|2026-04-29T16:43:00.000Z');
  check('Al Salam prepaid card without the stray symbol',
      sum(ex.extract('Thank you for using your VISA PREPAID card 1234 for BHD 0.200 at SAMPLE KIOSK on 3-Nov 09:05 .Bal: AED 99.99', family: SenderFamily.alSalam, receivedAt: DateTime.utc(2026, 11, 3, 6, 10))),
      '200|outgoing|card|1234|null|null|SAMPLE KIOSK|2026-11-03T06:05:00.000Z');
  check('a month name that is not a month is not read',
      ex.extract('Thank you for using your VISA PREPAID card 1234 for BHD 0.200 at SAMPLE KIOSK on 3-Xyz 09:05 .Bal: AED 99.99', family: SenderFamily.alSalam, receivedAt: DateTime.utc(2026, 11, 3, 6, 10))?.occurredAt,
      isNull);
  check('BenefitPay received', sum(ex.extract(bpReceived, family: SenderFamily.benefitPay)),
      '100|incoming|fawri|6633|0777|BP1000000001TEST|null|2026-11-02T18:02:00.000Z');
  check('BenefitPay credited (direction unknown)', sum(ex.extract(bpCredited, family: SenderFamily.benefitPay)),
      '100|unknown|fawri|6633|0777|BP1000000001TEST|null|2026-11-02T18:02:00.000Z');
  check('BenefitPay received without a name',
      ex.extract('FAWRI+ Payment - BHD 0.1 received from: From IBAN: BH40ALSA**********0777 To IBAN: BH35BIBB**********6633 Reference no: 6200000001-BP1000000001TEST-R Credited on: 02/11/2026 21:02', family: SenderFamily.benefitPay)?.amountFils,
      100);

  // Dedupe key
  check('Both BenefitPay notifications share one reference',
      ex.extract(bpReceived, family: SenderFamily.benefitPay)!.reference ==
          ex.extract(bpCredited, family: SenderFamily.benefitPay)!.reference,
      true);
  check('canonicalRef keeps bank references', Tier1Extractor.canonicalRef('BIB103KAE000EEEE'), 'BIB103KAE000EEEE');
  check('canonicalRef null', Tier1Extractor.canonicalRef(null), null);

  // Year handling for templates without a year
  check('No year and no receive time gives no date',
      ex.extract(bisbCard, family: SenderFamily.bisb)?.occurredAt, null);
  check('Year rolls back across New Year',
      ex.extract(bisbCard.replaceAll('15/10 @16:31', '31/12 @23:50'), family: SenderFamily.bisb, receivedAt: DateTime.utc(2026, 12, 31, 22, 0))?.occurredAt?.toIso8601String(),
      '2026-12-31T20:50:00.000Z');

  // Amounts
  check('Thousands separator', ex.extract(ilaIn.replaceAll('BHD 50.000', 'BHD 1,250.500'), family: SenderFamily.ila)?.amountFils, 1250500);
  check('Four decimals rejected', ex.extract(ilaIn.replaceAll('BHD 50.000', 'BHD 1.2345'), family: SenderFamily.ila)?.amountFils, null);

  // Confidence = 0.5*completeness + 0.3*specificity + 0.2*lexicon
  check('Full match, right sender', conf(ex.extract(bisbOut, family: SenderFamily.bisb)), 1000);
  check('Full match, wrong sender', conf(ex.extract(bisbOut, family: SenderFamily.alSalam)), 900);
  check('Full match, unknown sender', conf(ex.extract(bisbOut)), 900);
  check('Missing date lowers confidence', conf(ex.extract(bisbCard, family: SenderFamily.bisb)), 875);
  check('Unknown direction lowers confidence', conf(ex.extract(bpCredited, family: SenderFamily.benefitPay)), 833);

  // Not matched
  check('Greeting has no template', ex.extract('Hello from your bank') == null, true);
  check('ATM withdrawal has no template yet', ex.extract('ATM withdrawal of BHD 20.000 from card 7744 on 01/11/2026 10:00', family: SenderFamily.bisb) == null, true);

  // Privacy: nothing personal in the result
  final text = ex.extract(bpReceived, family: SenderFamily.benefitPay).toString();
  check('Result has no personal name', text.contains('Test Person'), false);
  check('Result has no full IBAN', text.contains('BH40') || text.contains('BH35'), false);

}
