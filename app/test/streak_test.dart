import 'package:beaza/domain/use_cases/streak.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime bh(int day, int hour) =>
    DateTime.utc(2026, 11, day, hour).subtract(kBahrainOffset);

ExtractionResult spend(int fils, DateTime at) => ExtractionResult(
      status: ExtractionStatus.transaction,
      amountFils: fils,
      currency: 'BHD',
      type: TxnType.purchase,
      direction: TxDirection.outgoing,
      timestamp: at,
    );

void main() {
  List<LedgerEntry> rec(List<ExtractionResult> r) =>
      const Reconciler().reconcile(r, OwnAccounts());
  const today = Day(2026, 11, 9);

  test('days in a row within the limit, ending yesterday', () {
    final e = rec([
      spend(12000, bh(5, 12)), // over: breaks the streak
      spend(3000, bh(6, 12)),
      spend(9000, bh(8, 12)), // 7 November: nothing spent, counts
      spend(15000, bh(9, 12)), // today does not count yet
    ]);
    expect(streakDays(e, today, 10000), 3);
  });

  test('no limit, no streak; at most 30', () {
    expect(streakDays(const [], today, 0), 0);
    expect(streakDays(const [], today, 10000), 30);
  });
}
