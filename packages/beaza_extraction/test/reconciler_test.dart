import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:test/test.dart';

void main() {
  const rec = Reconciler();
  final t0 = DateTime.utc(2026, 11, 2, 10, 0);

  ExtractionResult tx({
    int? amount = 1000,
    TxDirection dir = TxDirection.outgoing,
    TxnType? type = TxnType.purchase,
    Channel? ch = Channel.card,
    String? ref,
    String? last4 = '8855',
    String? cp,
    String? merchant = 'SHOP',
    int minute = 0,
    String currency = 'BHD',
    ExtractionStatus status = ExtractionStatus.transaction,
  }) =>
      ExtractionResult(
        status: status,
        amountFils: amount,
        currency: currency,
        type: type,
        direction: dir,
        channel: ch,
        reference: ref,
        last4: last4,
        counterpartyLast4: cp,
        merchantRaw: merchant,
        timestamp: t0.add(Duration(minutes: minute)),
      );

  ExtractionResult transfer(TxDirection dir,
          {String? ref, String? last4, String? cp, int amount = 6000, int minute = 0}) =>
      tx(
          amount: amount,
          dir: dir,
          type: dir == TxDirection.outgoing ? TxnType.transferOut : TxnType.transferIn,
          ch: Channel.transfer,
          ref: ref,
          last4: last4,
          cp: cp,
          merchant: null,
          minute: minute);

  String roles(List<LedgerEntry> es) => es.map((e) => e.role.name).join(',');

  group('roles', () {
    test('purchase is spending, incoming transfer is income', () {
      final es = rec.reconcile(
          [tx(), transfer(TxDirection.incoming, cp: '5522')], OwnAccounts());
      expect(roles(es), 'spending,income');
    });

    test('non-transactions and unparsed results are not counted', () {
      final es = rec.reconcile([
        const ExtractionResult(status: ExtractionStatus.nonTransaction),
        tx(status: ExtractionStatus.unparsed),
      ], OwnAccounts());
      expect(roles(es), 'notCounted,notCounted');
    });
  });

  group('duplicates by reference', () {
    test('same reference and direction is a duplicate', () {
      final es = rec.reconcile([
        transfer(TxDirection.incoming, ref: 'BP1000000001TEST'),
        transfer(TxDirection.incoming, ref: 'BP1000000001TEST', minute: 1),
      ], OwnAccounts());
      expect(roles(es), 'income,duplicate');
      expect(es[1].duplicateOf, 0);
    });

    test('same reference, opposite directions: both legs are internal', () {
      final es = rec.reconcile([
        transfer(TxDirection.outgoing, ref: 'BIB103KAD000DDDD', cp: '0777'),
        transfer(TxDirection.incoming, ref: 'BIB103KAD000DDDD', last4: '0777'),
      ], OwnAccounts());
      expect(roles(es), 'internalTransfer,internalTransfer');
    });

    test('a duplicate of one leg stays a duplicate', () {
      final es = rec.reconcile([
        transfer(TxDirection.outgoing, ref: 'R1'),
        transfer(TxDirection.incoming, ref: 'R1'),
        transfer(TxDirection.incoming, ref: 'R1', minute: 1),
      ], OwnAccounts());
      expect(roles(es), 'internalTransfer,internalTransfer,duplicate');
      expect(es[2].duplicateOf, 1);
    });
  });

  group('own accounts', () {
    test('transfer to a confirmed own account is internal', () {
      final es = rec.reconcile([transfer(TxDirection.outgoing, cp: '0777')],
          OwnAccounts(confirmed: ['0777']));
      expect(roles(es), 'internalTransfer');
    });

    test('unconfirmed account is not trusted', () {
      final es = rec.reconcile(
          [transfer(TxDirection.outgoing, cp: '0777')], OwnAccounts());
      expect(roles(es), 'spending');
    });

    test('rejected account is not own', () {
      final acc = OwnAccounts(confirmed: ['0777'])..reject('0777');
      expect(acc.isOwn('0777'), false);
      expect(roles(rec.reconcile([transfer(TxDirection.outgoing, cp: '0777')], acc)),
          'spending');
    });

    test('a card purchase is never internal, even with own digits', () {
      final es = rec.reconcile([tx(cp: '0777')], OwnAccounts(confirmed: ['0777']));
      expect(roles(es), 'spending');
    });

    test('suggestions: user-side digits not yet answered, in order', () {
      final acc = OwnAccounts(confirmed: ['6633'], rejected: ['1234']);
      final results = [
        tx(last4: '8855'),
        tx(last4: '6633'),
        tx(last4: '1234'),
        tx(last4: '0777'),
        tx(last4: '8855'),
        tx(last4: '9999', status: ExtractionStatus.unparsed),
      ];
      expect(acc.suggestions(results), ['8855', '0777']);
    });

    test('confirming an account and reconciling again changes the role', () {
      final results = [transfer(TxDirection.outgoing, cp: '0777')];
      final acc = OwnAccounts();
      expect(roles(rec.reconcile(results, acc)), 'spending');
      acc.confirm('0777');
      expect(roles(rec.reconcile(results, acc)), 'internalTransfer');
    });
  });

  group('possible duplicates without a reference', () {
    test('same amount and merchant within the window is flagged, still counted', () {
      final es = rec.reconcile([tx(), tx(minute: 3)], OwnAccounts());
      expect(roles(es), 'spending,spending');
      expect(es[1].possibleDuplicateOf, 0);
    });

    test('different merchant is not flagged', () {
      final es = rec.reconcile([tx(), tx(merchant: 'OTHER', minute: 3)], OwnAccounts());
      expect(es[1].possibleDuplicateOf, null);
    });

    test('outside the window is not flagged', () {
      final es = rec.reconcile([tx(), tx(minute: 30)], OwnAccounts());
      expect(es[1].possibleDuplicateOf, null);
    });

    test('different references are not flagged', () {
      final es = rec.reconcile([tx(ref: 'A'), tx(ref: 'B', minute: 1)], OwnAccounts());
      expect(es[1].possibleDuplicateOf, null);
    });

    test('different amount is not flagged', () {
      final es = rec.reconcile([tx(), tx(amount: 1500, minute: 1)], OwnAccounts());
      expect(es[1].possibleDuplicateOf, null);
    });
  });

  group('spending total', () {
    test('counts BHD spending only, not income, internal, duplicates or foreign', () {
      final es = rec.reconcile([
        tx(amount: 300),
        tx(amount: 1500, merchant: 'OTHER', minute: 1),
        transfer(TxDirection.incoming, amount: 50000),
        transfer(TxDirection.outgoing, cp: '0777', amount: 49000),
        tx(amount: 5000, currency: 'USD', merchant: 'WEB', minute: 2),
        transfer(TxDirection.incoming, ref: 'R9', amount: 100),
        transfer(TxDirection.incoming, ref: 'R9', amount: 100),
      ], OwnAccounts(confirmed: ['0777']));
      expect(Reconciler.spentFils(es), 1800);
    });
  });

  group('end to end with the extractor', () {
    final x = BeazaExtractor();

    test('both legs of a transfer between own banks are internal', () {
      final out = x.process(RawMessage(
          text:
              'Fawri+ payment BHD6.000, ref: BIB103KAD000DDDD was credited to IBAN ending 0777 on 2026/10/26 15:39. Balance BHD9.999. Tel: 17515151',
          sender: 'BisB',
          receivedAt: DateTime.utc(2026, 10, 26, 12, 40)));
      final inn = x.process(RawMessage(
          text:
              'Fawri+ BHD 6.000 ref BIB103KAD000DDDD from IBAN BH35BIBBXXXXXXXXXXXX27 credited to acct XXX10100777. Bal: BHD 9.999 on 26/10/26 at 15:39. Tel 17005500',
          sender: 'AlSalamBank',
          receivedAt: DateTime.utc(2026, 10, 26, 12, 40)));
      final es = rec.reconcile([out, inn], OwnAccounts());
      expect(roles(es), 'internalTransfer,internalTransfer');
      expect(Reconciler.spentFils(es), 0);
    });

    test('a Fawri credit that prints the name still pairs with its debit',
        () {
      final out = x.process(RawMessage(
          text:
              'Fawri+ payment BHD12.500, ref: NBB103KAE000EEEE was credited to IBAN ending 0000 on 2026/10/26 09:19. Balance BHD9.999. Tel: 17515151',
          sender: 'BisB',
          receivedAt: DateTime.utc(2026, 10, 26, 6, 20)));
      final inn = x.process(RawMessage(
          text:
              "Fawri BHD 12.500 Ref. NBB103KAE000EEEE from 'TEST PERSON ONE' credited to Acc. XXXX010100000. Bal: BHD 99.999 on 26/10/26 at 09:19. Tel 17005500",
          sender: 'AlSalamBank',
          receivedAt: DateTime.utc(2026, 10, 26, 6, 20)));
      final es = rec.reconcile([out, inn], OwnAccounts());
      expect(roles(es), 'internalTransfer,internalTransfer');
      expect(Reconciler.spentFils(es), 0);
    });

    test('BenefitPay received from a confirmed own account is internal', () {
      final r = x.process(RawMessage(
          text:
              'FAWRI+ Payment - BD 0.1 received from: Test Person\nFrom IBAN: BH40ALSA**********0777\nTo IBAN: BH35BIBB**********6633\nReference no: 6200000001-BP1000000001TEST-R\nCredited on: 02/11/2026 21:02',
          sender: 'BenefitPay',
          receivedAt: DateTime.utc(2026, 11, 2, 18, 5)));
      final acc = OwnAccounts();
      expect(acc.suggestions([r]), ['6633']);
      expect(roles(rec.reconcile([r], acc)), 'income');
      acc
        ..confirm('6633')
        ..confirm('0777');
      expect(roles(rec.reconcile([r], acc)), 'internalTransfer');
    });
  });
}
