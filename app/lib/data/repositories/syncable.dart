/// One local change waiting to go to the sync server.
class SyncItem {
  const SyncItem({
    required this.id,
    required this.updatedAtMs,
    required this.fields,
  });

  final String id;

  /// Used to clear the pending mark only if the row did not change again
  /// while it was being sent.
  final int updatedAtMs;

  /// Everything about the row. Encrypted before it leaves the phone.
  final Map<String, Object?> fields;
}

/// A remote version that arrived from another phone (already decrypted).
class RemoteItem {
  const RemoteItem(this.id, this.fields);

  final String id;
  final Map<String, Object?> fields;
}

/// A list of rows that syncs between phones.
///
/// Conflicts are settled by "last writer wins": the version with the later
/// updatedAtMs is kept on every phone (ties go to the larger device id, so
/// all phones pick the same one). Deleted rows stay as tombstones, so a
/// deletion travels like any other change.
abstract interface class Syncable {
  /// The collection name the server sees, for example `txn`.
  String get collection;

  Future<List<SyncItem>> pendingChanges({int limit});

  /// Clears the pending mark of [id] if it still has [updatedAtMs].
  Future<void> markSynced(String id, int updatedAtMs);

  /// Applies versions from other phones. Returns how many rows changed.
  /// Listeners are told once if anything changed.
  Future<int> applyRemote(List<RemoteItem> items);

  /// Marks every row to be sent again, for example after logging in to a
  /// different account.
  Future<void> markAllPending();
}

/// Last writer wins: true if the version from ([time], [device]) should
/// replace the one from ([localTime], [localDevice]).
bool isNewer(int time, String device, int localTime, String localDevice) =>
    time > localTime || (time == localTime && device.compareTo(localDevice) > 0);

/// Reads a field that must be an int, or throws [FormatException].
int intField(Map<String, Object?> f, String name) {
  final v = f[name];
  if (v is int) return v;
  throw FormatException('bad $name');
}

int? optionalInt(Map<String, Object?> f, String name) {
  final v = f[name];
  if (v == null || v is int) return v as int?;
  throw FormatException('bad $name');
}

String stringField(Map<String, Object?> f, String name) {
  final v = f[name];
  if (v is String) return v;
  throw FormatException('bad $name');
}

String? optionalString(Map<String, Object?> f, String name) {
  final v = f[name];
  if (v == null || v is String) return v as String?;
  throw FormatException('bad $name');
}

bool boolField(Map<String, Object?> f, String name) {
  final v = f[name];
  if (v is bool) return v;
  throw FormatException('bad $name');
}

double doubleField(Map<String, Object?> f, String name) {
  final v = f[name];
  if (v is num) return v.toDouble();
  throw FormatException('bad $name');
}
