import 'package:beaza/data/services/database.dart';

/// Small app preferences (for example the chosen language).
abstract class PreferencesStore {
  Future<String?> read(String name);

  /// Null removes the preference.
  Future<void> write(String name, String? value);
}

class DriftPreferencesStore implements PreferencesStore {
  DriftPreferencesStore(this._db);

  final AppDatabase _db;

  @override
  Future<String?> read(String name) async => (await (_db.select(_db.preferenceRows)
            ..where((r) => r.name.equals(name)))
          .getSingleOrNull())
      ?.value;

  @override
  Future<void> write(String name, String? value) async {
    if (value == null) {
      await (_db.delete(_db.preferenceRows)..where((r) => r.name.equals(name)))
          .go();
    } else {
      await _db.into(_db.preferenceRows).insertOnConflictUpdate(
            PreferenceRowsCompanion.insert(name: name, value: value),
          );
    }
  }
}

class MemoryPreferencesStore implements PreferencesStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String name) async => values[name];

  @override
  Future<void> write(String name, String? value) async {
    if (value == null) {
      values.remove(name);
    } else {
      values[name] = value;
    }
  }
}
