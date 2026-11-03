import 'dart:convert';

import 'package:beaza_crypto/beaza_crypto.dart';
import 'package:test/test.dart';

import 'password_keys_test.dart' show fast;

/// A ledger row as the app would sync it (no message text is ever stored).
Map<String, Object?> expense({int fils = 1500, String merchant = 'SAMPLE BAKERY'}) => {
      'amountFils': fils,
      'currency': 'BHD',
      'merchant': merchant,
      'type': 'purchase',
      'direction': 'outgoing',
      'atMs': 1793277727000,
      'updatedAtMs': 1793277730000,
      'deviceId': 'a1b2c3d4e5f60718293a4b5c6d7e8f90',
      'deletedAtMs': null,
    };

final id = randomId();

void main() {
  late RecordCipher cipher;
  setUp(() async {
    cipher = await RecordCipher.create(DataKey.generate());
  });

  test('a record comes back exactly as it went in', () async {
    final sealed = await cipher.encrypt(
        collection: 'transactions', id: id, fields: expense());
    expect(await cipher.decrypt(sealed), expense());
  });

  test('another phone with the same data key reads it', () async {
    final account = await AccountKeys.create();
    final phoneA = await RecordCipher.create(account.dataKey);
    final sealed = await phoneA.encrypt(
        collection: 'transactions', id: id, fields: expense());

    final dataKeyOnB =
        await account.bundle.openWithRecoveryKey(account.recoveryKey);
    final phoneB = await RecordCipher.create(dataKeyOnB);
    final fromServer = EncryptedRecord.fromJson(
        jsonDecode(jsonEncode(sealed.toJson())) as Map<String, Object?>);
    expect(await phoneB.decrypt(fromServer), expense());
  });

  test('the same record encrypted twice looks different', () async {
    final a = await cipher.encrypt(
        collection: 'transactions', id: id, fields: expense());
    final b = await cipher.encrypt(
        collection: 'transactions', id: id, fields: expense());
    expect(a.blob, isNot(b.blob));
  });

  test('another account cannot read it', () async {
    final sealed = await cipher.encrypt(
        collection: 'transactions', id: id, fields: expense());
    final other = await RecordCipher.create(DataKey.generate());
    expect(() => other.decrypt(sealed), throwsA(isA<DecryptionFailed>()));
  });

  test('a changed byte is detected', () async {
    final sealed = await cipher.encrypt(
        collection: 'transactions', id: id, fields: expense());
    for (final i in [0, 5, 30, sealed.blob.length - 1]) {
      final tampered = EncryptedRecord(
        collection: sealed.collection,
        id: sealed.id,
        blob: sealed.blob.sublist(0)..[i] ^= 1,
      );
      expect(() => cipher.decrypt(tampered), throwsA(isA<DecryptionFailed>()),
          reason: 'byte $i');
    }
  });

  test('the server cannot move a record to another id or list', () async {
    final sealed = await cipher.encrypt(
        collection: 'transactions', id: id, fields: expense());
    final moved = EncryptedRecord(
        collection: 'transactions', id: randomId(), blob: sealed.blob);
    final relisted =
        EncryptedRecord(collection: 'settings', id: id, blob: sealed.blob);
    expect(() => cipher.decrypt(moved), throwsA(isA<DecryptionFailed>()));
    expect(() => cipher.decrypt(relisted), throwsA(isA<DecryptionFailed>()));
  });

  test('blob size does not reveal the amount or a short merchant name',
      () async {
    final small = await cipher.encrypt(
        collection: 'transactions',
        id: id,
        fields: expense(fils: 100, merchant: 'CAFE'));
    final large = await cipher.encrypt(
        collection: 'transactions',
        id: id,
        fields: expense(fils: 123456, merchant: 'AL AYYAM TRADING'));
    expect(small.blob.length, large.blob.length);
    expect((small.blob.length - 41) % RecordCipher.block, 0);
  });

  test('padding is always removable', () {
    for (var n = 0; n < 200; n++) {
      final data = List.generate(n, (i) => i % 251 + 1);
      final padded = RecordCipher.pad(data);
      expect(padded.length % RecordCipher.block, 0);
      expect(RecordCipher.unpad(padded), data);
    }
  });

  test('ids and list names are checked', () {
    expect(
        () => cipher.encrypt(collection: 'a/b', id: id, fields: expense()),
        throwsArgumentError);
    expect(
        () => cipher.encrypt(
            collection: 'transactions', id: 'x/y', fields: expense()),
        throwsArgumentError);
  });

  test('everything the server receives holds nothing readable', () async {
    const password = 'my long password';
    final account = await AccountKeys.create(
        password: password, params: fast, minimum: fast);
    final phone = await RecordCipher.create(account.dataKey);
    final records = [
      await phone.encrypt(
          collection: 'transactions',
          id: randomId(),
          fields: expense(fils: 1500, merchant: 'AL AYYAM TRADING')),
      await phone.encrypt(
          collection: 'settings',
          id: 'main',
          fields: {'dailyLimitFils': 4000}),
    ];
    final upload = jsonEncode({
      'authKey': toBase64(account.authKey!),
      'bundle': account.bundle.toJson(),
      'records': [for (final r in records) r.toJson()],
    });

    for (final secret in [
      'AL AYYAM',
      'TRADING',
      // How the amounts would look in plain JSON (a colon never appears in
      // base64 or hex, so random ids cannot match by chance).
      ':1500',
      ':4000',
      'amountFils',
      'dailyLimitFils',
      'merchant',
      'purchase',
      password,
      account.recoveryKey.format(),
      toBase64(account.dataKey.exportForSecureStorage()),
    ]) {
      expect(upload.contains(secret), false, reason: secret);
    }
  });
}
