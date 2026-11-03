import 'package:beaza_extraction/beaza_extraction.dart';

/// Shown for transfers sent to someone, which have no shop.
const String kTransferBucket = 'transfer';

/// Shown when nothing says what the money was for.
const String kUnsortedBucket = 'unsorted';

class CategoryTotal {
  const CategoryTotal(this.bucket, this.totalFils, this.count);

  /// One of kCategories, [kTransferBucket] or [kUnsortedBucket].
  final String bucket;
  final int totalFils;
  final int count;
}

/// The group a transaction is shown under.
String bucketOf(ExtractionResult r) {
  final c = r.category;
  if (c != null && c.isNotEmpty) return c;
  if (r.type == TxnType.transferOut || r.channel == Channel.transfer) {
    return kTransferBucket;
  }
  return kUnsortedBucket;
}

/// What was spent from [from] to [to] (Bahrain days, both included), per
/// group, largest first. Only counted spending in BHD: copies and transfers
/// between the person's own accounts are left out, like the daily limit.
List<CategoryTotal> spendingByCategory(
  Iterable<LedgerEntry> entries,
  Day from,
  Day to,
) {
  final start = from.startUtc;
  final end = to.endUtc;
  final totals = <String, int>{};
  final counts = <String, int>{};
  for (final e in entries) {
    final t = e.result.timestamp;
    final a = e.result.amountFils;
    if (!e.countsTowardSpending || t == null || a == null) continue;
    final u = t.toUtc();
    if (u.isBefore(start) || !u.isBefore(end)) continue;
    final b = bucketOf(e.result);
    totals[b] = (totals[b] ?? 0) + a;
    counts[b] = (counts[b] ?? 0) + 1;
  }
  final out = [
    for (final b in totals.keys) CategoryTotal(b, totals[b]!, counts[b]!),
  ]..sort((x, y) {
      final c = y.totalFils.compareTo(x.totalFils);
      return c != 0 ? c : x.bucket.compareTo(y.bucket);
    });
  return out;
}
