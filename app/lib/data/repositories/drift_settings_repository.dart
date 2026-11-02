import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/data/services/database.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:drift/drift.dart' show Value;

/// The single settings record, kept in the encrypted database.
/// Until the user saves something it returns the defaults with no limit.
class DriftSettingsRepository extends SettingsRepository {
  DriftSettingsRepository(this._db, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  @override
  Future<GuardrailSettings> load() async {
    final row = await (_db.select(_db.settingsRows)
          ..where((r) => r.id.equals(1)))
        .getSingleOrNull();
    if (row == null) return const GuardrailSettings(dailyLimitFils: 0);
    return GuardrailSettings(
      dailyLimitFils: row.dailyLimitFils,
      microThresholdFils: row.microThresholdFils,
      alertCap: row.alertCap,
      microCountForTotal: row.microCountForTotal,
      rollover: row.rollover,
      rolloverCapPercent: row.rolloverCapPercent,
    );
  }

  @override
  Future<void> save(GuardrailSettings s) async {
    await _db.into(_db.settingsRows).insertOnConflictUpdate(
          SettingsRowsCompanion.insert(
            id: const Value(1),
            dailyLimitFils: s.dailyLimitFils,
            microThresholdFils: s.microThresholdFils,
            alertCap: s.alertCap,
            microCountForTotal: s.microCountForTotal,
            rollover: s.rollover,
            rolloverCapPercent: s.rolloverCapPercent,
            updatedAtMs: _clock().toUtc().millisecondsSinceEpoch,
          ),
        );
    notifyListeners();
  }
}
