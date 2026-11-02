import 'package:beaza/data/repositories/alert_log_store.dart';
import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza_extraction/beaza_extraction.dart';

/// Shows one alert (the app turns it into a localized notification).
typedef AlertPresenter = Future<void> Function(GuardrailAlert alert);

/// Recomputes today's guardrail after every change and alerts when a
/// threshold is crossed (Design 4.2): 50%, 80%, 100%, the micro-expense
/// total once, at most four alerts a day. Advisory only, never blocks.
class GuardrailAlerts {
  GuardrailAlerts({
    required LedgerRepository ledger,
    required SettingsRepository settings,
    required AlertLogStore logs,
    required AlertPresenter present,
    DateTime Function()? clock,
  })  : _ledger = ledger,
        _settings = settings,
        _logs = logs,
        _present = present,
        _clock = clock ?? DateTime.now;

  final LedgerRepository _ledger;
  final SettingsRepository _settings;
  final AlertLogStore _logs;
  final AlertPresenter _present;
  final DateTime Function() _clock;

  Future<void> _queue = Future.value();

  /// Runs one evaluation at a time, so two quick changes cannot both read
  /// the same log and send the same alert twice.
  Future<GuardrailAlert?> evaluate() {
    final run = _queue.then((_) => _evaluate());
    _queue = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  Future<GuardrailAlert?> _evaluate() async {
    try {
      final now = _clock();
      final settings = await _settings.load();
      final entries = await _ledger.entries();
      final day = Day.of(now);
      final summary = Guardrail(settings).summarize(entries, day);
      final decision = AlertPlanner(settings)
          .decide(summary, await _logs.load(day), now: now);
      await _logs.save(decision.log);
      final alert = decision.alert;
      if (alert != null) await _present(alert);
      return alert;
    } on Exception {
      // An alert that fails must never break saving a transaction.
      return null;
    }
  }
}
