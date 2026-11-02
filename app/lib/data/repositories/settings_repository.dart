import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/foundation.dart';

/// The single Settings record (daily limit, micro threshold, alert cap...).
abstract class SettingsRepository extends ChangeNotifier {
  Future<GuardrailSettings> load();

  Future<void> save(GuardrailSettings settings);
}

/// Keeps settings in memory until the database is added. Starts with no
/// daily limit, so the home screen asks the user to set one.
class InMemorySettingsRepository extends SettingsRepository {
  InMemorySettingsRepository([
    GuardrailSettings initial = const GuardrailSettings(dailyLimitFils: 0),
  ]) : _settings = initial;

  GuardrailSettings _settings;

  @override
  Future<GuardrailSettings> load() async => _settings;

  @override
  Future<void> save(GuardrailSettings settings) async {
    _settings = settings;
    notifyListeners();
  }
}
