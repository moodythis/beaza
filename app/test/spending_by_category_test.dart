import 'package:beaza/domain/use_cases/spending_by_category.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime bh(int day, int hour) =>
    DateTime.utc(2026, 11, day, hour).subtract(kBahrainOffset);

ExtractionResult tx(
  int fils,
  DateTime at, {
  String? category,
  TxnType type = TxnType.purchase,
  Channel? channel,
  String currency = 'BHD',
  TxDirection direction = TxDirection.outgoing,
  String? reference,
}) =>
    ExtractionResult(
      status: ExtractionStatus.transaction,
      amountFils: fils,
      currency: currency,
      type: type,
      direction: direction,
      channel: channel,
      category: category,
      reference: reference,
      timestamp: at,
    );

List<LedgerEntry> ledger(List<ExtractionResult> rs) =>
    const Reconciler().reconcile(rs, OwnAccounts());

String show(List<CategoryTotal> t) =>
    t.map((c) => '${c.bucket}:${c.totalFils}x${c.count}').join(',');

void main() {
  const from = Day(2026, 11, 1);
  const to = Day(2026, 11, 7);

  test('adds up per category, largest first', () {
    final t = spendingByCategory(
      ledger([
        tx(3900, bh(2, 10), category: 'food'),
        tx(5800, bh(3, 21), category: 'food'),
        tx(13200, bh(4, 20), category: 'shopping'),
        tx(2050, bh(5, 16)),
      ]),
      from,
      to,
    );
    expect(show(t), 'shopping:13200x1,food:9700x2,unsorted:2050x1');
  });

  test('a transfer sent to someone is its own group', () {
    final t = spendingByCategory(
      ledger([
        tx(5000, bh(3, 12),
            type: TxnType.transferOut,
            channel: Channel.transfer,
            reference: 'R1'),
      ]),
      from,
      to,
    );
    expect(show(t), 'transfer:5000x1');
  });

  test('money received, other currencies and other days are left out', () {
    final t = spendingByCategory(
      ledger([
        tx(9000, bh(3, 9),
            direction: TxDirection.incoming, type: TxnType.transferIn),
        tx(22000, bh(3, 9), currency: 'USD', category: 'entertainment'),
        tx(1000, bh(8, 9), category: 'food'), // after the range
        tx(1000, DateTime.utc(2026, 10, 31, 20), category: 'food'), // 23:00 on 31 Oct
        tx(2000, bh(1, 0), category: 'food'), // first minute of 1 Nov
      ]),
      from,
      to,
    );
    // 20:00 UTC on 31 Oct is 23:00 Bahrain on 31 Oct: before the range.
    expect(show(t), 'food:2000x1');
  });

  test('the range includes its last day up to midnight', () {
    final t = spendingByCategory(
      ledger([
        tx(700, DateTime.utc(2026, 11, 7, 20, 59), category: 'bills'),
        tx(800, DateTime.utc(2026, 11, 7, 21, 0), category: 'bills'),
      ]),
      from,
      to,
    );
    expect(show(t), 'bills:700x1');
  });

  test('nothing spent gives an empty list', () {
    expect(spendingByCategory(ledger([]), from, to), isEmpty);
  });

  test('bucketOf', () {
    expect(bucketOf(tx(1, bh(1, 1), category: 'health')), 'health');
    expect(bucketOf(tx(1, bh(1, 1))), kUnsortedBucket);
    expect(bucketOf(tx(1, bh(1, 1), type: TxnType.transferOut)),
        kTransferBucket);
  });
}
