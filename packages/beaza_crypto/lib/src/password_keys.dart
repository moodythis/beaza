import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Argon2id cost settings. Stored with the account so they can be raised
/// later without breaking old accounts.
class KdfParams {
  const KdfParams({
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
  });

  factory KdfParams.fromJson(Map<String, Object?> json) => KdfParams(
        memoryKiB: json['m'] as int,
        iterations: json['t'] as int,
        parallelism: json['p'] as int,
      );

  /// OWASP's Argon2id setting: 19 MiB of memory, 2 passes, 1 lane.
  static const KdfParams recommended =
      KdfParams(memoryKiB: 19456, iterations: 2, parallelism: 1);

  /// The weakest setting a phone accepts. The server tells a new phone which
  /// setting to use; without this floor a dishonest server could ask for a
  /// cheap one and then guess the password from what the phone sends back.
  static const KdfParams minimum = recommended;

  final int memoryKiB;
  final int iterations;
  final int parallelism;

  bool isAtLeast(KdfParams floor) =>
      memoryKiB >= floor.memoryKiB &&
      iterations >= floor.iterations &&
      parallelism >= 1;

  Map<String, Object?> toJson() =>
      {'alg': 'argon2id', 'm': memoryKiB, 't': iterations, 'p': parallelism};

  @override
  bool operator ==(Object other) =>
      other is KdfParams &&
      other.memoryKiB == memoryKiB &&
      other.iterations == iterations &&
      other.parallelism == parallelism;

  @override
  int get hashCode => Object.hash(memoryKiB, iterations, parallelism);

  @override
  String toString() => 'KdfParams(m: $memoryKiB KiB, t: $iterations, '
      'p: $parallelism)';
}

/// Thrown when asked to use an Argon2id setting below [KdfParams.minimum].
class WeakKdfParams implements Exception {
  const WeakKdfParams(this.params);
  final KdfParams params;

  @override
  String toString() => 'WeakKdfParams($params)';
}

/// Two keys made from the password with one slow Argon2id run.
///
/// [authKey] is what the phone sends to log in. The server keeps only a hash
/// of it, so it never sees the password. [wrapKey] never leaves the phone:
/// it opens the data key. Knowing one does not reveal the other, because each
/// comes from the Argon2id output through HKDF with a different label.
class PasswordKeys {
  PasswordKeys._(this.authKey, this.wrapKey, this.salt, this.params);

  final List<int> authKey;
  final SecretKey wrapKey;
  final List<int> salt;
  final KdfParams params;

  static const int saltLength = 16;

  static Future<PasswordKeys> derive({
    required String password,
    required List<int> salt,
    required KdfParams params,
    KdfParams minimum = KdfParams.minimum,
  }) async {
    if (!params.isAtLeast(minimum)) throw WeakKdfParams(params);
    if (password.isEmpty) throw ArgumentError.value('', 'password');
    if (salt.length < saltLength) throw ArgumentError.value(salt, 'salt');

    final stretched = await Argon2id(
      parallelism: params.parallelism,
      memory: params.memoryKiB,
      iterations: params.iterations,
      hashLength: 32,
    ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);

    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final auth = await hkdf.deriveKey(
      secretKey: stretched,
      info: utf8.encode('beaza/v1/auth'),
    );
    final wrap = await hkdf.deriveKey(
      secretKey: stretched,
      info: utf8.encode('beaza/v1/password-wrap'),
    );
    return PasswordKeys._(
      List.unmodifiable(await auth.extractBytes()),
      wrap,
      List.unmodifiable(salt),
      params,
    );
  }

  @override
  String toString() => 'PasswordKeys(hidden)';
}
