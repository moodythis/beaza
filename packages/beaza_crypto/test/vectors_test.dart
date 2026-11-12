// Published test vectors for the three primitives beaza_crypto relies on,
// checked against the same `cryptography` package version the app uses.
// If a dependency update ever changed their output, this file fails.
import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';

List<int> hex(String s) {
  final clean = s.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
  return [
    for (var i = 0; i < clean.length; i += 2)
      int.parse(clean.substring(i, i + 2), radix: 16),
  ];
}

void main() {
  test('XChaCha20-Poly1305: draft-irtf-cfrg-xchacha-03, section A.3.1',
      () async {
    final box = await Xchacha20.poly1305Aead().encrypt(
      hex('4c616469657320616e642047656e746c656d656e206f662074686520636c6173'
          '73206f66202739393a204966204920636f756c64206f6666657220796f75206f'
          '6e6c79206f6e652074697020666f7220746865206675747572652c2073756e73'
          '637265656e20776f756c642062652069742e'),
      secretKey: SecretKey(hex(
          '808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f')),
      nonce: hex('404142434445464748494a4b4c4d4e4f5051525354555657'),
      aad: hex('50515253c0c1c2c3c4c5c6c7'),
    );
    expect(
        box.cipherText,
        hex('bd6d179d3e83d43b9576579493c0e939572a1700252bfaccbed2902c21396cbb'
            '731c7f1b0b4aa6440bf3a82f4eda7e39ae64c6708c54c216cb96b72e1213b452'
            '2f8c9ba40db5d945b11b69b982c1bb9e3f3fac2bc369488f76b2383565d3fff9'
            '21f9664c97637da9768812f615c68b13b52e'));
    expect(box.mac.bytes, hex('c0875924c1c7987947deafd8780acf49'));
  });

  test('Argon2id: RFC 9106, section 5.3', () async {
    final key = await Argon2id(
      parallelism: 4,
      memory: 32,
      iterations: 3,
      hashLength: 32,
    ).deriveKey(
      secretKey: SecretKey(List<int>.filled(32, 0x01)),
      nonce: List<int>.filled(16, 0x02),
      optionalSecret: List<int>.filled(8, 0x03),
      associatedData: List<int>.filled(12, 0x04),
    );
    expect(
        await key.extractBytes(),
        hex('0d640df58d78766c08c037a34a8b53c9'
            'd01ef0452d75b65eb52520e96b01e659'));
  });

  test('HKDF-SHA256: RFC 5869, test case 1', () async {
    final key = await Hkdf(hmac: Hmac.sha256(), outputLength: 42).deriveKey(
      secretKey: SecretKey(List<int>.filled(22, 0x0b)),
      nonce: hex('000102030405060708090a0b0c'),
      info: hex('f0f1f2f3f4f5f6f7f8f9'),
    );
    expect(
        await key.extractBytes(),
        hex('3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf'
            '34007208d5b887185865'));
  });
}
