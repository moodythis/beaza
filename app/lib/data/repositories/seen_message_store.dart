import 'package:beaza/data/services/database.dart';
import 'package:drift/drift.dart';

/// Ids of messages already handled, so a message is never counted twice.
/// Holds only ids such as "sms:123", never text.
abstract class SeenMessageStore {
  Future<bool> contains(String key);

  Future<void> add(String key, DateTime at);

  /// Forgets ids handled before [cutoff] (they are outside the scan window).
  Future<void> pruneBefore(DateTime cutoff);
}

class DriftSeenMessageStore implements SeenMessageStore {
  DriftSeenMessageStore(this._db);

  final AppDatabase _db;

  @override
  Future<bool> contains(String key) async =>
      await (_db.select(_db.seenMessageRows)..where((r) => r.messageKey.equals(key)))
          .getSingleOrNull() !=
      null;

  @override
  Future<void> add(String key, DateTime at) =>
      _db.into(_db.seenMessageRows).insertOnConflictUpdate(
            SeenMessageRowsCompanion.insert(
              messageKey: key,
              seenAtMs: at.toUtc().millisecondsSinceEpoch,
            ),
          );

  @override
  Future<void> pruneBefore(DateTime cutoff) => (_db.delete(_db.seenMessageRows)
        ..where((r) =>
            r.seenAtMs.isSmallerThanValue(cutoff.toUtc().millisecondsSinceEpoch)))
      .go();
}

class MemorySeenMessageStore implements SeenMessageStore {
  final Map<String, DateTime> _seen = {};

  @override
  Future<bool> contains(String key) async => _seen.containsKey(key);

  @override
  Future<void> add(String key, DateTime at) async => _seen[key] = at;

  @override
  Future<void> pruneBefore(DateTime cutoff) async =>
      _seen.removeWhere((_, at) => at.isBefore(cutoff));
}
