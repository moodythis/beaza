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
  })  : _api = api,
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

  bool _consented = false;
  bool get consented => _consented;

  CoachStep _step = CoachStep.idle;
  CoachStep get step => _step;

  CoachPlan? _plan;
  CoachPlan? get plan => _plan;

  String? _error;
  String? get error => _error;

  /// The network layer's own words for the last failure, if any.
  String? _errorDetail;
  String? get errorDetail => _errorDetail;

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
    _alternatives = null;
    _altStep = CoachStep.idle;
    notifyListeners();
  }

  CoachStep _altStep = CoachStep.idle;
  CoachStep get altStep => _altStep;

  CheaperOptions? _alternatives;
  CheaperOptions? get alternatives => _alternatives;

  /// True when there are no shops to ask about yet.
  bool _noShops = false;
  bool get noShops => _noShops;

  /// "Cheaper options": the shop names and visit counts of the plan
  /// request only, under the same consent.
  Future<void> requestAlternatives(String language) async {
    if (!_consented) return;
    _altStep = CoachStep.loading;
    _error = null;
    _errorDetail = null;
    _noShops = false;
    notifyListeners();
    final request = alternativesRequest(await preview(language));
    if (request == null) {
      _noShops = true;
      _alternatives = null;
      _altStep = CoachStep.ready;
      notifyListeners();
      return;
    }
    try {
      _alternatives = await _api.alternatives(request);
      _altStep = CoachStep.ready;
    } on CoachException catch (e) {
      _error = e.code;
      _errorDetail = e.detail;
      _altStep = CoachStep.failed;
    }
    notifyListeners();
  }

  Future<void> requestPlan(String language) async {
    if (!_consented) return;
    _step = CoachStep.loading;
    _error = null;
    _errorDetail = null;
    notifyListeners();
    try {
      _plan = await _api.plan(await preview(language));
      _step = CoachStep.ready;
    } on CoachException catch (e) {
      _error = e.code;
      _errorDetail = e.detail;
      _step = CoachStep.failed;
    }
    notifyListeners();
  }
}
