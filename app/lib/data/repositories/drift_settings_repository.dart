import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/data/repositories/syncable.dart';
import 'package:beaza/data/services/database.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:drift/drift.dart';

/// The single settings record, kept in the encrypted database.
/// Until the user saves something it returns the defaults with no limit.
/// Syncs as one record: the limit set on one phone applies on all of them.
class DriftSettingsRepository extends SettingsRepository implements Syncable {
  DriftSettingsRepository(this._db, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  static const String syncCollection = 'settings';

  /// The only record id in the settings collection.
  static const String syncId = 'main';

  @override
  Future<GuardrailSettings> load() async {
    final row = await _row();
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
    await _write(s, _clock().toUtc().millisecondsSinceEpoch, pending: true);
    notifyListeners();
  }

  Future<SettingsRow?> _row() =>
      (_db.select(_db.settingsRows)..where((r) => r.id.equals(1)))
          .getSingleOrNull();

  Future<void> _write(GuardrailSettings s, int updatedAtMs,
          {required bool pending}) =>
      _db.into(_db.settingsRows).insertOnConflictUpdate(
            SettingsRowsCompanion.insert(
              id: const Value(1),
              dailyLimitFils: s.dailyLimitFils,
              microThresholdFils: s.microThresholdFils,
              alertCap: s.alertCap,
              microCountForTotal: s.microCountForTotal,
              rollover: s.rollover,
              rolloverCapPercent: s.rolloverCapPercent,
              updatedAtMs: updatedAtMs,
              pendingSync: Value(pending),
            ),
          );

  // ---- sync ----

  @override
  String get collection => syncCollection;

  @override
  Future<List<SyncItem>> pendingChanges({int limit = 100}) async {
    final row = await _row();
    if (row == null || !row.pendingSync || limit < 1) return const [];
    return [
      SyncItem(
        id: syncId,
        updatedAtMs: row.updatedAtMs,
        fields: {
          'v': 1,
          'dailyLimitFils': row.dailyLimitFils,
          'microThresholdFils': row.microThresholdFils,
          'alertCap': row.alertCap,
          'microCountForTotal': row.microCountForTotal,
          'rollover': row.rollover,
          'rolloverCapPercent': row.rolloverCapPercent,
          'updatedAtMs': row.updatedAtMs,
        },
      ),
    ];
  }

  @override
  Future<void> markSynced(String id, int updatedAtMs) async {
    if (id != syncId) return;
    await (_db.update(_db.settingsRows)
          ..where((r) => r.id.equals(1) & r.updatedAtMs.equals(updatedAtMs)))
        .write(const SettingsRowsCompanion(pendingSync: Value(false)));
  }

  @override
  Future<void> markAllPending() => _db
      .update(_db.settingsRows)
      .write(const SettingsRowsCompanion(pendingSync: Value(true)));

  @override
  Future<int> localCount() async => await _row() == null ? 0 : 1;

  /// Settings have no device: the limit stays as it is; the person can
  /// change it.
  @override
  Future<int> countFromOtherPhones() async => 0;

  @override
  Future<int> removeFromOtherPhones() async => 0;

  @override
  Future<int> applyRemote(List<RemoteItem> items) async {
    var changed = 0;
    for (final item in items) {
      if (item.id != syncId) continue;
      final GuardrailSettings remote;
      final int time;
      try {
        final f = item.fields;
        if (f['v'] != 1) throw const FormatException('unknown version');
        time = intField(f, 'updatedAtMs');
        final limit = intField(f, 'dailyLimitFils');
        final micro = intField(f, 'microThresholdFils');
        final cap = intField(f, 'alertCap');
        final count = intField(f, 'microCountForTotal');
        final percent = intField(f, 'rolloverCapPercent');
        if (limit < 0 ||
            micro <= 0 ||
            cap < 0 ||
            count <= 0 ||
            percent < 0 ||
            percent > 50) {
          throw const FormatException('out of range');
        }
        remote = GuardrailSettings(
          dailyLimitFils: limit,
          microThresholdFils: micro,
          alertCap: cap,
          microCountForTotal: count,
          rollover: boolField(f, 'rollover'),
          rolloverCapPercent: percent,
        );
      } on FormatException {
        continue;
      }
      final local = await _row();
      if (local == null || time > local.updatedAtMs) {
        await _write(remote, time, pending: false);
        changed++;
      } else if (time < local.updatedAtMs && !local.pendingSync) {
        // Ours is later: send it again so every phone ends up with it.
        await markAllPending();
      }
    }
    if (changed > 0) notifyListeners();
    return changed;
  }
}
