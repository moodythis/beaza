import 'package:beaza_assistant/beaza_assistant.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:test/test.dart';

import 'helpers.dart';

BeazaAiAssistant make({int limit = 10000, AiLlmClient? llm, bool allowed = false}) =>
    BeazaAiAssistant(
      settings: GuardrailSettings(dailyLimitFils: limit),
      llm: llm,
      llmAllowed: allowed,
      clock: () => bh(14, 15),
    );

void main() {
  final entries = sample();

  group('offline answers (rules and fils on the phone)', () {
    final a = make();

    test('spending this week', () {
      final r = a.answerLocally('كم صرفت هالأسبوع؟', entries);
      expect(r.intent, AssistantIntent.spendingQuery);
      expect(r.replyText, 'صرفت 19.150 د.ب في آخر 7 أيام (3 عمليات).');
      expect(r.referencedMetrics.first.value, 19150);
      expect(r.source, ResponseSource.local);
    });

    test('coffee today, by shop name', () {
      final r = a.answerLocally('كم صرفت على القهوة اليوم؟', entries);
      expect(r.intent, AssistantIntent.spendingQuery);
      expect(r.replyText, contains('3.900 د.ب على القهوة والكافيهات اليوم'));
      expect(r.replyText, contains('حسب أسماء المحلات'));
    });

    test('where did my money go this month', () {
      final r = a.answerLocally('وين راحت فلوسي هالشهر؟', entries);
      expect(r.replyText,
          'صرفت 20.150 د.ب هالشهر. أكثرها: التسوق 13.200 د.ب (66٪)، الأكل والمطاعم 4.900 د.ب (24٪)، غير مصنّف 2.050 د.ب (10٪).');
    });

    test('what is left of the daily limit', () {
      final r = a.answerLocally('جم باقي لي من حدي اليومي؟', entries);
      expect(r.replyText,
          'باقي لك 6.100 د.ب من حدك اليوم (10.000 د.ب). صرفت 3.900 د.ب لين الحين.');
      expect(r.referencedMetrics.map((m) => m.key),
          containsAll(['spent_today_fils', 'limit_fils', 'remaining_fils']));
    });

    test('over the limit', () {
      final r = make(limit: 3000).answerLocally('كم باقي؟', entries);
      expect(r.replyText,
          'تعديت حدك اليوم بـ 900 فلس. صرفت 3.900 د.ب من 3.000 د.ب.');
    });

    test('no limit set', () {
      final r = make(limit: 0).answerLocally('كم باقي لي؟', entries);
      expect(r.replyText, contains('ما حطيت حد يومي'));
    });

    test('advice from the guardrail state and the week', () {
      final r = a.answerLocally('عطني نصيحة', entries);
      expect(r.intent, AssistantIntent.guardrailAdvice);
      expect(r.replyText, contains('39٪'));
      expect(r.replyText, contains('6.100 د.ب'));
      expect(r.replyText, contains('التسوق 20٪'));
      expect(r.replyText, contains('2.640 د.ب'));
    });

    test('logging cash gives drafts, not saved entries', () {
      final r = a.answerLocally('شريت كرك بربيتين', entries);
      expect(r.intent, AssistantIntent.logExpense);
      expect(r.draftTransactions.single.amountFils, 200);
      expect(r.replyText, 'جهزت لك: كرك 200 فلس. أكّد قبل الحفظ.');
    });

    test('two items show the total', () {
      final r = a.answerLocally('شاورما بـ 800 فلس وكرك بـ 200 فلس', entries);
      expect(r.draftTransactions, hasLength(2));
      expect(r.replyText, contains('المجموع 1.000 د.ب'));
    });

    test('English question', () {
      final r = a.answerLocally('How much did I spend on food this week?', entries);
      expect(r.replyText,
          'You spent BHD 3.900 on food in the last 7 days (1 purchase).');
    });

    test('not understood', () {
      final r = a.answerLocally('مرحبا', entries);
      expect(r.intent, AssistantIntent.unknown);
      expect(r.replyText, contains('ما فهمت'));
    });
  });

  group('with a language model (optional, rewording only)', () {
    test('a reply with the same numbers is used; nothing private is sent', () async {
      final llm = MockLlmClient((_) => 'هالأسبوع صرفت ١٩٫١٥٠ د.ب في 3 عمليات.');
      final r = await make(llm: llm, allowed: true).ask('كم صرفت هالأسبوع؟', entries);
      expect(r.source, ResponseSource.llm);
      expect(r.replyText, 'هالأسبوع صرفت ١٩٫١٥٠ د.ب في 3 عمليات.');
      final sent = llm.prompts.single.contextJson;
      for (final secret in ['4810', 'COSTA', 'Costa', 'Waleed', 'REDTAG', 'REF']) {
        expect(sent, isNot(contains(secret)), reason: secret);
      }
      expect(sent, contains('19150'));
    });

    test('a reply with a number it invented is thrown away', () async {
      final llm = MockLlmClient((_) => 'صرفت 20 د.ب هالأسبوع.');
      final r = await make(llm: llm, allowed: true).ask('كم صرفت هالأسبوع؟', entries);
      expect(r.source, ResponseSource.local);
      expect(r.replyText, 'صرفت 19.150 د.ب في آخر 7 أيام (3 عمليات).');
    });

    test('a failing model falls back to the offline answer', () async {
      final llm = MockLlmClient((_) => throw StateError('offline'));
      final r = await make(llm: llm, allowed: true).ask('كم صرفت هالأسبوع؟', entries);
      expect(r.source, ResponseSource.local);
    });

    test('without consent the model is never called', () async {
      final llm = MockLlmClient((_) => 'x');
      await make(llm: llm).ask('كم صرفت هالأسبوع؟', entries);
      expect(llm.prompts, isEmpty);
    });

    test('drafts never go to the model', () async {
      final llm = MockLlmClient((_) => 'x');
      final r = await make(llm: llm, allowed: true).ask('شريت كرك بربيتين', entries);
      expect(llm.prompts, isEmpty);
      expect(r.intent, AssistantIntent.logExpense);
    });
  });
}
