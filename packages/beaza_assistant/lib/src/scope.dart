/// What the assistant answers and what it turns away, kept as one JSON
/// document so the rules can be read and changed in one place (the
/// supervisor's request after testing: a question that is not about the
/// person's spending got a spending answer).
///
/// Words are matched after [normalizeText] (أ→ا, ة→ه, lower case), with
/// "ال" and joined ب/و/ل removed in front and ي/ك/ه/ها/نا/كم at the end.
library;

import 'dart:convert';

import 'text.dart';

const String kAssistantScopeJson = r'''
{
  "version": 1,
  "purpose": "Beaza's assistant answers only questions about the person's own spending, daily limit, budget, saving goal, subscriptions and points in Beaza.",
  "rules": [
    "A question is answered only if it has at least one money word below, a spending category or shop type, or an amount.",
    "A short question about what is left (\"how much is left?\") is answered even without a money word.",
    "A request for advice is answered if it has a money word, or if every other word is filler (\"give me a tip\").",
    "Anything else gets the out-of-scope reply. It is never sent to a language model."
  ],
  "llmRule": "If the question is not about the person's spending, budget, daily limit, saving or subscriptions in Beaza, do not answer it; reply only with \"out_of_scope\".",
  "moneyWords": {
    "ar": ["صرف", "صرفت", "صرفنا", "اصرف", "يصرف", "مصروف", "مصاريف", "دفعت", "ادفع", "دفع", "فلوس", "بيزات", "ميزانيه", "ميزانيت", "حدي", "حدك", "دينار", "دنانير", "فلس", "ربيه", "ربيات", "راتب", "معاش", "منحه", "مخصص", "دخل", "توفير", "وفر", "اوفر", "وفرت", "ادخار", "مدخرات", "شريت", "اشتري", "اشتريت", "مشتريات", "شرا", "سعر", "اسعار", "غالي", "رخيص", "تكلفه", "كلفه", "اشتراك", "اشتراكات", "فاتوره", "فواتير", "تحويل", "حولت", "محل", "محلات", "مشترى", "تعديت"],
    "en": ["spend", "spent", "spending", "money", "budget", "limit", "paid", "pay", "payment", "payments", "expense", "expenses", "cost", "costs", "bought", "buy", "buying", "purchase", "purchases", "bhd", "bd", "dinar", "dinars", "fils", "salary", "income", "stipend", "allowance", "save", "saved", "saving", "savings", "subscription", "subscriptions", "bill", "bills", "afford", "price", "prices", "cheaper", "cheap", "expensive", "transfer", "transfers", "shop", "shops", "store", "stores"]
  },
  "leftWords": ["باقي", "تبقى", "يتبقى", "متبقي", "left", "remaining"],
  "adviceWords": ["نصيحه", "نصايح", "نصائح", "انصحني", "شسوي", "advice", "tip", "tips", "coach"],
  "fillerWords": ["عطني", "اعطني", "عطيني", "ابي", "ابغي", "ابغى", "ممكن", "لو", "سمحت", "شي", "اي", "وحده", "حق", "لي", "give", "me", "some", "any", "a", "an", "please", "i", "need", "want", "can", "you", "one", "for"],
  "reply": {
    "ar": "أنا أجاوب بس على أسئلة صرفك وميزانيتك في بيزة. جرّب: «كم صرفت هالأسبوع؟» أو «كم باقي من حدي اليوم؟» أو «عطني نصيحة أوفر».",
    "en": "I only answer questions about your spending and budget in Beaza. Try \"How much did I spend this week?\", \"How much is left of my limit today?\" or \"Give me a saving tip\"."
  }
}
''';

/// [kAssistantScopeJson], read once.
final AssistantScope kAssistantScope =
    AssistantScope.fromJson(jsonDecode(kAssistantScopeJson) as Map<String, Object?>);

class AssistantScope {
  AssistantScope._({
    required this.version,
    required this.llmRule,
    required this.moneyWords,
    required this.leftWords,
    required this.adviceWords,
    required this.fillerWords,
    required this.replyAr,
    required this.replyEn,
  });

  factory AssistantScope.fromJson(Map<String, Object?> j) {
    Set<String> words(Object? list) =>
        {for (final w in (list as List).cast<String>()) normalizeText(w)};
    final money = j['moneyWords'] as Map<String, Object?>;
    final reply = j['reply'] as Map<String, Object?>;
    return AssistantScope._(
      version: j['version'] as int,
      llmRule: j['llmRule'] as String,
      moneyWords: {...words(money['ar']), ...words(money['en'])},
      leftWords: words(j['leftWords']),
      adviceWords: words(j['adviceWords']),
      fillerWords: words(j['fillerWords']),
      replyAr: reply['ar'] as String,
      replyEn: reply['en'] as String,
    );
  }

  final int version;
  final String llmRule;
  final Set<String> moneyWords;
  final Set<String> leftWords;
  final Set<String> adviceWords;
  final Set<String> fillerWords;
  final String replyAr;
  final String replyEn;

  String reply({required bool arabic}) => arabic ? replyAr : replyEn;

  static const List<String> _prefixes = [
    'هال', 'عال', 'بال', 'وال', 'لل', 'ال', 'ب', 'و', 'ل', //
  ];
  static const List<String> _suffixes = ['كم', 'ها', 'نا', 'ي', 'ك', 'ه'];

  /// [t] and the forms without a joined prefix and/or a possessive ending.
  static Iterable<String> forms(String t) sync* {
    final starts = <String>[t];
    for (final p in _prefixes) {
      if (t.length > p.length + 1 && t.startsWith(p)) {
        starts.add(t.substring(p.length));
      }
    }
    for (final s in starts) {
      yield s;
      for (final e in _suffixes) {
        if (s.length > e.length + 1 && s.endsWith(e)) {
          yield s.substring(0, s.length - e.length);
        }
      }
    }
  }

  static bool _any(Iterable<String> tokens, Set<String> words) =>
      tokens.any((t) => forms(t).any(words.contains));

  bool hasMoneyWord(List<String> tokens) => _any(tokens, moneyWords);

  bool hasLeftWord(List<String> tokens) => _any(tokens, leftWords);

  /// Every word is an advice word or filler: "عطني نصيحة", "any tips?".
  bool onlyAdvice(List<String> tokens) {
    var advice = false;
    for (final t in tokens) {
      if (t == kBreak) continue;
      final f = forms(t).toList();
      if (f.any(adviceWords.contains)) {
        advice = true;
      } else if (!f.any(fillerWords.contains)) {
        return false;
      }
    }
    return advice;
  }
}
