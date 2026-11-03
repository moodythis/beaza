import 'dart:async';

import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/data/services/device_service.dart';
import 'package:beaza/domain/use_cases/data_export.dart';
import 'package:beaza/domain/use_cases/message_intake.dart';
import 'package:beaza/domain/use_cases/savings_tips.dart';
import 'package:beaza/domain/use_cases/spending_by_category.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/foundation.dart';

/// What the home screen shows for one Bahrain day. Immutable snapshot.
@immutable
class HomeState {
  const HomeState({
    required this.summary,
    required this.today,
    required this.weekMicro,
    this.weekByCategory = const [],
    this.tips = const [],
  });

  final DaySummary summary;

  /// Today's counted spending, newest first.
  final List<LedgerEntry> today;
  final MicroStats weekMicro;

  /// Spending of the last 7 days per category, largest first.
  final List<CategoryTotal> weekByCategory;

  /// Saving tips from rules on this phone (empty when there is too little).
  final List<SavingsTip> tips;
}

class HomeViewModel extends ChangeNotifier {
  HomeViewModel({
    required LedgerRepository ledger,
    required SettingsRepository settings,
    MessageIntake? intake,
    DeviceService? device,
    this.export,
    DateTime Function()? clock,
    this.arrivalDelay = const Duration(seconds: 3),
  })  : _ledger = ledger,
        _settings = settings,
        _intake = intake,
        _device = device,
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
  final DeviceService? _device;
  final DateTime Function() _clock;

  /// For the history screen.
  LedgerRepository get ledger => _ledger;

  /// Saves a copy of the person's data (account screen); null hides it.
  final DataExport? export;
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

  bool _batteryRestricted = false;

  /// True when battery saving may stop Beaza while it is closed, so bank
  /// messages are read and alerts shown late. Checked with the messages.
  bool get batteryRestricted => _batteryRestricted;

  int _duplicates = 0;

  /// Transactions that repeat an earlier one read from the same message.
  int get duplicates => _duplicates;

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
      _duplicates = await _ledger.countDuplicates();
      final settings = await _settings.load();
      final guardrail = Guardrail(settings);
      final day = Day.of(_clock());
      _state = HomeState(
        summary: guardrail.summarize(entries, day),
        today: guardrail.spendingOn(entries, day).reversed.toList(),
        weekMicro: guardrail.weeklyMicro(entries, day),
        weekByCategory: spendingByCategory(entries, day.addDays(-6), day),
        tips: savingsTips(entries, day,
            dailyLimitFils: settings.dailyLimitFils,
            microThresholdFils: settings.microThresholdFils),
      );
      _error = null;
    } on Exception catch (e) {
      _error = e;
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// Changes the category of one transaction (the person tapped it).
  Future<void> setCategory(LedgerEntry entry, String category) =>
      _ledger.setCategory(entry, category);

  /// Reads new bank messages if allowed. Called at start, on resume and
  /// when an SMS arrives. Also checks battery saving, which decides whether
  /// messages are read while the app is closed.
  Future<void> checkMessages() async {
    if (_disposed) return;
    await _checkBattery();
    final intake = _intake;
    if (intake == null) {
      _notify();
      return;
    }
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

  Future<void> _checkBattery() async {
    final device = _device;
    if (device == null) return;
    try {
      _batteryRestricted = await device.batteryRestricted() ?? false;
    } on Exception {
      _batteryRestricted = false;
    }
  }

  /// Opens Beaza's page in the phone's settings. The card goes away when the
  /// person comes back (the app re-checks on resume).
  Future<void> openBatterySettings() async {
    try {
      await _device?.openAppSettings();
    } on Exception {
      // Nothing to do: the card stays and the person can try again.
    }
  }

  /// Removes the repeats; the ledger notifies, so the screen recomputes.
  Future<int> removeDuplicates() => _ledger.removeDuplicates();

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
