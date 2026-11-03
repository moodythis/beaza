import 'package:beaza_crypto/beaza_crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The signed-in account on this phone.
class SavedAccount {
  const SavedAccount({
    required this.email,
    required this.token,
    required this.dataKey,
  });

  final String email;

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
    );
  }

  @override
  Future<void> write(SavedAccount account) async {
    await _storage.write(
        key: _dataKey,
        value: toBase64(account.dataKey.exportForSecureStorage()));
    await _storage.write(key: _token, value: account.token);
    await _storage.write(key: _email, value: account.email);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _email);
    await _storage.delete(key: _token);
    await _storage.delete(key: _dataKey);
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
