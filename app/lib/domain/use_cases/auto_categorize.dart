import 'dart:convert';

import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/preferences_store.dart';
import 'package:beaza/data/services/categorize_api.dart';
import 'package:beaza/domain/use_cases/shop_name.dart';
import 'package:beaza/domain/use_cases/spending_by_category.dart';
import 'package:beaza_extraction/beaza_extraction.dart';

/// Sorts purchases the phone could not sort, with AI (FR-8.14): only the
/// shop names go to the server (digits removed), after a separate consent.
/// The category is saved like the person's own choice, so it applies to the
/// whole shop and to later purchases there, and the person can change it.
/// Each name is asked once: a name the model could not tell stays unsorted.
class AutoCategorizer {
  AutoCategorizer({
    required LedgerRepository ledger,
    required PreferencesStore preferences,
    required CategorizeApi api,
  })  : _ledger = ledger,
        _prefs = preferences,
        _api = api;

  static const String consentPref = 'categorizeConsent';
  static const String triedPref = 'categorize.tried';

  /// Names remembered as already asked, so they are not sent again.
  static const int maxTried = 500;

  final LedgerRepository _ledger;
  final PreferencesStore _prefs;
  final CategorizeApi _api;

  Future<bool> isOn() async =>
      await _prefs.read(consentPref) == kCategorizeConsentVersion;

  Future<void> turnOn() => _prefs.write(consentPref, kCategorizeConsentVersion);

  Future<void> turnOff() => _prefs.write(consentPref, null);

  Future<int>? _running;

  /// Sorts what it can and returns how many shops got a category. Does
  /// nothing without the consent. Safe to call often: one run at a time.
  Future<int> run() => _running ??= _run().whenComplete(() => _running = null);

  Future<int> _run() async {
    if (!await isOn()) return 0;
    final tried = await _tried();
    final entries = await _ledger.entries();
    // One entry per shop: setting it sets the whole shop.
    final byName = <String, LedgerEntry>{};
    for (final e in entries) {
      if (e.role != EntryRole.spending) continue;
      if (bucketOf(e.result) != kUnsortedBucket) continue;
      final name = cleanShopName(e.result.merchantNorm ?? e.result.merchantRaw);
      if (name == null || tried.contains(name.toUpperCase())) continue;
      byName.putIfAbsent(name, () => e);
    }
    if (byName.isEmpty) return 0;
    var sorted = 0;
    final names = byName.keys.toList();
    for (var i = 0; i < names.length; i += 30) {
      final batch = names.sublist(i, i + 30 > names.length ? names.length : i + 30);
      final Map<String, String> got;
      try {
        got = await _api.categorize(batch);
      } on Object {
        return sorted; // offline or busy: try again next time
      }
      for (final name in batch) {
        final category = got[name];
        if (category != null && kCategories.contains(category)) {
          await _ledger.setCategory(byName[name]!, category);
          sorted++;
        }
        tried.add(name.toUpperCase());
      }
      await _saveTried(tried);
    }
    return sorted;
  }

  Future<Set<String>> _tried() async {
    try {
      final raw = await _prefs.read(triedPref);
      if (raw == null) return {};
      return (jsonDecode(raw) as List).cast<String>().toSet();
    } on Object {
      return {};
    }
  }

  Future<void> _saveTried(Set<String> tried) async {
    final list = tried.toList();
    final keep = list.length > maxTried ? list.sublist(list.length - maxTried) : list;
    await _prefs.write(triedPref, jsonEncode(keep));
  }
}
