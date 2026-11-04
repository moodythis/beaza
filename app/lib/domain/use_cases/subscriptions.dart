import 'package:beaza_extraction/beaza_extraction.dart';

/// A charge that repeats at the same amount from the same shop.
class Subscription {
  const Subscription({
    required this.name,
    required this.amountFils,
    required this.times,
    required this.weekly,
    required this.last,
    required this.next,
    this.knownByName = false,
  });

  /// Seen once only, but the shop is a known subscription service.
  final bool knownByName;

  final String name;

  /// The latest charge.
  final int amountFils;

  /// How many charges were found.
  final int times;

  /// Weekly rather than monthly.
  final bool weekly;
  final DateTime last;

  /// When the next charge is expected (last + the average gap).
  final DateTime next;

  /// What it costs a month: the charge, or a weekly charge x 52 / 12.
  int get monthlyFils => weekly ? (amountFils * 52 + 6) ~/ 12 : amountFils;
}

/// Shops that are subscriptions by nature (list adapted from the team's
/// earlier TypeScript prototype): one charge is enough to show them.
final RegExp kKnownSubscription = RegExp(
  r'netflix|spotify|youtube|apple\s*(?:music|tv|services|\.com)|icloud|disney|shahid|osn|anghami|deezer|crunchyroll|google\s*one|chatgpt|openai|adobe|github|dropbox|notion|microsoft\s*365|office\s*365|canva|linkedin|playstation|psn|xbox|nintendo|batelco|zain|\bstc\b|\bewa\b|tabreed|fitness\s*first|ufc\s*gym|gym',
  caseSensitive: false,
);

/// Repeating charges in the ledger: at least two counted charges from the
/// same shop, each gap 25 to 35 days (monthly) or 6 to 8 days (weekly),
/// every amount within 10% of the latest. Largest monthly cost first.
List<Subscription> findSubscriptions(Iterable<LedgerEntry> entries) {
  final byShop = <String, List<ExtractionResult>>{};
  final names = <String, String>{};
  for (final e in entries) {
    final r = e.result;
    final name = (r.merchantNorm ?? r.merchantRaw)?.trim();
    if (!e.countsTowardSpending ||
        name == null ||
        name.isEmpty ||
        r.timestamp == null ||
        r.amountFils == null) {
      continue;
    }
    final key = name.toLowerCase();
    names[key] = name;
    (byShop[key] ??= []).add(r);
  }
  final out = <Subscription>[];
  for (final MapEntry(:key, value: list) in byShop.entries) {
    list.sort((a, b) => a.timestamp!.compareTo(b.timestamp!));
    if (list.length < 2) {
      if (kKnownSubscription.hasMatch(names[key]!)) {
        out.add(Subscription(
          name: names[key]!,
          amountFils: list.single.amountFils!,
          times: 1,
          weekly: false,
          last: list.single.timestamp!,
          next: list.single.timestamp!.add(const Duration(days: 30)),
          knownByName: true,
        ));
      }
      continue;
    }
    final latest = list.last.amountFils!;
    // The run of matching charges that ends with the latest one.
    var run = <ExtractionResult>[list.last];
    bool? weekly;
    for (var i = list.length - 2; i >= 0; i--) {
      final a = list[i];
      final gap = run.first.timestamp!.difference(a.timestamp!).inDays;
      final isWeekly = gap >= 6 && gap <= 8;
      final isMonthly = gap >= 25 && gap <= 35;
      final close = (a.amountFils! - latest).abs() * 10 <= latest;
      if (!close || !(isWeekly || isMonthly)) break;
      if (weekly != null && weekly != isWeekly) break;
      weekly = isWeekly;
      run = [a, ...run];
    }
    if (run.length < 2) continue;
    final span = run.last.timestamp!.difference(run.first.timestamp!);
    final gap = Duration(microseconds: span.inMicroseconds ~/ (run.length - 1));
    out.add(Subscription(
      name: names[key]!,
      amountFils: latest,
      times: run.length,
      weekly: weekly!,
      last: run.last.timestamp!,
      next: run.last.timestamp!.add(gap),
    ));
  }
  out.sort((a, b) => b.monthlyFils.compareTo(a.monthlyFils));
  return out;
}
