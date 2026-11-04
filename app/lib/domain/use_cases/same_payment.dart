import 'package:beaza_extraction/beaza_extraction.dart';

/// A counted transaction that is probably the same payment as [r]: same
/// amount, within [window] of the printed time (or the same Bahrain day when
/// the receipt had no time). A receipt for a card purchase usually has a
/// bank SMS too, and adding both would count the money twice.
LedgerEntry? likelySamePayment(
  Iterable<LedgerEntry> entries,
  ExtractionResult r, {
  Duration window = const Duration(minutes: 30),
}) {
  final amount = r.amountFils;
  final at = r.timestamp;
  if (amount == null || at == null) return null;
  final noTime = r.flags.contains(ExtractionFlag.timestampFromReceipt);
  for (final e in entries) {
    final t = e.result.timestamp;
    if (!e.countsTowardSpending || t == null) continue;
    if (e.result.amountFils != amount) continue;
    final close =
        noTime ? Day.of(t) == Day.of(at) : t.difference(at).abs() <= window;
    if (close) return e;
  }
  return null;
}
