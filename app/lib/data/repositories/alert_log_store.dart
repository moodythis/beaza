import 'package:beaza/data/services/database.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:drift/drift.dart' show Value;

/// What was already sent each day, so closing the app does not reset the
/// alert cap or repeat an alert.
abstract class AlertLogStore {
  Future<AlertLog?> load(Day day);

  Future<void> save(AlertLog log);
}

class DriftAlertLogStore implements AlertLogStore {
  DriftAlertLogStore(this._db, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  @override
  Future<AlertLog?> load(Day day) async {
    final row = await (_db.select(_db.alertDayRows)
          ..where((r) => r.dayKey.equals(day.toString())))
        .getSingleOrNull();
    if (row == null) return null;
    final levels = AlertLevel.values;
    return AlertLog(
      day: day,
      sent: row.sent,
      highestLevel: levels[row.highestLevel.clamp(0, levels.length - 1)],
      microTotalShown: row.microTotalShown,
      limitExceededLogged: row.limitExceededLogged,
      limitFils: row.limitFils,
    );
  }

  @override
  Future<void> save(AlertLog log) =>
      _db.into(_db.alertDayRows).insertOnConflictUpdate(
            AlertDayRowsCompanion.insert(
              dayKey: log.day.toString(),
              sent: log.sent,
              highestLevel: log.highestLevel.index,
              microTotalShown: log.microTotalShown,
              limitExceededLogged: log.limitExceededLogged,
              limitFils: Value(log.limitFils),
              updatedAtMs: _clock().toUtc().millisecondsSinceEpoch,
            ),
          );
}

class MemoryAlertLogStore implements AlertLogStore {
  final Map<Day, AlertLog> logs = {};

  @override
  Future<AlertLog?> load(Day day) async => logs[day];

  @override
  Future<void> save(AlertLog log) async => logs[log.day] = log;
}
