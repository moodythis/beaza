/// Cash expenses typed in Gulf Arabic or English, to drafts:
/// "شريت شاورما بـ 800 فلس وكرك بـ 200 فلس" gives two drafts.
library;

import 'package:beaza_extraction/beaza_extraction.dart';

import 'money.dart';
import 'response.dart';
import 'text.dart';

/// Everyday words for what was bought, to a category (normalised spelling).
const Map<String, String> kLocalItems = {
  // food
  'كرك': 'food', 'شاي': 'food', 'چاي': 'food', 'قهوه': 'food', //
  'كوفي': 'food', 'شاورما': 'food', 'عشا': 'food', 'عشانا': 'food',
  'عشاء': 'food', 'غدا': 'food', 'غدانا': 'food', 'غداء': 'food',
  'فطور': 'food', 'ريوق': 'food', 'مطعم': 'food', 'برجر': 'food',
  'بيتزا': 'food', 'سندويش': 'food', 'ساندويش': 'food', 'عصير': 'food',
  'ايسكريم': 'food', 'حلويات': 'food', 'مكبوس': 'food', 'مچبوس': 'food',
  'كيك': 'food', 'دونات': 'food', 'باجله': 'food', 'نخي': 'food',
  // groceries
  'براده': 'groceries', 'بقاله': 'groceries', 'سوبرماركت': 'groceries',
  'خضار': 'groceries', 'فواكه': 'groceries', 'خبز': 'groceries',
  'مقاضي': 'groceries', 'ماي': 'groceries',
  // transport
  'بنزين': 'transport', 'تاكسي': 'transport', 'اوبر': 'transport',
  'باص': 'transport', 'مواقف': 'transport', 'باركنج': 'transport',
  // shopping
  'ملابس': 'shopping', 'جوتي': 'shopping', 'شنطه': 'shopping',
  'عطر': 'shopping', 'هديه': 'shopping',
  // bills
  'فاتوره': 'bills', 'رصيد': 'bills', 'انترنت': 'bills',
  // health
  'صيدليه': 'health', 'دوا': 'health', 'دواء': 'health',
  'دكتور': 'health', 'عياده': 'health',
  // entertainment
  'سينما': 'entertainment', 'بلايستيشن': 'entertainment',
  'العاب': 'entertainment', 'قيمز': 'entertainment',
  // education
  'كتاب': 'education', 'كتب': 'education', 'قرطاسيه': 'education',
  'طباعه': 'education', 'مكتبه': 'education',
};

/// Words around an amount that are not what was bought.
const Set<String> _filler = {
  'شريت', 'اشتريت', 'دفعت', 'صرفت', 'طلع', 'طلعت', 'كان', 'كانت', 'حق', //
  'ب', 'في', 'فى', 'على', 'من', 'و', 'عند', 'اليوم', 'امس', 'البارحه',
  'بس', 'تقريبا', 'سجل', 'سجلي', 'ضيف', 'اضف', 'حط', 'لي', 'مع',
  'i', 'paid', 'bought', 'for', 'on', 'at', 'spent', 'today', 'yesterday',
  'a', 'an', 'the', 'add', 'log', 'and', 'got',
};

const Set<String> _yesterday = {'امس', 'البارحه', 'yesterday'};

class ExpenseParser {
  const ExpenseParser({
    this.money = const BahrainiMoneyParser(),
    this.merchants = const MerchantNormalizer(),
  });

  final BahrainiMoneyParser money;
  final MerchantNormalizer merchants;

  /// One draft per amount in [text]. [now] is the time of a draft unless
  /// the text says yesterday (then the same time a day earlier).
  List<DraftTransaction> parse(String text, DateTime now) {
    final tokens = tokenize(text);
    final found = money.findAll(tokens);
    if (found.isEmpty) return const [];
    final at = tokens.any(_yesterday.contains)
        ? now.subtract(const Duration(days: 1))
        : now;
    final out = <DraftTransaction>[];
    var prevEnd = 0;
    for (var k = 0; k < found.length; k++) {
      final m = found[k];
      // Only the words since the last break, and at most a few of them.
      var before = tokens.sublist(prevEnd, m.start);
      final cut = before.lastIndexOf(kBreak);
      if (cut >= 0) before = before.sublist(cut + 1);
      var what = _describe(before, dropJoinedWa: k > 0 || cut >= 0, last: true);
      if (what == null) {
        // "دفعت دينار ونص في البرادة": the shop comes after the amount.
        final nextStart = k + 1 < found.length ? found[k + 1].start : tokens.length;
        var after = tokens.sublist(m.end, nextStart);
        final stop = after.indexOf(kBreak);
        if (stop >= 0) after = after.sublist(0, stop);
        what = _describe(after, dropJoinedWa: true, last: false);
      }
      out.add(DraftTransaction(
        amountFils: m.fils,
        timestamp: at,
        merchantRaw: what,
        category: what == null ? null : categoryOf(what),
        amountGuessed: m.guessed,
      ));
      prevEnd = m.end;
    }
    return out;
  }

  /// At most this many words name an item ("قهوة مثلجة كبيرة").
  static const int maxWords = 3;

  String? _describe(List<String> words,
      {required bool dropJoinedWa, required bool last}) {
    final kept = <String>[];
    for (var w in words) {
      if (w == kBreak) continue;
      if (kept.isEmpty && dropJoinedWa && w.length > 2 && w.startsWith('و')) {
        w = w.substring(1); // "وكرك"
      }
      if (_filler.contains(w)) continue;
      kept.add(w);
    }
    if (kept.isEmpty) return null;
    // Before the amount the nearest words are the last ones; after it, the
    // first ones.
    final near = kept.length <= maxWords
        ? kept
        : (last ? kept.sublist(kept.length - maxWords) : kept.sublist(0, maxWords));
    return near.join(' ');
  }

  /// Local word list first ("كرك", "البراده"), then the shop dictionary.
  String? categoryOf(String what) {
    for (final raw in what.split(' ')) {
      final w = stripJoined(raw, (s) {
        if (kLocalItems.containsKey(s)) return true;
        return s.startsWith('ال') && kLocalItems.containsKey(s.substring(2));
      });
      if (w == null) continue;
      return kLocalItems[w] ?? kLocalItems[w.substring(2)];
    }
    return merchants.normalize(what)?.category;
  }
}
