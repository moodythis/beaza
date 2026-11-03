import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'bytes.dart';

/// Thrown when encrypted data cannot be opened: the key is wrong or the data
/// was changed. The two cases are deliberately not told apart.
class DecryptionFailed implements Exception {
  const DecryptionFailed();

  @override
  String toString() => 'DecryptionFailed: wrong key or changed data';
}

/// Authenticated encryption with XChaCha20-Poly1305.
///
/// Layout: `version (1 byte) | nonce (24) | ciphertext | tag (16)`.
///
/// The 24-byte nonce is random for every message, which is safe for any
/// number of messages under one key (12-byte AES-GCM nonces are not).
/// [context] is authenticated but not stored: data sealed for one purpose
/// (one record id, one kind of key) does not open under another.
abstract final class Envelope {
  static const int version = 1;
  static const int nonceLength = 24;
  static const int tagLength = 16;
  static const int overhead = 1 + nonceLength + tagLength;

  static final Cipher _aead = Xchacha20.poly1305Aead();

  static Future<Uint8List> seal(
    List<int> plain,
    SecretKey key,
    String context,
  ) async {
    final box = await _aead.encrypt(
      plain,
      secretKey: key,
      nonce: randomBytes(nonceLength),
      aad: utf8.encode(context),
    );
    return Uint8List.fromList([version, ...box.concatenation()]);
  }

  static Future<Uint8List> open(
    List<int> sealed,
    SecretKey key,
    String context,
  ) async {
    if (sealed.length < overhead || sealed[0] != version) {
      throw const DecryptionFailed();
    }
    final box = SecretBox.fromConcatenation(
      sealed.sublist(1),
      nonceLength: nonceLength,
      macLength: tagLength,
    );
    try {
      final plain = await _aead.decrypt(
        box,
        secretKey: key,
        aad: utf8.encode(context),
      );
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      throw const DecryptionFailed();
    }
  }
}
