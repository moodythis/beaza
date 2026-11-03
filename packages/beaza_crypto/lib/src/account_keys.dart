import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'bytes.dart';
import 'envelope.dart';
import 'password_keys.dart';
import 'recovery_key.dart';

/// The random key that encrypts every record. Made on the first phone and
/// copied to the others only in locked form (see [KeyBundle]).
class DataKey {
  DataKey._(this._bytes);

  factory DataKey.generate() => DataKey._(randomBytes(length));

  /// Restores the key that the phone saved in its secure storage.
  factory DataKey.fromBytes(List<int> bytes) {
    if (bytes.length != length) {
      throw ArgumentError.value(bytes.length, 'bytes', 'must be 32 bytes');
    }
    return DataKey._(Uint8List.fromList(bytes));
  }

  static const int length = 32;

  final Uint8List _bytes;

  /// For the phone's secure storage (Android Keystore) only. Never sent.
  Uint8List exportForSecureStorage() => Uint8List.fromList(_bytes);

  /// The key for records. Kept separate from the data key itself so that
  /// each use has its own key (more uses can be added later the same way).
  Future<SecretKey> recordKey() => Hkdf(hmac: Hmac.sha256(), outputLength: 32)
      .deriveKey(
        secretKey: SecretKey(_bytes),
        info: utf8.encode('beaza/v1/records'),
      );

  @override
  bool operator ==(Object other) =>
      other is DataKey && sameBytes(other._bytes, _bytes);

  @override
  int get hashCode => Object.hashAll(_bytes);

  @override
  String toString() => 'DataKey(hidden)';
}

/// What the server keeps for an account. Every field is safe to give the
/// server: the data key appears only locked, once with the password's wrap
/// key and once with the recovery key. The salt and Argon2id setting are
/// public by design; the phone needs them before it can log in.
class KeyBundle {
  const KeyBundle({
    required this.keyId,
    required this.byRecovery,
    this.salt,
    this.kdf,
    this.byPassword,
  });

  factory KeyBundle.fromJson(Map<String, Object?> json) {
    if (json['v'] != version) {
      throw FormatException('Unknown key bundle version ${json['v']}');
    }
    final password = json['password'] as Map<String, Object?>?;
    return KeyBundle(
      keyId: json['keyId'] as String,
      byRecovery: fromBase64(json['recovery'] as String),
      salt: password == null ? null : fromBase64(password['salt'] as String),
      kdf: password == null
          ? null
          : KdfParams.fromJson(password['kdf'] as Map<String, Object?>),
      byPassword:
          password == null ? null : fromBase64(password['key'] as String),
    );
  }

  static const int version = 1;

  /// Random id of the data key. Bound into both locked copies, so copies
  /// from different keys cannot be mixed.
  final String keyId;
  final Uint8List byRecovery;
  final List<int>? salt;
  final KdfParams? kdf;
  final Uint8List? byPassword;

  /// False for Google accounts, which have only the recovery key.
  bool get hasPassword => byPassword != null;

  Map<String, Object?> toJson() => {
        'v': version,
        'keyId': keyId,
        'recovery': toBase64(byRecovery),
        if (byPassword != null)
          'password': {
            'salt': toBase64(salt!),
            'kdf': kdf!.toJson(),
            'key': toBase64(byPassword!),
          },
      };

  /// Opens the data key after logging in with the password. [keys] must come
  /// from [PasswordKeys.derive] with this bundle's salt and setting.
  Future<DataKey> openWithPassword(PasswordKeys keys) async {
    final locked = byPassword;
    if (locked == null) throw StateError('This account has no password');
    return DataKey.fromBytes(
        await Envelope.open(locked, keys.wrapKey, _context(keyId, 'password')));
  }

  Future<DataKey> openWithRecoveryKey(RecoveryKey key) async =>
      DataKey.fromBytes(await Envelope.open(
          byRecovery, await key.wrappingKey(), _context(keyId, 'recovery')));

  KeyBundle _copyWith({
    Uint8List? byRecovery,
    List<int>? salt,
    KdfParams? kdf,
    Uint8List? byPassword,
  }) =>
      KeyBundle(
        keyId: keyId,
        byRecovery: byRecovery ?? this.byRecovery,
        salt: salt ?? this.salt,
        kdf: kdf ?? this.kdf,
        byPassword: byPassword ?? this.byPassword,
      );
}

String _context(String keyId, String lock) => 'beaza/v1/data-key/$lock/$keyId';

/// Everything made when an account is created. [recoveryKey] is shown to the
/// user once; [authKey] and [bundle] go to the server; [dataKey] goes to the
/// phone's secure storage.
class NewAccount {
  const NewAccount({
    required this.dataKey,
    required this.recoveryKey,
    required this.bundle,
    required this.authKey,
  });

  final DataKey dataKey;
  final RecoveryKey recoveryKey;
  final KeyBundle bundle;

  /// Null for Google accounts (Google proves who the user is).
  final List<int>? authKey;
}

/// A new password: the server replaces the bundle and the stored auth hash.
/// Records are not touched, because the data key stays the same.
class PasswordChange {
  const PasswordChange(this.bundle, this.authKey);
  final KeyBundle bundle;
  final List<int> authKey;
}

/// Creating accounts and changing their locks. All of it runs on the phone.
abstract final class AccountKeys {
  /// A new account. With [password] (email accounts) the data key is locked
  /// twice; without it (Google accounts) only with the recovery key.
  static Future<NewAccount> create({
    String? password,
    KdfParams params = KdfParams.recommended,
    KdfParams minimum = KdfParams.minimum,
  }) async {
    final dataKey = DataKey.generate();
    final recoveryKey = RecoveryKey.generate();
    final keyId = randomId();
    var bundle = KeyBundle(
      keyId: keyId,
      byRecovery: await Envelope.seal(dataKey._bytes,
          await recoveryKey.wrappingKey(), _context(keyId, 'recovery')),
    );
    List<int>? authKey;
    if (password != null) {
      final change = await setPassword(bundle, dataKey, password,
          params: params, minimum: minimum);
      bundle = change.bundle;
      authKey = change.authKey;
    }
    return NewAccount(
      dataKey: dataKey,
      recoveryKey: recoveryKey,
      bundle: bundle,
      authKey: authKey,
    );
  }

  /// Sets or changes the password, with a fresh salt. Used after a
  /// recovery-key login too, so a forgotten password can be replaced.
  static Future<PasswordChange> setPassword(
    KeyBundle bundle,
    DataKey dataKey,
    String password, {
    KdfParams params = KdfParams.recommended,
    KdfParams minimum = KdfParams.minimum,
  }) async {
    final keys = await PasswordKeys.derive(
      password: password,
      salt: randomBytes(PasswordKeys.saltLength),
      params: params,
      minimum: minimum,
    );
    final locked = await Envelope.seal(
        dataKey._bytes, keys.wrapKey, _context(bundle.keyId, 'password'));
    return PasswordChange(
      bundle._copyWith(salt: keys.salt, kdf: params, byPassword: locked),
      keys.authKey,
    );
  }

  /// Replaces the recovery key (for example when the old one may have been
  /// seen by someone). The old key stops working once the server has the new
  /// bundle.
  static Future<({KeyBundle bundle, RecoveryKey recoveryKey})>
      replaceRecoveryKey(KeyBundle bundle, DataKey dataKey) async {
    final recoveryKey = RecoveryKey.generate();
    final locked = await Envelope.seal(dataKey._bytes,
        await recoveryKey.wrappingKey(), _context(bundle.keyId, 'recovery'));
    return (
      bundle: bundle._copyWith(byRecovery: locked),
      recoveryKey: recoveryKey,
    );
  }
}
