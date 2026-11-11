/// What the person is asking, with word lists (Gulf Arabic and English).
library;

import 'package:beaza_extraction/beaza_extraction.dart';

import 'analytics.dart';
import 'money.dart';
import 'response.dart';
import 'scope.dart';
import 'text.dart';

enum Topic { coffee, delivery }

class ParsedRequest {
  const ParsedRequest({
    required this.intent,
    required this.arabic,
    this.period = PeriodKind.week,
    this.category,
    this.topic,
    this.wantsRemaining = false,
    this.wantsBreakdown = false,
    this.weekday,
    this.periodGiven = false,
    this.priceFils,
  });

  /// The same question for another period: "لا، بس الأحد" after "كم صرفت؟".
  ParsedRequest forPeriodOf(ParsedRequest other) => ParsedRequest(
        intent: intent,
        arabic: other.arabic,
        period: other.period,
        category: category,
        topic: topic,
        wantsRemaining: false,
        wantsBreakdown: wantsBreakdown,
        weekday: other.weekday,
        periodGiven: true,
      );

  final AssistantIntent intent;
  final bool arabic;
  final PeriodKind period;
  final String? category;
  final Topic? topic;
  final bool wantsRemaining;
  final bool wantsBreakdown;

  /// DateTime.monday..sunday when [period] is [PeriodKind.weekday].
  final int? weekday;

  /// The text named a day or a period (today, Sunday, this month...).
  final bool periodGiven;

  /// The price in a "can I buy it?" question.
  final int? priceFils;
}

/// "Can I / should I buy or take it": with an amount and a question.
const Set<String> _afford = {
  'يمديني', 'يمدي', 'يمدني', 'يمديك', 'اقدر', 'اشتري', 'اشتريه', 'اشتريت', //
  'شريت', 'اخذ', 'اخذه', 'اخذت', 'اخد', 'اخدت', 'اجيب', 'ينفع', 'afford', //
  'buy', 'get', 'purchase',
};

/// Weekday names: Arabic only with "ال" in front ("أحد" alone is "anyone").
final Map<String, int> _weekdays = {
  for (final e in const {
    'احد': DateTime.sunday,
    'اثنين': DateTime.monday,
    'اتنين': DateTime.monday,
    'ثلاثاء': DateTime.tuesday,
    'ثلاثا': DateTime.tuesday,
    'اربعاء': DateTime.wednesday,
    'اربعا': DateTime.wednesday,
    'خميس': DateTime.thursday,
    'جمعه': DateTime.friday,
    'سبت': DateTime.saturday,
  }.entries)
    for (final p in const ['ال', 'بال', 'وال', 'هال', 'لل'])
      '$p${e.key}': e.value,
  'sunday': DateTime.sunday,
  'monday': DateTime.monday,
  'tuesday': DateTime.tuesday,
  'wednesday': DateTime.wednesday,
  'thursday': DateTime.thursday,
  'friday': DateTime.friday,
  'saturday': DateTime.saturday,
};

int? _weekdayIn(List<String> tokens) {
  for (final t in tokens) {
    final w = _weekdays[t] ?? _weekdays[t.endsWith('s') ? t.substring(0, t.length - 1) : t];
    if (w != null) return w;
  }
  return null;
}

const Set<String> _question = {
  'كم', 'جم', 'چم', 'شكثر', 'شقد', 'قديش', 'وين', 'هل', 'شنو', 'ايش', //
  'وش', 'بكم', 'how', 'what', 'where', 'which',
};
const Set<String> _advice = {
  'نصيحه', 'نصايح', 'نصائح', 'انصحني', 'وفر', 'اوفر', 'توفير', 'شسوي', //
  'advice', 'tip', 'tips', 'save', 'saving', 'coach',
};
const Set<String> _remaining = {
  'باقي', 'باقيلي', 'يتبقى', 'تبقى', 'متبقي', 'حدي', 'حد', 'limit', //
  'left', 'remaining',
};
const Set<String> _breakdown = {
  'راحت', 'راح', 'توزيع', 'اصناف', 'breakdown', 'categories', 'go', 'went',
};
const Set<String> _howMuch = {'كم', 'جم', 'چم', 'بكم', 'شكثر', 'شقد', 'much'};
const Set<String> _today = {'اليوم', 'هاليوم', 'today'};
const Set<String> _yesterday = {'امس', 'البارحه', 'yesterday'};
const Set<String> _week = {'اسبوع', 'week'};
const Set<String> _month = {'شهر', 'month'};

const Map<String, Set<String>> _categoryWords = {
  'food': {'مطاعم', 'مطعم', 'اكل', 'food', 'restaurants', 'eating'},
  'groceries': {'بقاله', 'سوبرماركت', 'مقاضي', 'براده', 'groceries', 'grocery'},
  'shopping': {'تسوق', 'ملابس', 'shopping', 'clothes'},
  'transport': {'مواصلات', 'بنزين', 'تاكسي', 'transport', 'fuel', 'petrol'},
  'bills': {'فواتير', 'فاتوره', 'bills'},
  'health': {'صحه', 'صيدليه', 'دوا', 'health', 'pharmacy'},
  'entertainment': {'ترفيه', 'سينما', 'العاب', 'entertainment', 'cinema', 'games'},
  'education': {'دراسه', 'تعليم', 'كتب', 'education', 'books'},
};

const Map<Topic, Set<String>> _topicWords = {
  Topic.coffee: {'قهوه', 'كوفي', 'كافيه', 'كافيهات', 'كرك', 'coffee', 'cafe', 'cafes'},
  Topic.delivery: {'طلبات', 'توصيل', 'delivery', 'talabat', 'جاهز'},
};

/// Shop-name patterns for a topic. Approximate: it goes by names only.
final Map<Topic, RegExp> kTopicShops = {
  Topic.coffee: RegExp(
      r'coffee|karak|caf[eé]|\bcaf\b|roast|costa|starbucks|tim hortons|dunkin|كوفي|قهو[هة]|كافيه|كرك',
      caseSensitive: false,
      unicode: true),
  Topic.delivery: RegExp(
      r'talabat|jahez|careem\s*food|keeta|deliveroo|طلبات|جاهز',
      caseSensitive: false,
      unicode: true),
};

bool matchesTopic(Topic topic, ExtractionResult r) {
  final name = '${r.merchantNorm ?? ''} ${r.merchantRaw ?? ''}';
  return kTopicShops[topic]!.hasMatch(name);
}

/// The word and its forms without "ال", "هال", "عال", or a joined ب/و/ل.
Iterable<String> _forms(String t) sync* {
  yield t;
  for (final p in const ['هال', 'عال', 'بال', 'وال', 'لل', 'ال', 'ب', 'و', 'ل']) {
    if (t.length > p.length + 1 && t.startsWith(p)) yield t.substring(p.length);
  }
}

bool _has(List<String> tokens, Set<String> words) =>
    tokens.any((t) => _forms(t).any(words.contains));

class IntentDetector {
  const IntentDetector({this.money = const BahrainiMoneyParser()});

  final BahrainiMoneyParser money;

  /// The text carries its own money question, advice request or amount,
  /// so it is not a follow-up to the previous question.
  bool hasMoneyIntent(String text) {
    final tokens = tokenize(text);
    return kAssistantScope.hasMoneyWord(tokens) ||
        _has(tokens, _advice) ||
        money.findAll(tokens).isNotEmpty;
  }

  ParsedRequest detect(String text) {
    final tokens = tokenize(text);
    final arabic = isArabic(text);
    final asks = text.contains('?') || text.contains('؟') || _has(tokens, _question);

    String? category;
    for (final e in _categoryWords.entries) {
      if (_has(tokens, e.value)) {
        category = e.key;
        break;
      }
    }
    Topic? topic;
    for (final e in _topicWords.entries) {
      if (_has(tokens, e.value)) {
        topic = e.key;
        break;
      }
    }
    final remaining = _has(tokens, _remaining);
    final weekday = _weekdayIn(tokens);
    final period = weekday != null
        ? PeriodKind.weekday
        : _has(tokens, _yesterday)
        ? PeriodKind.yesterday
        : _has(tokens, _today)
            ? PeriodKind.today
            : _has(tokens, _month)
                ? PeriodKind.month
                : _has(tokens, _week)
                    ? PeriodKind.week
                    : (remaining ? PeriodKind.today : PeriodKind.week);

    // Only the person's own money is in scope (kAssistantScopeJson).
    final scope = kAssistantScope;
    final amounts = money.findAll(tokens).isNotEmpty;
    // A category or shop type alone ("best restaurant?", "advice on my
    // studies") is not about money; with "how much" or a period it is.
    final kindAsked = (category != null || topic != null) &&
        (_has(tokens, _howMuch) ||
            weekday != null ||
            _has(tokens, _today) ||
            _has(tokens, _yesterday) ||
            _has(tokens, _week) ||
            _has(tokens, _month));
    final aboutMoney = scope.hasMoneyWord(tokens) || kindAsked || amounts;
    final words = tokens.where((t) => t != kBreak).length;
    // "كم باقي؟", "How much is left today?"; not "how many days are left?".
    final shortLeft = scope.hasLeftWord(tokens) &&
        (words <= 3 ||
            _has(tokens, _howMuch) ||
            _has(tokens, _today) ||
            _has(tokens, _week) ||
            _has(tokens, _month));

    final prices = money.findAll(tokens);
    AssistantIntent intent;
    // "Can I buy it for 300?" and "if I spend 2 BD today, what is left?".
    if (asks &&
        prices.length == 1 &&
        (_has(tokens, _afford) || _has(tokens, const {'لو', 'if'}))) {
      intent = AssistantIntent.canIBuy;
    } else if (_has(tokens, _advice)) {
      intent = aboutMoney || scope.onlyAdvice(tokens)
          ? AssistantIntent.guardrailAdvice
          : AssistantIntent.outOfScope;
    } else if (asks || remaining) {
      intent = aboutMoney || shortLeft
          ? AssistantIntent.spendingQuery
          : AssistantIntent.outOfScope;
    } else if (amounts) {
      intent = AssistantIntent.logExpense;
    } else {
      intent = AssistantIntent.unknown;
    }

    final whereWord = _has(tokens, const {'وين', 'where'});
    return ParsedRequest(
      intent: intent,
      arabic: arabic,
      period: period,
      category: category,
      topic: category == null ? topic : null,
      wantsRemaining: remaining,
      weekday: weekday,
      priceFils: intent == AssistantIntent.canIBuy ? prices.single.fils : null,
      periodGiven: weekday != null ||
          _has(tokens, _today) ||
          _has(tokens, _yesterday) ||
          _has(tokens, _week) ||
          _has(tokens, _month),
      wantsBreakdown: category == null &&
          topic == null &&
          (_has(tokens, _breakdown) || whereWord),
    );
  }
}
