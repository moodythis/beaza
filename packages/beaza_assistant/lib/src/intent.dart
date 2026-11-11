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
  });

  final AssistantIntent intent;
  final bool arabic;
  final PeriodKind period;
  final String? category;
  final Topic? topic;
  final bool wantsRemaining;
  final bool wantsBreakdown;
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
    final period = _has(tokens, _yesterday)
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

    AssistantIntent intent;
    if (_has(tokens, _advice)) {
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
      wantsBreakdown: category == null &&
          topic == null &&
          (_has(tokens, _breakdown) || whereWord),
    );
  }
}
