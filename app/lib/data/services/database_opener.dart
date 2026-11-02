import 'dart:io';

import 'package:beaza/data/services/database.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

final RegExp _hexKey = RegExp(r'^[0-9a-f]{64}$');

/// Opens (or creates) the encrypted database file.
///
/// [hexKey] is 64 lowercase hex characters (256 bits) from the Android
/// Keystore. With a wrong key, opening throws instead of returning data.
/// [background] runs SQLite on its own isolate (the app); tests pass false.
AppDatabase openEncryptedDatabase(
  File file,
  String hexKey, {
  bool background = true,
}) {
  if (!_hexKey.hasMatch(hexKey)) {
    throw ArgumentError.value(hexKey.length, 'hexKey', 'must be 64 hex digits');
  }

  // Captures only the key string, so it can run on the background isolate.
  void setup(sqlite.Database raw) {
    raw.execute("PRAGMA cipher = 'sqlcipher';");
    raw.execute("PRAGMA key = '$hexKey';");
    // Fails here, not later, when the cipher is missing or the key is wrong.
    if (raw.select('PRAGMA cipher;').isEmpty) {
      throw StateError('SQLite3 Multiple Ciphers is not linked');
    }
    raw.select('SELECT count(*) FROM sqlite_master;');
    raw.execute('PRAGMA journal_mode = WAL;');
  }

  return AppDatabase(
    background
        ? NativeDatabase.createInBackground(file, setup: setup)
        : NativeDatabase(file, setup: setup),
  );
}

/// An unencrypted in-memory database, for tests of the repositories only.
AppDatabase openMemoryDatabase() => AppDatabase(NativeDatabase.memory());
