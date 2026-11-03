import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

final Random _secure = Random.secure();

/// Bytes from the operating system's secure random generator.
Uint8List randomBytes(int length) {
  final out = Uint8List(length);
  for (var i = 0; i < length; i++) {
    out[i] = _secure.nextInt(256);
  }
  return out;
}

/// A random id as 32 lowercase hex characters (128 bits).
String randomId() =>
    randomBytes(16).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Base64url without padding, the form used in JSON sent to the server.
String toBase64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

Uint8List fromBase64(String text) =>
    base64Url.decode(base64Url.normalize(text));

/// Compares in time that does not depend on where the first difference is.
bool sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
