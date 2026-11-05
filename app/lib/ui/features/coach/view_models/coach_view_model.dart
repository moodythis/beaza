import 'dart:math';

import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/preferences_store.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/data/services/coach_api.dart';
import 'package:beaza/domain/use_cases/coach_request.dart';
import 'package:beaza/domain/use_cases/daily_budget.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/foundation.dart';

enum CoachStep { idle, loading, ready, failed }

/// The AI savings plan: a separate consent (stored on the phone, can be
/// withdrawn), the exact totals that will be sent, and the plan.
class CoachViewModel extends ChangeNotifier {
  CoachViewModel({
    required CoachApi api,
    required PreferencesStore preferences,
    required LedgerRepository ledger,
    required SettingsRepository settings,
    DateTime Function()? clock,
    List<int> Function()? salt,
  })  : _api = api,
        _salt = salt ?? _randomSalt,
        _prefs = preferences,
        _ledger = ledger,
        _settings = settings,
        _clock = clock ?? DateTime.now;

  static const String prefName = 'coachConsent';

  final CoachApi _api;
  final PreferencesStore _prefs;
  final LedgerRepository _ledger;
  final SettingsRepository _settings;
  final DateTime Function() _clock;
  final List<int> Function() _salt;

  static List<int> _randomSalt() {
    final r = Random.secure();
    return List<int>.generate(16, (_) => r.nextInt(256));
  }

  bool _consented = false;
  bool get consented => _consented;

  CoachStep _step = CoachStep.idle;
  CoachStep get step => _step;

  CoachPlan? _plan;
  CoachPlan? get plan => _plan;

  String? _error;
  String? get error => _error;

  Future<void> load() async {
    _consented = await _prefs.read(prefName) == kCoachConsentVersion;
    notifyListeners();
  }

  /// Exactly what [requestPlan] would send, to show before agreeing.
  Future<Map<String, Object>> preview(String language) async => coachRequest(
        await _ledger.entries(),
        await _settings.load(),
        Day.of(_clock()),
        language,
        plan: await readBudgetPlan(_prefs),
      );

  Future<void> agree() async {
    await _prefs.write(prefName, kCoachConsentVersion);
    _consented = true;
    notifyListeners();
  }

  /// Withdraws the consent; nothing is sent again until the person agrees.
  Future<void> withdraw() async {
    await _prefs.write(prefName, null);
    _consented = false;
    _plan = null;
    _step = CoachStep.idle;
    notifyListeners();
  }

  Future<void> requestPlan(String language) async {
    if (!_consented) return;
    _step = CoachStep.loading;
    _error = null;
    notifyListeners();
    try {
      // Shop names stay here: the server gets codes, and the names are put
      // back into the plan on the phone.
      final (:request, :names) =
          pseudonymizeShops(await preview(language), _salt());
      final plan = await _api.plan(request);
      _plan = CoachPlan(
        text: restoreShopNames(plan.text, names),
        fromModel: plan.fromModel,
      );
      _step = CoachStep.ready;
    } on CoachException catch (e) {
      _error = e.code;
      _step = CoachStep.failed;
    }
    notifyListeners();
  }
}
