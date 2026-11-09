import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:test/test.dart';

DateTime bh(int day, int hour) =>
    DateTime.utc(2026, 11, day, hour).subtract(kBahrainOffset);

ExtractionResult tx(int fils, DateTime at, TxDirection dir,
        {String? category, String? ref}) =>
    ExtractionResult(
      status: ExtractionStatus.transaction,
      amountFils: fils,
      currency: 'BHD',
      type: dir == TxDirection.outgoing ? TxnType.purchase : TxnType.transferIn,
      direction: dir,
      category: category,
      reference: ref,
      timestamp: at,
    );

void main() {
  const reconciler = Reconciler();
  const g = Guardrail(GuardrailSettings(dailyLimitFils: 10000));
  const today = Day(2026, 11, 9);

  test('money received is income until the person marks it paid back', () {
    final e = reconciler.reconcile([
      tx(8000, bh(9, 13), TxDirection.outgoing, ref: 'A'),
      tx(4000, bh(9, 18), TxDirection.incoming, ref: 'B'),
    ], OwnAccounts());
    expect(e[1].role, EntryRole.income);
    expect(g.spentOn(e, today), 8000);
  });

  test('a repayment comes off the day it arrives', () {
    final e = reconciler.reconcile([
      tx(8000, bh(9, 13), TxDirection.outgoing, ref: 'A'),
      tx(4000, bh(9, 18), TxDirection.incoming,
          category: kRepaymentCategory, ref: 'B'),
    ], OwnAccounts());
    expect(e[1].role, EntryRole.repayment);
    expect(e[1].countsTowardSpending, isFalse);
    expect(e[1].countedFils, -4000);
    expect(g.spentOn(e, today), 4000);
    expect(g.summarize(e, today).spentFils, 4000);
    expect(Reconciler.netFils(e), 4000);
  });

  test('more paid back than spent today: the day shows 0, the sum stays exact',
      () {
    final e = reconciler.reconcile([
      tx(8000, bh(8, 21), TxDirection.outgoing, ref: 'A'), // yesterday
      tx(6000, bh(9, 10), TxDirection.incoming,
          category: kRepaymentCategory, ref: 'B'),
      tx(1000, bh(9, 12), TxDirection.outgoing, ref: 'C'),
    ], OwnAccounts());
    expect(g.summarize(e, today).spentFils, 0);
    expect(g.spentOn(e, today), -5000);
    expect(g.spentOn(e, today.previous) + g.spentOn(e, today), 3000);
  });
}
