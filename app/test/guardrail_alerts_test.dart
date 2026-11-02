import 'package:beaza/data/repositories/alert_log_store.dart';
import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/domain/use_cases/guardrail_alerts.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/core/alert_text.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime bh(int day, int hour) =>
    DateTime.utc(2026, 11, day, hour).subtract(kBahrainOffset);

void main() {
  late InMemoryLedgerRepository ledger;
  late InMemorySettingsRepository settings;
  late MemoryAlertLogStore logs;
  late List<GuardrailAlert> shown;
  late GuardrailAlerts alerts;

  setUp(() {
    ledger = InMemoryLedgerRepository();
    settings = InMemorySettingsRepository(
        const GuardrailSettings(dailyLimitFils: 4000));
    logs = MemoryAlertLogStore();
    shown = [];
    alerts = GuardrailAlerts(
      ledger: ledger,
      settings: settings,
      logs: logs,
      present: (a) async => shown.add(a),
      clock: () => bh(3, 12),
    );
  });

  test('the case from the phone: limit 4.000, spent 2.000 -> 50% alert',
      () async {
    await ledger.addManual(amountFils: 2000, at: bh(3, 9));
    final a = await alerts.evaluate();
    expect(a?.level, AlertLevel.level1);
    expect(shown, hasLength(1));
  });

  test('under 50% stays quiet', () async {
    await ledger.addManual(amountFils: 1000, at: bh(3, 9));
    expect(await alerts.evaluate(), isNull);
    expect(shown, isEmpty);
  });

  test('each level once; the log survives (as after closing the app)',
      () async {
    await ledger.addManual(amountFils: 2000, at: bh(3, 9));
    await alerts.evaluate();
    await alerts.evaluate();
    expect(shown.map((a) => a.level), [AlertLevel.level1]);

    await ledger.addManual(amountFils: 1300, at: bh(3, 10));
    await alerts.evaluate();
    await ledger.addManual(amountFils: 1000, at: bh(3, 11));
    await alerts.evaluate();
    expect(shown.map((a) => a.level),
        [AlertLevel.level1, AlertLevel.level2, AlertLevel.level3]);
    expect(logs.logs[const Day(2026, 11, 3)]!.sent, 3);
  });

  test('overlapping evaluations send one alert', () async {
    await ledger.addManual(amountFils: 2000, at: bh(3, 9));
    await Future.wait([alerts.evaluate(), alerts.evaluate(), alerts.evaluate()]);
    expect(shown, hasLength(1));
  });

  test('lowering the limit can trigger an alert', () async {
    await ledger.addManual(amountFils: 1000, at: bh(3, 9));
    await alerts.evaluate();
    await settings.save(const GuardrailSettings(dailyLimitFils: 1200));
    expect((await alerts.evaluate())?.level, AlertLevel.level2);
  });

  test('a failing notification does not throw', () async {
    final failing = GuardrailAlerts(
      ledger: ledger,
      settings: settings,
      logs: logs,
      present: (_) async => throw Exception('no permission'),
      clock: () => bh(3, 12),
    );
    await ledger.addManual(amountFils: 2000, at: bh(3, 9));
    expect(await failing.evaluate(), isNull);
  });

  group('notification text', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final ar = lookupAppLocalizations(const Locale('ar'));
    const g = Guardrail(GuardrailSettings(dailyLimitFils: 4000));

    GuardrailAlert alertFor(List<int> amounts, AlertLevel level,
        {bool micro = false}) {
      final entries = [
        for (var i = 0; i < amounts.length; i++)
          LedgerEntry(
            index: i,
            role: EntryRole.spending,
            result: ExtractionResult(
              status: ExtractionStatus.transaction,
              amountFils: amounts[i],
              currency: 'BHD',
              direction: TxDirection.outgoing,
              timestamp: bh(3, 9 + i),
            ),
          ),
      ];
      return GuardrailAlert(
        summary: g.summarize(entries, const Day(2026, 11, 3)),
        level: level,
        includesMicroTotal: micro,
      );
    }

    test('50% in English, amount first', () {
      final t = alertText(en, alertFor([2000], AlertLevel.level1));
      expect(t.title, "Half of today's limit used");
      expect(t.body, 'Spent BHD 2.000 · BHD 2.000 left today');
    });

    test('100% in Arabic shows the overrun', () {
      final t = alertText(ar, alertFor([5000], AlertLevel.level3));
      expect(t.title, 'وصلت إلى حد اليوم');
      expect(t.body, 'صرفت 5.000 د.ب · تجاوزت حد اليوم بـ 1.000 د.ب');
    });

    test('80% lists the small expenses', () {
      final t = alertText(en, alertFor([1600, 1700], AlertLevel.level2));
      expect(t.body.split('\n').last, '2 small expenses today · BHD 3.300');
    });

    test('one id per day', () {
      expect(alertId(const Day(2026, 11, 3)), 20261103);
    });
  });
}
