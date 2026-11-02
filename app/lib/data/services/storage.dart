import 'dart:io';

import 'package:beaza/data/repositories/drift_ledger_repository.dart';
import 'package:beaza/data/repositories/drift_settings_repository.dart';
import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/seen_message_store.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
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
  });

  final AppDatabase database;
  final LedgerRepository ledger;
  final SettingsRepository settings;
  final SeenMessageStore seenMessages;
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
  return Storage(
    database: db,
    ledger: DriftLedgerRepository(db, deviceId: deviceId),
    settings: DriftSettingsRepository(db),
    seenMessages: DriftSeenMessageStore(db),
  );
}
