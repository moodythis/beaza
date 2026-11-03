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

/// Where the account lives between launches.
abstract class AccountStore {
  Future<SavedAccount?> read();
  Future<void> write(SavedAccount account);
  Future<void> clear();
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
}
