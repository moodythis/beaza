import 'package:beaza/data/repositories/savings_repository.dart';
import 'package:beaza/domain/use_cases/spending_by_category.dart';
import 'package:beaza_extraction/beaza_extraction.dart';

/// DEMO points and offers. The partners and codes are invented for the
/// prototype and clearly labelled as such in the app; no real shop, bank or
/// brand appears, and nothing is sent anywhere.
class DemoOffer {
  const DemoOffer({
    required this.id,
    required this.category,
    required this.partnerAr,
    required this.partnerEn,
    required this.offerAr,
    required this.offerEn,
    required this.cost,
  });

  final String id;
  final String category;
  final String partnerAr;
  final String partnerEn;
  final String offerAr;
  final String offerEn;

  /// Points needed.
  final int cost;

  /// A made-up code, the same each time for the same offer and number.
  String codeFor(int n) => 'DEMO-${id.toUpperCase()}-${(n * 7919 + 1000) % 9000 + 1000}';
}

const List<DemoOffer> kDemoOffers = [
  DemoOffer(
    id: 'nakhla', category: 'food',
    partnerAr: 'مقهى النخلة', partnerEn: 'Nakhla Cafe',
    offerAr: 'خصم 25٪ على القهوة الثالثة', offerEn: '25% off your third coffee',
    cost: 50,
  ),
  DemoOffer(
    id: 'tannour', category: 'food',
    partnerAr: 'مطعم التنور', partnerEn: 'Tannour Kitchen',
    offerAr: 'وجبة طالب بـ 1.500 د.ب', offerEn: 'Student meal for BHD 1.500',
    cost: 80,
  ),
  DemoOffer(
    id: 'baqala', category: 'groceries',
    partnerAr: 'برادة الحي', partnerEn: 'Neighbourhood Baqala',
    offerAr: '10٪ على المقاضي فوق 5 د.ب', offerEn: '10% off groceries over BHD 5',
    cost: 60,
  ),
  DemoOffer(
    id: 'souq', category: 'shopping',
    partnerAr: 'سوق الطلبة', partnerEn: 'Student Souq',
    offerAr: 'خصم 15٪ على الملابس', offerEn: '15% off clothes',
    cost: 100,
  ),
  DemoOffer(
    id: 'maktaba', category: 'education',
    partnerAr: 'مكتبة الطالب', partnerEn: 'Student Bookshop',
    offerAr: 'طباعة 50 صفحة مجاناً', offerEn: '50 free printed pages',
    cost: 40,
  ),
  DemoOffer(
    id: 'mishwar', category: 'transport',
    partnerAr: 'مشوار', partnerEn: 'Mishwar Rides',
    offerAr: 'رحلة ثانية بنص السعر', offerEn: 'Second ride at half price',
    cost: 70,
  ),
  DemoOffer(
    id: 'sinema', category: 'entertainment',
    partnerAr: 'سينما الجزيرة الصغيرة', partnerEn: 'Little Island Cinema',
    offerAr: 'تذكرة الطالب بنص السعر', offerEn: 'Half-price student ticket',
    cost: 90,
  ),
];

/// Points: 10 for each finished day of the last 30 that stayed within the
/// daily limit (only days with some spending, and only when a limit is
/// set), plus 20 for each purchase skipped after the cooling-off wait.
int pointsEarned(
  Iterable<LedgerEntry> entries,
  GuardrailSettings settings,
  List<Hold> holds,
  Day today,
) {
  var points = 20 * holds.where((h) => h.decision == 'skipped').length;
  if (settings.dailyLimitFils <= 0) return points;
  final list = entries.toList();
  for (var i = 1; i <= 30; i++) {
    final d = today.addDays(-i);
    final spent = spendingByCategory(list, d, d).fold<int>(0, (a, c) => a + c.totalFils);
    if (spent > 0 && spent <= settings.dailyLimitFils) points += 10;
  }
  return points;
}

/// Offers in a fixed order, or (when the person turned it on) the ones for
/// their biggest categories of the last 7 days first. Worked out on the
/// phone; nothing is sent.
List<DemoOffer> rankOffers(List<CategoryTotal> week, {required bool personal}) {
  if (!personal) return kDemoOffers;
  final rank = {for (var i = 0; i < week.length; i++) week[i].bucket: i};
  final list = [...kDemoOffers];
  list.sort((a, b) => (rank[a.category] ?? 99).compareTo(rank[b.category] ?? 99));
  return list;
}
