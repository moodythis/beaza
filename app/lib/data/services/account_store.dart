import 'dart:convert';

import 'package:beaza_crypto/beaza_crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The signed-in account on this phone.
class SavedAccount {
  const SavedAccount({
    required this.email,
    required this.token,
    required this.dataKey,
    this.google = false,
  });

  final String email;

  /// Signed in with Google: no password; Google confirms deletion.
  final bool google;

  /// Session token for the sync server.
  final String token;

  /// Opens the synced records. Only ever kept in secure storage.
  final DataKey dataKey;
}

/// A Google account this phone may log in to again with Google alone, kept
/// after logging out: the server's device key (which opens no data) and the
/// data key, both in the Keystore.
class RememberedGoogle {
  const RememberedGoogle({
    required this.email,
    required this.deviceKey,
    required this.dataKey,
  });

  final String email;
  final String deviceKey;
  final DataKey dataKey;
}

/// Where the account lives between launches.
abstract class AccountStore {
  Future<SavedAccount?> read();
  Future<void> write(SavedAccount account);
  Future<void> clear();

  Future<RememberedGoogle?> readRemembered();
  Future<void> writeRemembered(RememberedGoogle remembered);
  Future<void> clearRemembered();
}

/// Keeps the account in the Android Keystore, next to the database key.
class SecureAccountStore implements AccountStore {
  SecureAccountStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _email = 'beaza.account.email';
  static const _token = 'beaza.account.token';
  static const _dataKey = 'beaza.account.dataKey';
  static const _google = 'beaza.account.google';
  static const _remembered = 'beaza.remembered.google';

  @override
  Future<SavedAccount?> read() async {
    final email = await _storage.read(key: _email);
    final token = await _storage.read(key: _token);
    final key = await _storage.read(key: _dataKey);
    if (email == null || token == null || key == null) return null;
    return SavedAccount(
      email: email,
      token: token,
      dataKey: DataKey.fromBytes(fromBase64(key)),
      google: await _storage.read(key: _google) == '1',
    );
  }

  @override
  Future<void> write(SavedAccount account) async {
    await _storage.write(
        key: _dataKey,
        value: toBase64(account.dataKey.exportForSecureStorage()));
    await _storage.write(key: _token, value: account.token);
    await _storage.write(key: _email, value: account.email);
    await _storage.write(key: _google, value: account.google ? '1' : '0');
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _email);
    await _storage.delete(key: _token);
    await _storage.delete(key: _dataKey);
    await _storage.delete(key: _google);
  }

  @override
  Future<RememberedGoogle?> readRemembered() async {
    final text = await _storage.read(key: _remembered);
    if (text == null) return null;
    try {
      final j = jsonDecode(text) as Map<String, Object?>;
      return RememberedGoogle(
        email: j['email']! as String,
        deviceKey: j['deviceKey']! as String,
        dataKey: DataKey.fromBytes(fromBase64(j['dataKey']! as String)),
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<void> writeRemembered(RememberedGoogle r) => _storage.write(
        key: _remembered,
        value: jsonEncode({
          'email': r.email,
          'deviceKey': r.deviceKey,
          'dataKey': toBase64(r.dataKey.exportForSecureStorage()),
        }),
      );

  @override
  Future<void> clearRemembered() => _storage.delete(key: _remembered);
}

/// For tests.
class MemoryAccountStore implements AccountStore {
  SavedAccount? saved;

  @override
  Future<SavedAccount?> read() async => saved;

  @override
  Future<void> write(SavedAccount account) async => saved = account;

  @override
  Future<void> clear() async => saved = null;

  RememberedGoogle? remembered;

  @override
  Future<RememberedGoogle?> readRemembered() async => remembered;

  @override
  Future<void> writeRemembered(RememberedGoogle r) async => remembered = r;

  @override
  Future<void> clearRemembered() async => remembered = null;
}
