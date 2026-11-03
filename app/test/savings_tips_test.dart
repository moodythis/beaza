import 'package:beaza/domain/use_cases/savings_tips.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter_test/flutter_test.dart';

// "today" is 14 Nov 2026; the last 7 days are 8-14 Nov, the 7 before 1-7 Nov.
const today = Day(2026, 11, 14);

DateTime bh(int day, [int hour = 12]) =>
    DateTime.utc(2026, 11, day, hour).subtract(kBahrainOffset);

int _n = 0;

ExtractionResult tx(int fils, DateTime at, {String? category}) =>
    ExtractionResult(
      status: ExtractionStatus.transaction,
      amountFils: fils,
      currency: 'BHD',
      type: TxnType.purchase,
      direction: TxDirection.outgoing,
      category: category,
      reference: 'R${_n++}',
      timestamp: at,
    );

List<LedgerEntry> ledger(List<ExtractionResult> rs) =>
    const Reconciler().reconcile(rs, OwnAccounts());

String show(List<SavingsTip> t) =>
    t.map((x) => '${x.kind.name}:${x.bucket}:${x.fils}:${x.otherFils}:${x.count}').join(',');

void main() {
  test('too little spending says nothing', () {
    final t = savingsTips(ledger([tx(3000, bh(10), category: 'food')]), today);
    expect(t, isEmpty);
  });

  test('a category up by half or more is called out with both amounts', () {
    final t = savingsTips(
      ledger([
        tx(4000, bh(3), category: 'food'), // week before
        tx(7000, bh(10), category: 'food'), // this week, 1.75 times
        tx(1000, bh(11), category: 'transport'),
      ]),
      today,
    );
    expect(show(t), startsWith('categorySpike:food:7000:4000:0'));
  });

  test('a small rise is not a spike', () {
    final t = savingsTips(
      ledger([
        tx(6000, bh(3), category: 'food'),
        tx(7000, bh(10), category: 'food'),
      ]),
      today,
    );
    expect(t.map((x) => x.kind), isNot(contains(TipKind.categorySpike)));
  });

  test('a new category with nothing the week before is not called a spike', () {
    final t = savingsTips(
      ledger([tx(9000, bh(10), category: 'shopping')]),
      today,
    );
    expect(t.map((x) => x.kind), isNot(contains(TipKind.categorySpike)));
  });

  test('days over the daily limit: two or more', () {
    final rs = [
      tx(6000, bh(9), category: 'food'),
      tx(6000, bh(11), category: 'food'),
      tx(2000, bh(13), category: 'food'),
    ];
    final withLimit = savingsTips(ledger(rs), today, dailyLimitFils: 5000);
    expect(withLimit.map((x) => x.kind), contains(TipKind.overLimitDays));
    expect(
      withLimit.firstWhere((x) => x.kind == TipKind.overLimitDays).count,
      2,
    );
    final noLimit = savingsTips(ledger(rs), today);
    expect(noLimit.map((x) => x.kind), isNot(contains(TipKind.overLimitDays)));
    final one = savingsTips(ledger(rs), today, dailyLimitFils: 6000);
    expect(one.map((x) => x.kind), isNot(contains(TipKind.overLimitDays)));
  });

  test('one category taking 40 percent or more of the week', () {
    final t = savingsTips(
      ledger([
        tx(8000, bh(10), category: 'groceries'),
        tx(4000, bh(11), category: 'transport'),
        tx(3000, bh(12), category: 'bills'),
      ]),
      today,
    );
    expect(show(t), contains('topCategory:groceries:8000:0:53'));
  });

  test('trim target: 20 percent of the biggest discretionary category', () {
    final t = savingsTips(
      ledger([
        tx(9000, bh(10), category: 'entertainment'),
        tx(2000, bh(11), category: 'bills'),
        tx(2000, bh(12), category: 'transport'),
      ]),
      today,
    );
    expect(t.map((x) => x.kind), contains(TipKind.trimTarget));
    final trim = t.firstWhere((x) => x.kind == TipKind.trimTarget);
    expect(trim.bucket, 'entertainment');
    expect(trim.fils, 1800);
  });

  test('transfers and unsorted spending are never given a tip', () {
    final t = savingsTips(
      ledger([
        tx(20000, bh(10)), // unsorted
        tx(3000, bh(11), category: 'food'),
      ]),
      today,
    );
    expect(t.where((x) => x.bucket == 'unsorted'), isEmpty);
  });

  test('at most three tips', () {
    final t = savingsTips(
      ledger([
        tx(3000, bh(3), category: 'food'),
        tx(9000, bh(9), category: 'food'),
        tx(9000, bh(10), category: 'shopping'),
        tx(9000, bh(11), category: 'entertainment'),
      ]),
      today,
      dailyLimitFils: 4000,
    );
    expect(t.length, lessThanOrEqualTo(3));
    expect(t, isNotEmpty);
  });
}
