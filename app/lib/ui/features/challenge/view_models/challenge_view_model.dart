import 'dart:convert';

import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/preferences_store.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/domain/use_cases/weekly_challenge.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/foundation.dart';

/// The weekly challenge card: a suggestion from last week, or the running
/// challenge and how it stands. Kept on the phone only.
class ChallengeViewModel extends ChangeNotifier {
  ChallengeViewModel({
    required PreferencesStore preferences,
    required LedgerRepository ledger,
    required SettingsRepository settings,
    DateTime Function()? clock,
  })  : _prefs = preferences,
        _ledger = ledger,
        _settings = settings,
        _clock = clock ?? DateTime.now {
    _ledger.addListener(load);
  }

  static const String prefName = 'challenge';

  final PreferencesStore _prefs;
  final LedgerRepository _ledger;
  final SettingsRepository _settings;
  final DateTime Function() _clock;

  Challenge? _active;

  /// The challenge the person took, while it runs and once it is over.
  Challenge? get active => _active;

  ChallengeProgress? _progress;
  ChallengeProgress? get progress => _progress;

  Challenge? _suggestion;

  /// What to offer when nothing is running; null when nothing stands out.
  Challenge? get suggestion => _suggestion;

  bool get kept =>
      _active != null && _progress != null && challengeKept(_active!, _progress!);

  bool _disposed = false;

  Future<void> load() async {
    final entries = await _ledger.entries();
    final micro = (await _settings.load()).microThresholdFils;
    final today = Day.of(_clock());
    Challenge? active;
    try {
      final raw = await _prefs.read(prefName);
      active = raw == null ? null : Challenge.fromJson(jsonDecode(raw));
    } on FormatException {
      active = null;
    }
    _active = active;
    _progress = active == null
        ? null
        : challengeProgress(active, entries, today, microThresholdFils: micro);
    _suggestion = active == null
        ? suggestChallenge(entries, today, microThresholdFils: micro)
        : null;
    if (!_disposed) notifyListeners();
  }

  /// Starts the suggested challenge today.
  Future<void> accept() async {
    final s = _suggestion;
    if (s == null) return;
    await _prefs.write(
        prefName, jsonEncode(s.startingOn(Day.of(_clock())).toJson()));
    await load();
  }

  /// Ends the running (or finished) challenge; a new suggestion follows.
  Future<void> clear() async {
    await _prefs.write(prefName, null);
    await load();
  }

  @override
  void dispose() {
    _disposed = true;
    _ledger.removeListener(load);
    super.dispose();
  }
}
