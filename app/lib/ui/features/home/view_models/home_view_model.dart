import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/foundation.dart';

/// What the home screen shows for one Bahrain day. Immutable snapshot.
@immutable
class HomeState {
  const HomeState({
    required this.summary,
    required this.today,
    required this.weekMicro,
  });

  final DaySummary summary;

  /// Today's counted spending, newest first.
  final List<LedgerEntry> today;
  final MicroStats weekMicro;
}

class HomeViewModel extends ChangeNotifier {
  HomeViewModel({
    required LedgerRepository ledger,
    required SettingsRepository settings,
    DateTime Function()? clock,
  })  : _ledger = ledger,
        _settings = settings,
        _clock = clock ?? DateTime.now {
    _ledger.addListener(load);
    _settings.addListener(load);
  }

  final LedgerRepository _ledger;
  final SettingsRepository _settings;
  final DateTime Function() _clock;

  HomeState? _state;
  HomeState? get state => _state;

  bool _loading = false;
  bool get isLoading => _loading;

  Object? _error;
  Object? get error => _error;

  bool _disposed = false;

  /// Recomputes everything from the ledger (FR-5.1), so an edit or a
  /// deletion can move the day back to a lower alert state.
  Future<void> load() async {
    _loading = true;
    _notify();
    try {
      final entries = await _ledger.entries();
      final settings = await _settings.load();
      final guardrail = Guardrail(settings);
      final day = Day.of(_clock());
      _state = HomeState(
        summary: guardrail.summarize(entries, day),
        today: guardrail.spendingOn(entries, day).reversed.toList(),
        weekMicro: guardrail.weeklyMicro(entries, day),
      );
      _error = null;
    } on Exception catch (e) {
      _error = e;
    } finally {
      _loading = false;
      _notify();
    }
  }

  Future<void> addExpense({required int amountFils, String? merchant}) =>
      _ledger.addManual(amountFils: amountFils, merchant: merchant, at: _clock());

  Future<void> setDailyLimit(int fils) async {
    final current = await _settings.load();
    await _settings.save(current.copyWith(dailyLimitFils: fils));
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ledger.removeListener(load);
    _settings.removeListener(load);
    super.dispose();
  }
}
