import 'dart:convert';

import 'package:beaza_assistant/beaza_assistant.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  const today = Day(2026, 11, 14);
  final s = SpendingSummaryBuilder(sample(),
      settings: const GuardrailSettings(dailyLimitFils: 10000), today: today);

  group('SpendingSummaryBuilder (integer fils)', () {
    test('totals per period; received money and USD left out', () {
      expect(s.total(Period.of(PeriodKind.today, today)), 3900);
      expect(s.total(Period.of(PeriodKind.week, today)), 19150);
      expect(s.total(Period.of(PeriodKind.month, today)), 20150);
      expect(s.total(Period.of(PeriodKind.yesterday, today)), 0);
      expect(s.count(Period.of(PeriodKind.week, today)), 3);
    });

    test('period lengths', () {
      expect(Period.of(PeriodKind.week, today).days, 7);
      expect(Period.of(PeriodKind.month, today).days, 14);
    });

    test('shares are rounded whole percents, largest first', () {
      final b = s.byBucket(Period.of(PeriodKind.week, today));
      expect(b.map((x) => '${x.bucket}:${x.totalFils}:${x.percent}'),
          ['shopping:13200:69', 'food:3900:20', 'unsorted:2050:11']);
    });

    test('percentOf', () {
      expect(percentOf(1, 3), 33);
      expect(percentOf(2, 3), 67);
      expect(percentOf(5, 0), 0);
    });

    test('today against the limit, and small purchases', () {
      final d = s.todaySummary();
      expect(d.spentFils, 3900);
      expect(d.remainingFils, 6100);
      expect(d.percentUsed, 39);
      final m = s.microIn(Period.of(PeriodKind.week, today));
      expect([m.count, m.totalFils], [2, 5950]);
    });
  });

  group('AiContextSanitizer', () {
    const z = AiContextSanitizer();

    test('masks phones, IBANs, e-mails and card numbers, keeps amounts', () {
      final out = z.sanitizeText(
          'رقمي 3333 4444 وحسابي BH93BIBB00200000006142 وايميلي a.b@x.com وبطاقة 7744 ودفعت 2.500 د.ب و800 فلس');
      for (final secret in ['3333', '4444', 'BH93', 'a.b@x.com', '7744']) {
        expect(out, isNot(contains(secret)), reason: secret);
      }
      expect(out, contains('2.500 د.ب'));
      expect(out, contains('800 فلس'));
    });

    test('one transaction keeps only the allowed fields', () {
      final e = ledger([
        tx(2050, bh(10, 16),
            merchantRaw: 'Waleed Al Kabah MANAMA',
            merchantNorm: 'Waleed Al Kabah',
            last4: '4810',
            counterpartyLast4: '9417',
            reference: 'NBB241026ONH8WCQ'),
      ]).single;
      final json = jsonEncode(z.entry(e));
      for (final secret in ['4810', '9417', 'NBB241026', 'Waleed', 'MANAMA']) {
        expect(json, isNot(contains(secret)), reason: secret);
      }
      expect(z.entry(e)['amount_fils'], 2050);
      expect(z.entry(e)['date'], '2026-11-10');
      expect(z.entry(e)['merchant'], isNull);
    });

    test('a known chain keeps its name', () {
      expect(z.entry(sample().first)['merchant'], 'Costa Coffee');
    });

    test('the context has only intent, language, masked words and numbers', () {
      final c = z.context(
        intent: AssistantIntent.spendingQuery,
        language: 'ar-gulf',
        question: 'كم صرفت؟ رقمي 33334444',
        metrics: const [Metric('total_fils', 1500, MetricUnit.fils, display: '1.500 د.ب')],
        draftReply: 'صرفت 1.500 د.ب',
      );
      expect(c.keys, ['intent', 'language', 'question', 'metrics', 'draft_reply']);
      expect(jsonEncode(c), isNot(contains('33334444')));
    });
  });

  group('NumberGuard', () {
    const g = NumberGuard();
    test('the same number written differently is allowed', () {
      expect(g.allows('صرفت ٢٫٥ دينار', ['2.500 د.ب']), isTrue);
    });
    test('a new number is refused', () {
      expect(g.allows('صرفت 20 د.ب', ['صرفت 19.150 د.ب']), isFalse);
    });
    test('empty or too long is refused', () {
      expect(g.allows('  ', ['1']), isFalse);
      expect(g.allows('a' * 401, ['1']), isFalse);
    });
  });
}
