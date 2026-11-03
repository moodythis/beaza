import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';

import 'bytes.dart';

/// Why a typed recovery key was refused.
enum RecoveryKeyProblem {
  /// Not 32 characters after removing spaces and dashes.
  length,

  /// A character outside the alphabet.
  character,

  /// The checksum does not match: almost certainly a typing mistake.
  typo,
}

class RecoveryKeyException implements Exception {
  const RecoveryKeyException(this.problem);
  final RecoveryKeyProblem problem;

  @override
  String toString() => 'RecoveryKeyException(${problem.name})';
}

/// The key the user writes down once. It opens the data key when the
/// password is forgotten, and is the only way in for Google accounts.
///
/// 18 random bytes (144 bits) plus a 2-byte checksum make 20 bytes, written
/// as 32 Crockford base32 characters in 8 groups of 4:
/// `7K3M-9QXA-...`. The checksum catches typing mistakes before any network
/// call. 144 random bits cannot be guessed, so no slow hashing is needed.
///
/// It never leaves the phone and is never stored by the app.
class RecoveryKey {
  RecoveryKey._(this._secret);

  /// Builds a key from known bytes. For tests; the app uses [generate].
  factory RecoveryKey.fromSecret(List<int> secret) {
    if (secret.length != secretLength) {
      throw ArgumentError.value(secret.length, 'secret', 'must be 18 bytes');
    }
    return RecoveryKey._(Uint8List.fromList(secret));
  }

  factory RecoveryKey.generate() => RecoveryKey._(randomBytes(secretLength));

  static const int secretLength = 18;
  static const int checksumLength = 2;
  static const int characters = 32;
  static const String alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  final Uint8List _secret;

  /// Reads a key as the user typed it. Accepts lower case, spaces, dashes,
  /// Arabic-Indic digits, and the look-alikes O (zero), I and L (one).
  factory RecoveryKey.parse(String typed) {
    final chars = _normalize(typed);
    if (chars.length != characters) {
      throw const RecoveryKeyException(RecoveryKeyProblem.length);
    }
    for (final c in chars.split('')) {
      if (!alphabet.contains(c)) {
        throw const RecoveryKeyException(RecoveryKeyProblem.character);
      }
    }
    final bytes = _decode(chars);
    final secret = bytes.sublist(0, secretLength);
    if (!sameBytes(bytes.sublist(secretLength), _checksum(secret))) {
      throw const RecoveryKeyException(RecoveryKeyProblem.typo);
    }
    return RecoveryKey._(secret);
  }

  /// The text shown to the user: 8 groups of 4 characters.
  String format() {
    final chars = _encode([..._secret, ..._checksum(_secret)]);
    final groups = <String>[];
    for (var i = 0; i < chars.length; i += 4) {
      groups.add(chars.substring(i, i + 4));
    }
    return groups.join('-');
  }

  /// The key that locks and opens the data key's recovery copy.
  Future<SecretKey> wrappingKey() => Hkdf(hmac: Hmac.sha256(), outputLength: 32)
      .deriveKey(
        secretKey: SecretKey(_secret),
        info: utf8.encode('beaza/v1/recovery-wrap'),
      );

  /// What the phone sends the server to prove it holds the recovery key when
  /// the password is forgotten. Made with a different label than
  /// [wrappingKey], so seeing it (the server stores only its hash) tells
  /// nobody anything about the key that opens the data.
  Future<List<int>> authKey() async => (await Hkdf(
          hmac: Hmac.sha256(), outputLength: 32)
      .deriveKey(
        secretKey: SecretKey(_secret),
        info: utf8.encode('beaza/v1/recovery-auth'),
      ))
      .extractBytes();

  @override
  bool operator ==(Object other) =>
      other is RecoveryKey && sameBytes(other._secret, _secret);

  @override
  int get hashCode => Object.hashAll(_secret);

  /// Never prints the key, so it cannot end up in logs.
  @override
  String toString() => 'RecoveryKey(hidden)';

  static List<int> _checksum(List<int> secret) =>
      hash.sha256.convert(secret).bytes.sublist(0, checksumLength);

  static const Map<String, String> _lookAlikes = {
    'O': '0',
    'I': '1',
    'L': '1',
    '٠': '0',
    '١': '1',
    '٢': '2',
    '٣': '3',
    '٤': '4',
    '٥': '5',
    '٦': '6',
    '٧': '7',
    '٨': '8',
    '٩': '9',
  };

  static String _normalize(String typed) {
    final out = StringBuffer();
    for (final c in typed.toUpperCase().split('')) {
      if (c == '-' || c.trim().isEmpty) continue;
      out.write(_lookAlikes[c] ?? c);
    }
    return out.toString();
  }

  static String _encode(List<int> bytes) {
    final out = StringBuffer();
    var buffer = 0;
    var bits = 0;
    for (final b in bytes) {
      buffer = (buffer << 8) | b;
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        out.write(alphabet[(buffer >> bits) & 31]);
      }
      buffer &= (1 << bits) - 1;
    }
    if (bits > 0) out.write(alphabet[(buffer << (5 - bits)) & 31]);
    return out.toString();
  }

  static Uint8List _decode(String chars) {
    final out = <int>[];
    var buffer = 0;
    var bits = 0;
    for (final c in chars.split('')) {
      buffer = (buffer << 5) | alphabet.indexOf(c);
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.add((buffer >> bits) & 0xff);
      }
      buffer &= (1 << bits) - 1;
    }
    return Uint8List.fromList(out);
  }
}
