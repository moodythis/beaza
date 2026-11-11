/// What the person is asking, with word lists (Gulf Arabic and English).
library;

import 'package:beaza_extraction/beaza_extraction.dart';

import 'analytics.dart';
import 'money.dart';
import 'response.dart';
import 'scope.dart';
import 'text.dart';

enum Topic { coffee, delivery }

/// What a spending question asks for, beyond a plain total.
enum QueryKind { total, biggest, topShop, compare, average, projection, overLimit }

const Set<String> _biggestWords = {'اكبر', 'اغلى', 'biggest', 'largest', 'expensive'};
const Set<String> _shopWords = {'محل', 'محلات', 'مكان', 'shop', 'shops', 'store', 'stores', 'place'};
const Set<String> _mostWords = {'اكثر', 'most', 'often', 'وايد'};
const Set<String> _compareWords = {'قارن', 'مقارنه', 'compare', 'compared', 'vs', 'than'};
const Set<String> _moreLess = {'اكثر', 'اقل', 'more', 'less', 'زاد', 'نقص'};
const Set<String> _pastWords = {'فات', 'الماضي', 'ماضي', 'قبله', 'last', 'previous'};
const Set<String> _averageWords = {'معدل', 'متوسط', 'average', 'avg', 'يوميا', 'باليوم', 'daily'};
const Set<String> _endWords = {'اخر', 'نهايه', 'end', 'rate', 'بهالمعدل', 'pace'};
const Set<String> _overWords = {'تعديت', 'تجاوزت', 'عديت', 'طلعت', 'over', 'exceeded', 'passed', 'went'};
const Set<String> _manyDays = {'يوم', 'ايام', 'مرات', 'مره', 'days', 'times'};

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
    this.kind = QueryKind.total,
    this.words = const [],
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
        kind: kind,
        words: words,
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

  final QueryKind kind;

  /// The question's words, for matching a shop name.
  final List<String> words;
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
  'وش', 'ويش', 'شو', 'بكم', 'how', 'what', 'where', 'which',
};

/// "If ...": a what-if, never an expense to add.
const Set<String> _conditional = {'لو', 'اذا', 'if'};
const Set<String> _outcome = {'يصير', 'بيصير', 'يبقى', 'يظل', 'يقه', 'happens', 'happen'};

/// Words of a question that are never part of a shop's name.
final Set<String> _questionVocabulary = {
  ..._question, ..._conditional, ..._outcome, ..._howMuch, ..._howMany, //
  ..._today, ..._yesterday, ..._week, ..._month, ..._pastWords, ..._remaining, //
  ..._advice, ..._breakdown, ..._afford, ..._biggestWords, ..._shopWords, //
  ..._mostWords, ..._compareWords, ..._moreLess, ..._averageWords, ..._endWords, //
  ..._overWords, ..._manyDays,
  for (final w in _categoryWords.values) ...w,
  for (final w in _topicWords.values) ...w,
  'في', 'عند', 'من', 'على', 'عن', 'يا', 'اليوم', 'at', 'in', 'on', 'the', 'did', //
  'do', 'i', 'my', 'me', 'to', 'for', 'from', 'is', 'was', 'have', 'this', 'that', //
  'بيزه', 'beaza', 'ويكند', 'weekend', 'كله', 'كلها', 'بالضبط', 'تقريبا', 'لين', //
  'الحين', 'now', 'all', 'so', 'far', 'total', 'much', 'many', 'spend',
};

/// True for a word that belongs to the question itself (or to money, a
/// period, a category), so it cannot be a shop name.
bool isQuestionWord(String token) =>
    _forms(token).any((f) =>
        _questionVocabulary.contains(f) ||
        kAssistantScope.moneyWords.contains(f) ||
        kAssistantScope.fillerWords.contains(f) ||
        kAssistantScope.leftWords.contains(f));
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
const Set<String> _howMany = {'many'};
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
                ? (_has(tokens, _pastWords) ? PeriodKind.lastMonth : PeriodKind.month)
                : _has(tokens, _week)
                    ? (_has(tokens, _pastWords) && !_has(tokens, _compareWords) && !_has(tokens, _moreLess)
                        ? PeriodKind.lastWeek
                        : PeriodKind.week)
                    : (remaining ? PeriodKind.today : PeriodKind.week);

    final QueryKind kind;
    if (_has(tokens, _overWords) && (_has(tokens, _manyDays) || _has(tokens, _howMany))) {
      kind = QueryKind.overLimit;
    } else if (_has(tokens, _compareWords) ||
        (_has(tokens, _moreLess) && _has(tokens, _pastWords))) {
      kind = QueryKind.compare;
    } else if (_has(tokens, _endWords) && (_has(tokens, _month) || _has(tokens, const {'rate', 'pace', 'بهالمعدل'}))) {
      kind = QueryKind.projection;
    } else if (_has(tokens, _averageWords)) {
      kind = QueryKind.average;
    } else if (_has(tokens, _shopWords) && (_has(tokens, _mostWords) || _has(tokens, const {'وين', 'which', 'where'}))) {
      kind = QueryKind.topShop;
    } else if (_has(tokens, _biggestWords) ||
        (_has(tokens, const {'most'}) && _has(tokens, const {'expensive'}))) {
      kind = QueryKind.biggest;
    } else {
      kind = QueryKind.total;
    }

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
    final hypothetical = _has(tokens, _conditional);
    if ((asks || hypothetical) &&
        prices.length == 1 &&
        (_has(tokens, _afford) || hypothetical || _has(tokens, _outcome))) {
      intent = AssistantIntent.canIBuy;
    } else if (_has(tokens, _advice)) {
      intent = aboutMoney || scope.onlyAdvice(tokens)
          ? AssistantIntent.guardrailAdvice
          : AssistantIntent.outOfScope;
    } else if (asks || remaining) {
      intent = aboutMoney || shortLeft
          ? AssistantIntent.spendingQuery
          : AssistantIntent.outOfScope;
    } else if (amounts && !hypothetical) {
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
      kind: kind,
      words: tokens,
      wantsBreakdown: category == null &&
          topic == null &&
          (_has(tokens, _breakdown) || whereWord),
    );
  }
}
