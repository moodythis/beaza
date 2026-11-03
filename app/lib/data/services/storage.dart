import 'dart:io';

import 'package:beaza/data/repositories/alert_log_store.dart';
import 'package:beaza/data/repositories/drift_ledger_repository.dart';
import 'package:beaza/data/repositories/drift_settings_repository.dart';
import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/preferences_store.dart';
import 'package:beaza/data/repositories/seen_message_store.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/data/repositories/syncable.dart';
import 'package:beaza/data/services/database.dart';
import 'package:beaza/data/services/database_opener.dart';
import 'package:beaza/data/services/key_store.dart';
import 'package:path/path.dart' as p;

/// Everything the app stores, opened together.
class Storage {
  const Storage({
    required this.database,
    required this.ledger,
    required this.settings,
    required this.seenMessages,
    required this.alertLogs,
    required this.preferences,
    this.syncables = const [],
  });

  final AppDatabase database;
  final LedgerRepository ledger;
  final SettingsRepository settings;
  final SeenMessageStore seenMessages;
  final AlertLogStore alertLogs;
  final PreferencesStore preferences;

  /// The lists that sync between phones (transactions and settings).
  final List<Syncable> syncables;
}

/// Opens the encrypted database in [directory], creating the key on first
/// use. If the file exists but the key is gone (for example the phone's
/// secure storage was wiped), it throws instead of creating a new empty
/// database over the old data.
Future<Storage> openStorage({
  required Directory directory,
  required KeyStore keys,
  bool background = true,
}) async {
  await directory.create(recursive: true);
  final file = File(p.join(directory.path, 'beaza.db'));

  var key = await keys.readDatabaseKey();
  if (key == null) {
    if (await file.exists()) {
      throw StateError('The database exists but its key is missing');
    }
    key = await keys.createDatabaseKey();
  }

  final db = openEncryptedDatabase(file, key, background: background);
  final deviceId = await keys.deviceId();
  final ledger = DriftLedgerRepository(db, deviceId: deviceId);
  final settings = DriftSettingsRepository(db);
  return Storage(
    database: db,
    ledger: ledger,
    settings: settings,
    syncables: [ledger, settings],
    seenMessages: DriftSeenMessageStore(db),
    alertLogs: DriftAlertLogStore(db),
    preferences: DriftPreferencesStore(db),
  );
}
