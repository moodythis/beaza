import 'package:beaza/data/repositories/preferences_store.dart';
import 'package:flutter/widgets.dart';

/// The language the user chose with the button, kept between launches.
/// Null means "follow the phone".
class LanguageController extends ChangeNotifier {
  LanguageController(this._prefs);

  final PreferencesStore _prefs;
  static const String prefName = 'language';

  String? _code;

  /// "ar", "en" or null (follow the phone).
  String? get code => _code;

  Locale? get locale => _code == null ? null : Locale(_code!);

  Future<void> load() async {
    final saved = await _prefs.read(prefName);
    _code = (saved == 'ar' || saved == 'en') ? saved : null;
    notifyListeners();
  }

  Future<void> choose(String code) async {
    if (code != 'ar' && code != 'en') {
      throw ArgumentError.value(code, 'code', 'must be ar or en');
    }
    _code = code;
    notifyListeners();
    await _prefs.write(prefName, code);
  }
}

/// The language shown: the user's choice, otherwise the phone's language if
/// it is English, otherwise Arabic (the app's first language).
String effectiveLanguage(String? chosen, Locale phone) =>
    chosen ?? (phone.languageCode == 'en' ? 'en' : 'ar');
