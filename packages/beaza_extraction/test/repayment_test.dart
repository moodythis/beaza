import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:test/test.dart';

DateTime bh(int day, int hour) =>
    DateTime.utc(2026, 11, day, hour).subtract(kBahrainOffset);

var _ref = 0;

ExtractionResult out(int fils, DateTime at) => ExtractionResult(
      status: ExtractionStatus.transaction,
      amountFils: fils,
      currency: 'BHD',
      type: TxnType.purchase,
      direction: TxDirection.outgoing,
      reference: 'O${_ref++}',
      timestamp: at,
    );

ExtractionResult received(int fils, DateTime at,
        {String? category, TxnType type = TxnType.transferIn}) =>
    ExtractionResult(
      status: ExtractionStatus.transaction,
      amountFils: fils,
      currency: 'BHD',
      type: type,
      channel: type == TxnType.refund ? Channel.card : Channel.transfer,
      direction: TxDirection.incoming,
      category: category,
      reference: 'I${_ref++}',
      timestamp: at,
    );

void main() {
  const reconciler = Reconciler();
  const g = Guardrail(GuardrailSettings(dailyLimitFils: 10000));
  const today = Day(2026, 11, 9);
  List<LedgerEntry> rec(List<ExtractionResult> r) =>
      reconciler.reconcile(r, OwnAccounts());

  test('a transfer back after spending is a repayment on its own',
      () {
    final e = rec([out(8000, bh(9, 13)), received(6000, bh(9, 16))]);
    expect(e[1].role, EntryRole.repayment);
    expect(e[1].countsTowardSpending, isFalse);
    expect(e[1].countedFils, -6000);
    expect(g.spentOn(e, today), 2000);
    expect(g.summarize(e, today).spentFils, 2000);
  });

  test('more than the month spent (a salary) stays income', () {
    final e = rec([out(8000, bh(9, 13)), received(50000, bh(9, 16))]);
    expect(e[1].role, EntryRole.income);
    expect(g.spentOn(e, today), 8000);
  });

  test('a stipend stays income even when the month\'s spending adds up to it',
      () {
    // 45 purchases of 9.000 = 405.000 spent; 400.000 arrives.
    final e = rec([
      for (var i = 0; i < 45; i++) out(9000, bh(1 + i % 8, 10 + i % 10)),
      received(400000, bh(9, 16)),
    ]);
    expect(e.last.role, EntryRole.income);
    // A friend's 9.000 the same day is still money paid back.
    final f = rec([
      for (var i = 0; i < 45; i++) out(9000, bh(1 + i % 8, 10 + i % 10)),
      received(400000, bh(9, 16)),
      received(9000, bh(9, 17)),
    ]);
    expect(f.last.role, EntryRole.repayment);
  });

  test('no more than the largest single purchase', () {
    final e = rec([
      out(5000, bh(8, 13)),
      out(5000, bh(8, 14)),
      received(8000, bh(9, 10)),
    ]);
    expect(e[2].role, EntryRole.income);
  });

  test('two transfers cannot pay back the same spending twice', () {
    final e = rec([
      out(8000, bh(8, 13)),
      received(6000, bh(9, 10)),
      received(6000, bh(9, 11)),
    ]);
    expect(e[1].role, EntryRole.repayment);
    expect(e[2].role, EntryRole.income);
  });

  test('paid back up to 30 days later counts; older spending does not', () {
    final late = DateTime.utc(2026, 11, 30, 10);
    expect(rec([out(8000, bh(1, 13)), received(6000, late)])[1].role,
        EntryRole.repayment);
    final tooLate = DateTime.utc(2026, 12, 5, 10);
    expect(rec([out(8000, bh(1, 13)), received(6000, tooLate)])[1].role,
        EntryRole.income);
  });

  test('a shop refund is always a repayment', () {
    final e = rec([received(3000, bh(9, 16), type: TxnType.refund)]);
    expect(e[0].role, EntryRole.repayment);
  });

  test('the person decides: received stays income, repayment always counts',
      () {
    final e = rec([
      out(8000, bh(9, 13)),
      received(6000, bh(9, 16), category: kReceivedCategory),
      received(90000, bh(9, 17), category: kRepaymentCategory),
    ]);
    expect(e[1].role, EntryRole.income);
    expect(e[2].role, EntryRole.repayment);
  });

  test('more paid back than spent today: the day shows 0, the sum stays exact',
      () {
    final e = rec([
      out(8000, bh(8, 21)),
      received(6000, bh(9, 10)),
      out(1000, bh(9, 12)),
    ]);
    expect(g.summarize(e, today).spentFils, 0);
    expect(g.spentOn(e, today), -5000);
    expect(g.spentOn(e, today.previous) + g.spentOn(e, today), 3000);
  });
}
