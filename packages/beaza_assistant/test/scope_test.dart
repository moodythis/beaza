import 'dart:convert';

import 'package:beaza_assistant/beaza_assistant.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:test/test.dart';

import 'helpers.dart';

BeazaAiAssistant make({AiLlmClient? llm}) => BeazaAiAssistant(
      settings: const GuardrailSettings(dailyLimitFils: 10000),
      llm: llm,
      llmAllowed: llm != null,
      clock: () => bh(14, 15),
    );

void main() {
  final entries = sample();
  final a = make();

  group('only questions about the person\'s money are answered', () {
    for (final q in [
      'What is the capital of France?',
      'How old is Messi?',
      'Who will win the match today?',
      'شنو عاصمة فرنسا؟',
      'كم عمر ميسي؟',
      'وين أحسن مطعم في المنامة؟',
      'Give me advice about my exams',
      'عطني نصيحة في الدراسة',
      'what day is it today?',
      'How many days are left until Eid?',
    ]) {
      test(q, () {
        final r = a.answerLocally(q, entries);
        expect(r.intent, AssistantIntent.outOfScope);
        expect(r.referencedMetrics, isEmpty);
        expect(r.replyText,
            anyOf(contains('صرفك وميزانيتك'), contains('your spending and budget')));
      });
    }

    for (final (q, intent) in [
      ('كم صرفت هالأسبوع؟', AssistantIntent.spendingQuery),
      ('How much did I spend on food this week?', AssistantIntent.spendingQuery),
      ('وين راحت فلوسي هالشهر؟', AssistantIntent.spendingQuery),
      ('كم باقي؟', AssistantIntent.spendingQuery),
      ('How much is left today?', AssistantIntent.spendingQuery),
      ('جم باقي لي من حدي اليومي؟', AssistantIntent.spendingQuery),
      ('كم صرفت على القهوة اليوم؟', AssistantIntent.spendingQuery),
      ('عطني نصيحة', AssistantIntent.guardrailAdvice),
      ('any tips?', AssistantIntent.guardrailAdvice),
      ('how can I save money?', AssistantIntent.guardrailAdvice),
      ('شريت كرك بربيتين', AssistantIntent.logExpense),
    ]) {
      test('still answered: $q', () {
        expect(a.answerLocally(q, entries).intent, intent);
      });
    }

    test('an off-topic question never reaches the model', () async {
      final llm = MockLlmClient((_) => 'Paris');
      final r = await make(llm: llm).ask('What is the capital of France?', entries);
      expect(r.intent, AssistantIntent.outOfScope);
      expect(llm.prompts, isEmpty);
    });

    test('the rules are one JSON document', () {
      final j = jsonDecode(kAssistantScopeJson) as Map<String, Object?>;
      expect(j['version'], 1);
      expect(kAssistantScope.moneyWords, contains('صرفت'));
      expect(kAssistantScope.moneyWords, contains('spend'));
      expect(kSystemPrompt, contains('Bahraini'));
    });
  });

  group('advice names the person\'s own habits', () {
    // Today is Saturday 14 Nov 2026 (Bahrain).
    final habits = ledger([
      for (var d = 9; d <= 13; d++)
        tx(1200, bh(d, 8), merchantRaw: 'KARAK HOUSE', category: 'food'),
      for (var d = 9; d <= 11; d++)
        tx(2500, bh(d, 13), merchantRaw: 'TALABAT', category: 'food'),
    ]);

    test('karak runs and delivery, with what to do instead', () {
      final r = a.answerLocally('عطني نصيحة', habits);
      expect(r.intent, AssistantIntent.guardrailAdvice);
      expect(r.replyText, contains('5 مرات هالأسبوع بـ 6.000 د.ب'));
      expect(r.replyText, contains('سوّ قهوتك بالبيت'));
      expect(r.replyText, contains('استلام من المطعم'));
      final keys = r.referencedMetrics.map((m) => m.key);
      expect(keys, containsAll(['coffee_count_week', 'delivery_week_fils']));
    });

    test('English too, and nothing named when the habits are small', () {
      final r = a.answerLocally('any tips?', habits);
      expect(r.replyText, contains('Make it at home'));
      final small = a.answerLocally('any tips?', ledger([
        tx(500, bh(13, 8), merchantRaw: 'COSTA COFFEE'),
      ]));
      expect(small.replyText, isNot(contains('at home')));
    });
  });

  group('a day of the week, and follow-ups', () {
    // Today is Saturday 14 Nov 2026 (Bahrain). Sunday was 8 Nov.
    final week = ledger([
      tx(2000, bh(8, 10), merchantRaw: 'CAFE'), // Sunday
      tx(1500, bh(8, 19), merchantRaw: 'CAFE'), // Sunday
      tx(4000, bh(12, 13), merchantRaw: 'SHOP'), // Thursday
      tx(700, bh(14, 9), merchantRaw: 'CAFE'), // today
    ]);

    test('"جم صرفت يوم الاحد" answers for Sunday only', () {
      final r = a.answerLocally('جم صرفت يوم الاحد', week);
      expect(r.intent, AssistantIntent.spendingQuery);
      expect(r.replyText, 'صرفت 3.500 د.ب يوم الأحد (2 عمليات).');
    });

    test('English, and today\'s weekday is today', () {
      expect(a.answerLocally('How much did I spend on Thursday?', week).replyText,
          'You spent BHD 4.000 on Thursday (1 purchase).');
      expect(a.answerLocally('How much did I spend on Saturday?', week).replyText,
          'You spent 700 fils today (1 purchase).');
    });

    test('"لا بس الاحد" after a question asks it again for Sunday', () {
      final r = a.answerLocally('لا بس الاحد', week, previous: 'كم صرفت هالأسبوع؟');
      expect(r.intent, AssistantIntent.spendingQuery);
      expect(r.replyText, 'صرفت 3.500 د.ب يوم الأحد (2 عمليات).');
      final y = a.answerLocally('and yesterday?', week,
          previous: 'How much did I spend this week?');
      expect(y.replyText, contains('yesterday'));
    });

    test('"أحد" without "ال" is not Sunday, and no follow-up without a question before', () {
      expect(a.answerLocally('لا بس الاحد', week).intent, AssistantIntent.unknown);
      expect(a.answerLocally('هل احد يعرف؟', week).intent, AssistantIntent.outOfScope);
    });
  });

  group('can I buy it?', () {
    test('a laptop for 300 BD with a budget plan: the limit it leaves', () {
      final r = a.answerLocally(
          'الحين لو اخذت لابتوب ب ٣٠٠ دينار هلي يمديني؟', entries,
          afford: const AffordFacts(
              monthLeftFils: 72600, limitFromTomorrowFils: 3821, limitIfBoughtFils: 0));
      expect(r.intent, AssistantIntent.canIBuy);
      expect(r.replyText, contains('300.000 د.ب أكثر من كل اللي باقي لك هالشهر (72.600 د.ب)'));
    });

    test('it fits, but the limit drops', () {
      final r = a.answerLocally('Can I afford a phone for 40 BD?', entries,
          afford: const AffordFacts(
              monthLeftFils: 72600, limitFromTomorrowFils: 3821, limitIfBoughtFils: 1716));
      expect(r.replyText,
          'You can, but you will have to cut back: from tomorrow your daily limit drops from BHD 3.821 to BHD 1.716 until the end of the month. That is less than half your limit, so if it can wait, leave it to next month or save up for it.');
    });

    test('only a daily limit: days of the limit and how long to save', () {
      // Limit 10.000, nothing spent today (14 Nov) in sample() except 3.900.
      final r = a.answerLocally('يمديني اشتري سماعة ب 50 دينار؟', entries);
      expect(r.intent, AssistantIntent.canIBuy);
      expect(r.replyText, contains('50.000 د.ب تساوي 5 يوم من حدك اليومي (10.000 د.ب)'));
      expect(r.replyText, contains('نص حدك كل يوم (5.000 د.ب)، بتجمعه في 10 يوم'));
    });

    test('a log is still a log', () {
      expect(a.answerLocally('شريت كرك بربيتين', entries).intent,
          AssistantIntent.logExpense);
    });
  });
}
