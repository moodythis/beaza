import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:test/test.dart';

/// A Bahrain local time in November 2026, as the UTC instant the app stores.
DateTime bh(int day, int hour, [int minute = 0]) =>
    DateTime.utc(2026, 11, day, hour, minute).subtract(kBahrainOffset);

var _next = 0;

LedgerEntry spend(int fils, DateTime at,
        {EntryRole role = EntryRole.spending, String currency = 'BHD'}) =>
    LedgerEntry(
      index: _next++,
      role: role,
      result: ExtractionResult(
        status: ExtractionStatus.transaction,
        amountFils: fils,
        currency: currency,
        direction: TxDirection.outgoing,
        timestamp: at,
      ),
    );

void main() {
  const settings = GuardrailSettings(dailyLimitFils: 10000);
  const g = Guardrail(settings);
  const planner = AlertPlanner(settings);
  const today = Day(2026, 11, 2);

  group('Bahrain day', () {
    test('day starts at 21:00 UTC the day before', () {
      expect(today.startUtc, DateTime.utc(2026, 11, 1, 21));
      expect(today.endUtc, DateTime.utc(2026, 11, 2, 21));
    });

    test('an instant after 21:00 UTC belongs to the next Bahrain day', () {
      expect(Day.of(DateTime.utc(2026, 11, 1, 21, 30)), today);
      expect(Day.of(DateTime.utc(2026, 11, 1, 20, 59)), const Day(2026, 11, 1));
    });

    test('month and year boundaries', () {
      expect(const Day(2026, 12, 31).addDays(1), const Day(2027, 1, 1));
      expect(const Day(2026, 3, 1).previous, const Day(2026, 2, 28));
      expect(today.toString(), '2026-11-02');
    });
  });

  group('suggested limit', () {
    test('design example: (250 - 60 - 30) / 30 = 5.333', () {
      expect(
          GuardrailSettings.suggestedDailyLimitFils(
            monthlyIncomeFils: 250000,
            fixedCommitmentsFils: 60000,
            savingsTargetFils: 30000,
            cycleDays: 30,
          ),
          5333);
    });

    test('never negative', () {
      expect(
          GuardrailSettings.suggestedDailyLimitFils(
            monthlyIncomeFils: 100000,
            fixedCommitmentsFils: 90000,
            savingsTargetFils: 20000,
            cycleDays: 30,
          ),
          0);
    });

    test('copyWith changes one field and keeps the rest', () {
      final s = const GuardrailSettings(dailyLimitFils: 1, alertCap: 2)
          .copyWith(dailyLimitFils: 9000);
      expect(s.dailyLimitFils, 9000);
      expect(s.alertCap, 2);
      expect(s.microThresholdFils, 5000);
    });

    test('zero days is rejected', () {
      expect(
          () => GuardrailSettings.suggestedDailyLimitFils(
                monthlyIncomeFils: 1,
                fixedCommitmentsFils: 0,
                savingsTargetFils: 0,
                cycleDays: 0,
              ),
          throwsArgumentError);
    });
  });

  group('summary', () {
    test('only BHD spending on the Bahrain day counts', () {
      final entries = [
        spend(2000, bh(2, 9)),
        spend(1500, bh(2, 23, 59)),
        spend(9000, bh(1, 23, 59)), // yesterday
        spend(4000, bh(3, 0, 0)), // tomorrow
        spend(3000, bh(2, 10), role: EntryRole.income),
        spend(3000, bh(2, 10), role: EntryRole.internalTransfer),
        spend(3000, bh(2, 10), role: EntryRole.duplicate),
        spend(3000, bh(2, 10), currency: 'USD'),
      ];
      final s = g.summarize(entries, today);
      expect(s.spentFils, 3500);
      expect(s.spendingCount, 2);
      expect(s.remainingFils, 6500);
      expect(s.percentUsed, 35);
      expect(s.level, AlertLevel.normal);
    });

    test('remaining goes negative past the limit', () {
      final s = g.summarize([spend(12500, bh(2, 9))], today);
      expect(s.remainingFils, -2500);
      expect(s.percentUsed, 125);
      expect(s.level, AlertLevel.level3);
    });

    test('levels at exactly 50, 80 and 100 percent', () {
      expect(g.levelFor(4999, 10000), AlertLevel.normal);
      expect(g.levelFor(5000, 10000), AlertLevel.level1);
      expect(g.levelFor(7999, 10000), AlertLevel.level1);
      expect(g.levelFor(8000, 10000), AlertLevel.level2);
      expect(g.levelFor(10000, 10000), AlertLevel.level3);
    });

    test('no limit set: totals work, level stays normal', () {
      const off = Guardrail(GuardrailSettings(dailyLimitFils: 0));
      final s = off.summarize([spend(50000, bh(2, 9))], today);
      expect(s.spentFils, 50000);
      expect(s.percentUsed, 0);
      expect(s.level, AlertLevel.normal);
    });
  });

  group('micro-expenses', () {
    test('at or below 5.000 BHD, latest three newest first', () {
      final a = spend(500, bh(2, 8));
      final b = spend(5000, bh(2, 9)); // exactly the threshold
      final c = spend(5001, bh(2, 10)); // above
      final d = spend(1200, bh(2, 11));
      final e = spend(800, bh(2, 12));
      final s = g.summarize([e, c, a, d, b], today);
      expect(s.micro.count, 4);
      expect(s.micro.totalFils, 7500);
      expect(s.latestMicro.map((x) => x.result.amountFils), [800, 1200, 5000]);
    });

    test('weekly view covers the seven days ending today', () {
      final week = [
        spend(1000, DateTime.utc(2026, 10, 26, 21)), // Oct 27 00:00 Bahrain
        spend(2000, DateTime.utc(2026, 10, 26, 20, 59)), // Oct 26, outside
        spend(3000, bh(2, 20)),
        spend(9000, bh(2, 21)), // not micro
      ];
      final w = g.weeklyMicro(week, today);
      expect(w.count, 2);
      expect(w.totalFils, 4000);
    });
  });

  group('rollover', () {
    const ro = Guardrail(GuardrailSettings(dailyLimitFils: 10000, rollover: true));

    test('off by default', () {
      expect(g.rolloverFor([spend(1000, bh(1, 9))], today), 0);
    });

    test('unspent yesterday carries, capped at 50 percent', () {
      expect(ro.rolloverFor([spend(8000, bh(1, 9))], today), 2000);
      expect(ro.rolloverFor([spend(1000, bh(1, 9))], today), 5000);
      expect(ro.rolloverFor([spend(12000, bh(1, 9))], today), 0);
    });

    test('rollover raises the effective limit', () {
      final s = ro.summarize([spend(8000, bh(1, 9)), spend(9000, bh(2, 9))], today);
      expect(s.limitFils, 12000);
      expect(s.remainingFils, 3000);
      expect(s.level, AlertLevel.level1); // 75 percent
    });
  });

  group('alerts', () {
    final now = bh(2, 12);

    AlertDecision run(List<LedgerEntry> es, AlertLog? log,
            {DateTime? at, DateTime? snooze}) =>
        planner.decide(g.summarize(es, today), log,
            now: at ?? now, snoozedUntil: snooze);

    test('nothing under 50 percent', () {
      final d = run([spend(4000, bh(2, 9))], null);
      expect(d.alert, isNull);
      expect(d.log.sent, 0);
    });

    test('each level alerts once, in order', () {
      final es = [spend(5000, bh(2, 9))];
      final d1 = run(es, null);
      expect(d1.alert!.level, AlertLevel.level1);
      expect(run(es, d1.log).alert, isNull);

      es.add(spend(3000, bh(2, 10)));
      final d2 = run(es, d1.log);
      expect(d2.alert!.level, AlertLevel.level2);

      es.add(spend(2000, bh(2, 11)));
      final d3 = run(es, d2.log);
      expect(d3.alert!.level, AlertLevel.level3);
      expect(d3.logLimitExceeded, isTrue);
      expect(d3.log.sent, 3);
    });

    test('jumping past several levels gives one alert at the highest', () {
      final d = run([spend(11000, bh(2, 9))], null);
      expect(d.alert!.level, AlertLevel.level3);
      expect(d.log.sent, 1);
    });

    test('dropping back after an edit does not repeat the alert', () {
      final d1 = run([spend(8000, bh(2, 9))], null);
      final d2 = run([spend(4000, bh(2, 9))], d1.log); // edited down
      expect(d2.alert, isNull);
      final d3 = run([spend(8500, bh(2, 9))], d2.log); // back up
      expect(d3.alert, isNull);
    });

    test('micro total shown once after three micro-expenses', () {
      final es = [spend(500, bh(2, 8)), spend(600, bh(2, 9))];
      expect(run(es, null).alert, isNull);
      es.add(spend(700, bh(2, 10)));
      final d = run(es, null);
      expect(d.alert!.includesMicroTotal, isTrue);
      expect(d.alert!.level, AlertLevel.normal);
      es.add(spend(800, bh(2, 11)));
      expect(run(es, d.log).alert, isNull);
    });

    test('micro total rides along with a level alert as one', () {
      final es = [
        spend(2000, bh(2, 8)),
        spend(2000, bh(2, 9)),
        spend(2000, bh(2, 10)),
      ];
      final d = run(es, null);
      expect(d.alert!.level, AlertLevel.level1);
      expect(d.alert!.includesMicroTotal, isTrue);
      expect(d.log.sent, 1);
    });

    test('cap of four per day', () {
      const tight = GuardrailSettings(dailyLimitFils: 10000, alertCap: 1);
      final d1 = const AlertPlanner(tight).decide(
          g.summarize([spend(5000, bh(2, 9))], today), null,
          now: now);
      expect(d1.alert, isNotNull);
      final d2 = const AlertPlanner(tight).decide(
          g.summarize([spend(9000, bh(2, 9))], today), d1.log,
          now: now);
      expect(d2.alert, isNull);
      expect(d2.suppressed, SuppressReason.capReached);
      expect(settings.alertCap, 4);
    });

    test('snooze holds alerts, the due level fires after it ends', () {
      final es = [spend(8000, bh(2, 9))];
      final held = run(es, null, snooze: bh(2, 13));
      expect(held.alert, isNull);
      expect(held.suppressed, SuppressReason.snoozed);
      expect(held.log.sent, 0);
      final after = run(es, held.log, at: bh(2, 14), snooze: bh(2, 13));
      expect(after.alert!.level, AlertLevel.level2);
    });

    test('limit-exceeded event is logged even while snoozed, once', () {
      final es = [spend(10000, bh(2, 9))];
      final d1 = run(es, null, snooze: bh(2, 23));
      expect(d1.logLimitExceeded, isTrue);
      expect(d1.alert, isNull);
      final d2 = run(es, d1.log, snooze: bh(2, 23));
      expect(d2.logLimitExceeded, isFalse);
    });

    test('a new limit starts the levels again (the phone case)', () {
      // Limit 4.000: 50% then 100% were alerted earlier in the day.
      const small = GuardrailSettings(dailyLimitFils: 4000);
      final d1 = const AlertPlanner(small).decide(
          const Guardrail(small).summarize([spend(4000, bh(2, 1))], today),
          null,
          now: now);
      expect(d1.alert!.level, AlertLevel.level3);

      // The user raises the limit to 10.000; 5.000 spent is 50% of the new one.
      const big = GuardrailSettings(dailyLimitFils: 10000);
      final d2 = const AlertPlanner(big).decide(
          const Guardrail(big).summarize([spend(5000, bh(2, 1))], today),
          d1.log,
          now: now);
      expect(d2.alert?.level, AlertLevel.level1);
      expect(d2.log.sent, 2); // the daily cap still counts both
    });

    test('the same limit keeps the levels already sent', () {
      final d1 = run([spend(5000, bh(2, 9))], null);
      expect(d1.log.limitFils, 10000);
      expect(run([spend(5500, bh(2, 9))], d1.log).alert, isNull);
    });

    test('a log from another day is ignored', () {
      const old = AlertLog(
          day: Day(2026, 11, 1), sent: 4, highestLevel: AlertLevel.level3);
      final d = run([spend(5000, bh(2, 9))], old);
      expect(d.alert!.level, AlertLevel.level1);
      expect(d.log.day, today);
    });
  });

  // Seen on a real phone, 12 November 2026: BHD 2.050 came back at 14:37 and
  // a BHD 1.000 payment at 18:54 left "spent today" at 0.000.
  test('money paid back hides a later payment from spent, but both are kept', () {
    final back = LedgerEntry(
      index: _next++,
      role: EntryRole.repayment,
      result: ExtractionResult(
        status: ExtractionStatus.transaction,
        amountFils: 2050,
        currency: 'BHD',
        direction: TxDirection.incoming,
        timestamp: bh(2, 14, 37),
      ),
    );
    final s = g.summarize([back, spend(1000, bh(2, 18, 54))], today);
    expect(s.spentFils, 0);
    expect(s.grossSpentFils, 1000);
    expect(s.paidBackFils, 2050);
  });
}
