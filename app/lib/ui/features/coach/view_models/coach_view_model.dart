import 'dart:convert';

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

  /// The last AI plan and the request it answered: the same totals give
  /// the same plan at once, without asking the server again.
  /// v2: plans became a short message instead of numbered steps, so a plan
  /// kept under the old key is not shown again.
  static const String planCacheKey = 'coach.lastPlan.v2';
  static const String _oldPlanCacheKey = 'coach.lastPlan';

  /// The last cheaper options and the shops they were for, kept a week.
  static const String altCacheKey = 'coach.lastAlternatives';
  static const Duration altCacheAge = Duration(days: 7);

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
    await _prefs.write(planCacheKey, null);
    await _prefs.write(_oldPlanCacheKey, null);
    await _prefs.write(altCacheKey, null);
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
    final shops = _shopKey(request);
    final cached = await _cachedAlternatives(shops);
    if (cached != null) {
      _alternatives = cached;
      _altStep = CoachStep.ready;
      notifyListeners();
      return;
    }
    try {
      _alternatives = await _api.alternatives(request);
      _altStep = CoachStep.ready;
      if (_alternatives!.options.isNotEmpty) {
        await _prefs.write(
            altCacheKey,
            jsonEncode({
              'shops': shops,
              'at': _clock().toUtc().millisecondsSinceEpoch,
              'provider': _alternatives!.provider,
              'options': [
                for (final o in _alternatives!.options)
                  {'shop': o.shop, 'idea': o.idea},
              ],
            }));
      }
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
    final request = await preview(language);
    final key = jsonEncode(request);
    final cached = await _cachedPlan(key);
    if (cached != null) {
      _plan = cached;
      _step = CoachStep.ready;
      notifyListeners();
      return;
    }
    try {
      _plan = await _api.plan(request);
      _step = CoachStep.ready;
      // Only the AI's plans are kept: a plan written by rules is asked
      // again next time, when the AI may answer.
      if (_plan!.fromModel) {
        await _prefs.write(planCacheKey,
            jsonEncode({'request': key, 'text': _plan!.text, 'provider': _plan!.provider}));
        await _prefs.write(_oldPlanCacheKey, null);
      }
    } on CoachException catch (e) {
      _error = e.code;
      _errorDetail = e.detail;
      _step = CoachStep.failed;
    }
    notifyListeners();
  }

  Future<CoachPlan?> _cachedPlan(String request) async {
    try {
      final raw = await _prefs.read(planCacheKey);
      if (raw == null) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (m['request'] != request || m['text'] is! String) return null;
      return CoachPlan(
          text: m['text'] as String,
          fromModel: true,
          provider: m['provider'] as String?);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  /// The shops asked about, in a fixed order and without the visit counts,
  /// which change with every purchase while the ideas do not.
  static String _shopKey(Map<String, Object> request) {
    final shops = request['shops'];
    final names = [
      if (shops is List)
        for (final s in shops)
          if (s is Map && s['name'] is String) (s['name'] as String).toUpperCase(),
    ]..sort();
    return '${request['language']}|${names.join('|')}';
  }

  Future<CheaperOptions?> _cachedAlternatives(String shops) async {
    try {
      final raw = await _prefs.read(altCacheKey);
      if (raw == null) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (m['shops'] != shops) return null;
      final at = DateTime.fromMillisecondsSinceEpoch(m['at'] as int, isUtc: true);
      final age = _clock().toUtc().difference(at);
      if (age.isNegative || age > altCacheAge) return null;
      return CheaperOptions(
        options: [
          for (final o in m['options'] as List)
            CheaperOption(shop: o['shop'] as String, idea: o['idea'] as String),
        ],
        provider: m['provider'] as String?,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}
