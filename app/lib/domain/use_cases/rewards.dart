import 'package:beaza/data/repositories/savings_repository.dart';
import 'package:beaza/domain/use_cases/daily_close.dart';
import 'package:beaza/domain/use_cases/spending_by_category.dart';
import 'package:beaza_assistant/beaza_assistant.dart' show Topic, matchesTopic;
import 'package:beaza_extraction/beaza_extraction.dart';

/// Coupons that shops give Beaza to show its users (FR-9.5). They are free:
/// nobody pays points for them. Beaza picks the ones that fit what the
/// person spends on. For the prototype the shops and codes are invented and
/// clearly labelled as a demo; no real shop, bank or brand appears, and
/// nothing is sent anywhere. In a real launch this list would come from the
/// partner shops.
class DemoOffer {
  const DemoOffer({
    required this.id,
    required this.category,
    required this.partnerAr,
    required this.partnerEn,
    required this.offerAr,
    required this.offerEn,
    required this.percent,
    this.topic,
    this.cost = 0,
  });

  final String id;
  final String category;
  final String partnerAr;
  final String partnerEn;
  final String offerAr;
  final String offerEn;

  /// The discount, in percent, used to show what it would have saved.
  final int percent;

  /// 'coffee' or 'delivery' when the offer is about that kind of shop
  /// rather than the whole category.
  final String? topic;

  /// Points taken when it is claimed: 0, coupons are free.
  final int cost;

  /// A made-up code, the same each time for the same offer and number.
  String codeFor(int n) => 'DEMO-${id.toUpperCase()}-${(n * 7919 + 1000) % 9000 + 1000}';
}

const List<DemoOffer> kDemoOffers = [
  DemoOffer(
    id: 'nakhla', category: 'food', topic: 'coffee',
    partnerAr: 'مقهى النخلة', partnerEn: 'Nakhla Cafe',
    offerAr: 'خصم 20٪ على القهوة والكرك', offerEn: '20% off coffee and karak',
    percent: 20,
  ),
  DemoOffer(
    id: 'tannour', category: 'food',
    partnerAr: 'مطعم التنور', partnerEn: 'Tannour Kitchen',
    offerAr: 'خصم 15٪ على وجبات الطلبة', offerEn: '15% off student meals',
    percent: 15,
  ),
  DemoOffer(
    id: 'tawseel', category: 'food', topic: 'delivery',
    partnerAr: 'توصيل الفريج', partnerEn: 'Fereej Delivery',
    offerAr: 'خصم 25٪ على رسوم التوصيل والطلب', offerEn: '25% off your order and delivery fee',
    percent: 25,
  ),
  DemoOffer(
    id: 'baqala', category: 'groceries',
    partnerAr: 'برادة الحي', partnerEn: 'Neighbourhood Baqala',
    offerAr: 'خصم 10٪ على المقاضي', offerEn: '10% off groceries',
    percent: 10,
  ),
  DemoOffer(
    id: 'souq', category: 'shopping',
    partnerAr: 'سوق الطلبة', partnerEn: 'Student Souq',
    offerAr: 'خصم 15٪ على الملابس', offerEn: '15% off clothes',
    percent: 15,
  ),
  DemoOffer(
    id: 'maktaba', category: 'education',
    partnerAr: 'مكتبة الطالب', partnerEn: 'Student Bookshop',
    offerAr: 'خصم 20٪ على الطباعة والقرطاسية', offerEn: '20% off printing and stationery',
    percent: 20,
  ),
  DemoOffer(
    id: 'mishwar', category: 'transport',
    partnerAr: 'مشوار', partnerEn: 'Mishwar Rides',
    offerAr: 'خصم 20٪ على المشاوير', offerEn: '20% off rides',
    percent: 20,
  ),
  DemoOffer(
    id: 'sinema', category: 'entertainment',
    partnerAr: 'سينما الجزيرة الصغيرة', partnerEn: 'Little Island Cinema',
    offerAr: 'خصم 30٪ على تذكرة الطالب', offerEn: '30% off student tickets',
    percent: 30,
  ),
];

/// What the person spent in the last 7 days where [offer] applies, and
/// what its discount would have kept: integer fils, worked out on the phone.
({int spentFils, int count, int savingFils}) offerFit(
    DemoOffer offer, Iterable<LedgerEntry> entries, Day today) {
  final from = today.addDays(-6);
  var spent = 0, count = 0;
  for (final e in entries) {
    final t = e.result.timestamp;
    if (!e.countsTowardSpending || t == null || e.result.amountFils == null) continue;
    final d = Day.of(t);
    if (d.compareTo(from) < 0 || d.compareTo(today) > 0) continue;
    final topic = offer.topic;
    final fits = topic == 'coffee'
        ? matchesTopic(Topic.coffee, e.result)
        : topic == 'delivery'
            ? matchesTopic(Topic.delivery, e.result)
            : e.result.category == offer.category;
    if (!fits) continue;
    spent += e.result.amountFils!;
    count++;
  }
  return (spentFils: spent, count: count, savingFils: spent * offer.percent ~/ 100);
}

/// Points: 10 for each finished day of the last 30 that stayed within the
/// daily limit (only days with some spending, and only when a limit is
/// set), plus 20 for each purchase skipped after the cooling-off wait.
/// and [kClosePoints] for each day of the last 30 whose unspent money was
/// sent to the goal ([sweeps]).
int pointsEarned(
  Iterable<LedgerEntry> entries,
  GuardrailSettings settings,
  List<Hold> holds,
  Day today, {
  int sweeps = 0,
}) {
  var points = 20 * holds.where((h) => h.decision == 'skipped').length +
      kClosePoints * sweeps;
  if (settings.dailyLimitFils <= 0) return points;
  final list = entries.toList();
  for (var i = 1; i <= 30; i++) {
    final d = today.addDays(-i);
    final spent = spendingByCategory(list, d, d).fold<int>(0, (a, c) => a + c.totalFils);
    if (spent > 0 && spent <= settings.dailyLimitFils) points += 10;
  }
  return points;
}

/// Offers in a fixed order, or (when the person turned it on, the default)
/// the ones that would have saved most on the last 7 days' spending first,
/// then by the person's biggest categories. Worked out on the phone; nothing
/// is sent.
List<DemoOffer> rankOffers(List<CategoryTotal> week,
    {required bool personal, Map<String, int> savings = const {}}) {
  if (!personal) return kDemoOffers;
  final rank = {for (var i = 0; i < week.length; i++) week[i].bucket: i};
  final list = [...kDemoOffers];
  list.sort((a, b) {
    final s = (savings[b.id] ?? 0).compareTo(savings[a.id] ?? 0);
    if (s != 0) return s;
    return (rank[a.category] ?? 99).compareTo(rank[b.category] ?? 99);
  });
  return list;
}
