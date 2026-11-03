import 'package:beaza_extraction/beaza_extraction.dart';

/// Bahrain time on a day of November 2026, as UTC.
DateTime bh(int day, [int hour = 12]) =>
    DateTime.utc(2026, 11, day, hour).subtract(kBahrainOffset);

int _ref = 0;

ExtractionResult tx(
  int fils,
  DateTime at, {
  String? category,
  String? merchantRaw,
  String? merchantNorm,
  String? last4,
  String? counterpartyLast4,
  String? reference,
  String currency = 'BHD',
  TxnType type = TxnType.purchase,
  TxDirection direction = TxDirection.outgoing,
}) =>
    ExtractionResult(
      status: ExtractionStatus.transaction,
      kind: MessageKind.transaction,
      amountFils: fils,
      currency: currency,
      type: type,
      direction: direction,
      category: category,
      merchantRaw: merchantRaw,
      merchantNorm: merchantNorm,
      last4: last4,
      counterpartyLast4: counterpartyLast4,
      reference: reference ?? 'REF${_ref++}',
      timestamp: at,
    );

List<LedgerEntry> ledger(List<ExtractionResult> rs) =>
    const Reconciler().reconcile(rs, OwnAccounts());

/// Today is 14 Nov 2026. Last 7 days (8-14 Nov): food 3.900 (Costa, today),
/// shopping 13.200, not sorted 2.050 = 19.150. Plus 1.000 food on 1 Nov
/// (this month only), and money received and a USD purchase (never counted).
List<LedgerEntry> sample() => ledger([
      tx(3900, bh(14, 9),
          category: 'food',
          merchantRaw: 'COSTA COFFEE SEEF MALL',
          merchantNorm: 'Costa Coffee',
          last4: '4810'),
      tx(13200, bh(12, 20), category: 'shopping', merchantRaw: 'REDTAG MANAMA'),
      tx(2050, bh(10, 16), merchantRaw: 'Waleed Al Kabah MANAMA'),
      tx(1000, bh(1, 10), category: 'food'),
      tx(9000, bh(13, 9),
          type: TxnType.transferIn, direction: TxDirection.incoming),
      tx(22000, bh(11, 9), currency: 'USD', category: 'entertainment'),
    ]);
