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

  // A transfer in cannot tell a friend paying back from the person's own
  // top-up (seen on a real phone: transfers from the person's other accounts
  // were taken as repayments and hid real spending), so it stays income
  // until the person says otherwise.
  test('a transfer in after spending stays income until the person marks it',
      () {
    final e = rec([out(8000, bh(9, 13)), received(6000, bh(9, 16))]);
    expect(e[1].role, EntryRole.income);
    expect(g.summarize(e, today).spentFils, 8000);
    final m = rec([
      out(8000, bh(9, 13)),
      received(6000, bh(9, 16), category: kRepaymentCategory),
    ]);
    expect(m[1].role, EntryRole.repayment);
    expect(m[1].countedFils, -6000);
    expect(g.summarize(m, today).spentFils, 2000);
  });

  test('a top-up then a payment the same day: the payment counts', () {
    // 14 November 2026: 2.492 in from another account, then 0.250 spent.
    final e = rec([received(2492, bh(9, 0)), out(250, bh(9, 0))]);
    expect(e[0].role, EntryRole.income);
    expect(g.summarize(e, today).spentFils, 250);
  });

  test('a stipend stays income', () {
    final e = rec([
      for (var i = 0; i < 45; i++) out(9000, bh(1 + i % 8, 10 + i % 10)),
      received(400000, bh(9, 16)),
    ]);
    expect(e.last.role, EntryRole.income);
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
      received(6000, bh(9, 10), category: kRepaymentCategory),
      out(1000, bh(9, 12)),
    ]);
    expect(g.summarize(e, today).spentFils, 0);
    expect(g.spentOn(e, today), -5000);
    expect(g.spentOn(e, today.previous) + g.spentOn(e, today), 3000);
  });

  test('a transfer the person marks as between own accounts counts as neither',
      () {
    final top = received(2492, bh(9, 0), category: kOwnTransferCategory);
    final sentOut = ExtractionResult(
      status: ExtractionStatus.transaction,
      amountFils: 5000,
      currency: 'BHD',
      type: TxnType.transferOut,
      channel: Channel.transfer,
      direction: TxDirection.outgoing,
      category: kOwnTransferCategory,
      reference: 'X1',
      timestamp: bh(9, 1),
    );
    final e = rec([top, sentOut, out(100, bh(9, 2))]);
    expect(e[0].role, EntryRole.internalTransfer);
    expect(e[1].role, EntryRole.internalTransfer);
    expect(g.summarize(e, today).spentFils, 100);
  });
}
