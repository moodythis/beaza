import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the database key and this phone's id live. The key is kept in the
/// Android Keystore and is never written next to the database file.
abstract class KeyStore {
  /// The database key, or null when none was created yet.
  Future<String?> readDatabaseKey();

  /// Creates and stores a new random 256-bit key (64 hex digits).
  Future<String> createDatabaseKey();

  /// Random id of this phone, created on first use. Needed for sync.
  Future<String> deviceId();
}

String randomHex(int bytes, {Random? random}) {
  final r = random ?? Random.secure();
  final b = StringBuffer();
  for (var i = 0; i < bytes; i++) {
    b.write(r.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return b.toString();
}

/// Random 128-bit id as 32 hex digits, for transactions and devices.
String newId() => randomHex(16);

class SecureKeyStore implements KeyStore {
  SecureKeyStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _keyName = 'beaza.db.key';
  static const _deviceName = 'beaza.device.id';

  @override
  Future<String?> readDatabaseKey() => _storage.read(key: _keyName);

  @override
  Future<String> createDatabaseKey() async {
    final key = randomHex(32);
    await _storage.write(key: _keyName, value: key);
    return key;
  }

  @override
  Future<String> deviceId() async {
    final existing = await _storage.read(key: _deviceName);
    if (existing != null) return existing;
    final id = newId();
    await _storage.write(key: _deviceName, value: id);
    return id;
  }
}

/// For tests: keeps everything in memory.
class MemoryKeyStore implements KeyStore {
  String? _key;
  String? _device;

  @override
  Future<String?> readDatabaseKey() async => _key;

  @override
  Future<String> createDatabaseKey() async => _key = randomHex(32);

  @override
  Future<String> deviceId() async => _device ??= newId();
}
