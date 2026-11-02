import 'dart:async';

import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/domain/use_cases/message_intake.dart';
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
    MessageIntake? intake,
    DateTime Function()? clock,
    this.arrivalDelay = const Duration(seconds: 3),
  })  : _ledger = ledger,
        _settings = settings,
        _intake = intake,
        _clock = clock ?? DateTime.now {
    _ledger.addListener(load);
    _settings.addListener(load);
    // The SMS app writes the inbox a moment after the broadcast.
    _arrivals = _intake?.arrivals.listen(
      (_) => Future<void>.delayed(arrivalDelay, checkMessages),
      onError: (Object _) {},
    );
  }

  final LedgerRepository _ledger;
  final SettingsRepository _settings;
  final MessageIntake? _intake;
  final DateTime Function() _clock;
  final Duration arrivalDelay;
  StreamSubscription<void>? _arrivals;

  /// Null until checked, or when there is no SMS support (tests, other OS).
  bool? _smsAllowed;
  bool? get smsAllowed => _smsAllowed;

  /// True after the user refused the permission dialog in this session.
  bool _smsDenied = false;
  bool get smsDenied => _smsDenied;

  /// For the review screen; null when SMS reading is not available.
  MessageIntake? get intake => _intake;

  int _notUnderstood = 0;
  int get notUnderstood => _notUnderstood;

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

  /// Reads new bank messages if allowed. Called at start, on resume and
  /// when an SMS arrives.
  Future<void> checkMessages() async {
    final intake = _intake;
    if (intake == null || _disposed) return;
    try {
      _smsAllowed = await intake.hasPermission();
      if (_smsAllowed == true) {
        _notUnderstood = (await intake.scan()).notUnderstood;
      }
    } on Exception {
      // Reading SMS is a convenience: a failure must not break the screen.
    }
    _notify();
  }

  Future<void> enableMessages() async {
    final intake = _intake;
    if (intake == null) return;
    try {
      _smsAllowed = await intake.requestPermission();
    } on Exception {
      _smsAllowed = false;
    }
    _smsDenied = _smsAllowed != true;
    _notify();
    if (_smsAllowed == true) await checkMessages();
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
    _arrivals?.cancel();
    _ledger.removeListener(load);
    _settings.removeListener(load);
    super.dispose();
  }
}
