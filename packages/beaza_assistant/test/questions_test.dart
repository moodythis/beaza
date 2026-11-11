// The everyday spending questions people ask, in Gulf Arabic and English.
import 'package:beaza_assistant/beaza_assistant.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  // Today is Saturday 14 Nov 2026 (Bahrain); limit 10.000.
  final a = BeazaAiAssistant(
    settings: const GuardrailSettings(dailyLimitFils: 10000),
    clock: () => bh(14, 15),
  );
  final entries = ledger([
    tx(2500, bh(8, 10), merchantRaw: 'STARBUCKS SEEF', category: 'food'),
    tx(15000, bh(9, 20), merchantRaw: 'LULU HYPERMARKET', category: 'groceries'),
    tx(1800, bh(10, 13), merchantRaw: 'STARBUCKS SEEF', category: 'food'),
    tx(8000, bh(12, 21), merchantRaw: 'REDTAG', category: 'shopping'),
    tx(1700, bh(14, 9), merchantRaw: 'STARBUCKS SEEF', category: 'food'),
    tx(10000, bh(3, 12), merchantRaw: 'LULU HYPERMARKET', category: 'groceries'),
    tx(2000, bh(5, 12), merchantRaw: 'CAFE', category: 'food'),
    tx(3500, bh(11, 17), merchantRaw: 'مرفأ الأطفال', category: 'entertainment'),
  ]);
  String ask(String q) => a.answerLocally(q, entries).replyText;

  test('biggest purchase', () {
    for (final q in ['وش أكبر مصروف هالأسبوع؟', 'What was my biggest purchase this week?']) {
      expect(ask(q), allOf(contains('15.000'), contains('LULU HYPERMARKET')), reason: q);
    }
    expect(ask('وش أكبر مصروف هالأسبوع؟'), contains('يوم الاثنين'));
  });

  test('the shop with most spending', () {
    expect(ask('أكثر محل صرفت فيه هالأسبوع؟'),
        'أكثر محل صرفت فيه في آخر 7 أيام: LULU HYPERMARKET، 15.000 د.ب (مرة وحدة).');
    expect(ask('Which shop did I spend the most at?'), contains('LULU HYPERMARKET'));
  });

  test('against the week before', () {
    for (final q in ['صرفت أكثر من الأسبوع اللي فات؟', 'Did I spend more than last week?']) {
      expect(ask(q), allOf(contains('32.500'), contains('12.000'), contains('20.500'), contains('171')),
          reason: q);
    }
  });

  test('average a day', () {
    expect(ask('كم معدل صرفي باليوم؟'),
        'معدل صرفك في آخر 7 أيام: 4.642 د.ب باليوم (32.500 د.ب على 7 أيام). وهذا ضمن حدك (10.000 د.ب).');
    expect(ask('What is my average daily spending?'), contains('BHD 4.642 a day'));
  });

  test('where the month ends at this pace', () {
    for (final q in ['كم بصرف آخر الشهر بهالمعدل؟', 'How much will I spend by the end of the month?']) {
      expect(ask(q), allOf(contains('44.500'), contains('95.357')), reason: q);
    }
  });

  test('days over the limit', () {
    expect(ask('كم يوم تعديت حدي هالأسبوع؟'), 'تعديت حدك 1 من 7 أيام في آخر 7 أيام.');
    expect(ask('How many days did I go over my limit?'), contains('1 of 7 days'));
  });

  test('a named shop', () {
    expect(ask('كم صرفت في starbucks هالأسبوع؟'),
        'صرفت 6.000 د.ب في STARBUCKS SEEF في آخر 7 أيام (3 عمليات).');
    expect(ask('How much did I spend at Starbucks this week?'),
        'You spent BHD 6.000 at STARBUCKS SEEF in the last 7 days (3 purchases).');
  });

  test('last week and last month', () {
    expect(ask('كم صرفت الأسبوع اللي فات؟'),
        'صرفت 12.000 د.ب في الأسبوع اللي قبله (2 عمليات).');
    expect(ask('How much did I spend last month?'), 'Nothing spent last month.');
  });

  test('the plain questions still work', () {
    expect(ask('كم صرفت هالأسبوع؟'), 'صرفت 32.500 د.ب في آخر 7 أيام (6 عمليات).');
    expect(a.answerLocally('كم باقي؟', entries).replyText, contains('باقي لك'));
  });

  test('a shop named in Arabic, written with or without spaces', () {
    for (final q in ['دفعت لمرفأالاطفال كم؟', 'كم صرفت في مرفأ الأطفال؟', 'كم دفعت لمرفا الاطفال هالأسبوع']) {
      expect(ask(q), 'صرفت 3.500 د.ب في مرفأ الأطفال في آخر 7 أيام (عملية وحدة).', reason: q);
    }
    expect(ask('دفعت لصالون النخيل كم؟'),
        'ما لقيت مشتريات مسجلة باسم «صالون النخيل» في قائمتك.');
    expect(ask('كم صرفت هالأسبوع يا بيزة؟'), contains('32.500'));
    expect(ask('كم صرفت في الويكند؟'), isNot(contains('ما لقيت')));
  });

  test('"what if I spend 4 today" is a question, never an expense to add', () {
    final r = a.answerLocally('لو صرفت ٤ في اليوم ويش يصير', entries);
    expect(r.intent, AssistantIntent.canIBuy);
    expect(r.draftTransactions, isEmpty);
    expect(r.replyText, contains('4.000'));
    expect(a.answerLocally('إذا دفعت 3 دينار شنو يصير؟', entries).intent,
        AssistantIntent.canIBuy);
  });
}
