import 'dart:convert';

import 'package:beaza_crypto/beaza_crypto.dart';
import 'package:test/test.dart';

import 'password_keys_test.dart' show fast;

Future<NewAccount> emailAccount([String password = 'my password']) =>
    AccountKeys.create(password: password, params: fast, minimum: fast);

/// What a second phone does: get the salt and setting from the server,
/// derive the keys, then open the bundle the server returned.
Future<DataKey> logIn(KeyBundle bundle, String password) async {
  final keys = await PasswordKeys.derive(
    password: password,
    salt: bundle.salt!,
    params: bundle.kdf!,
    minimum: fast,
  );
  return bundle.openWithPassword(keys);
}

/// The bundle after a trip to the server and back.
KeyBundle viaServer(KeyBundle b) => KeyBundle.fromJson(
    jsonDecode(jsonEncode(b.toJson())) as Map<String, Object?>);

void main() {
  test('a second phone logs in with the password and gets the same data key',
      () async {
    final account = await emailAccount();
    expect(await logIn(viaServer(account.bundle), 'my password'),
        account.dataKey);
  });

  test('the auth key sent at sign-up matches the one sent at log-in',
      () async {
    final account = await emailAccount();
    final b = viaServer(account.bundle);
    final keys = await PasswordKeys.derive(
        password: 'my password', salt: b.salt!, params: b.kdf!, minimum: fast);
    expect(keys.authKey, account.authKey);
  });

  test('a wrong password does not open the data key', () async {
    final account = await emailAccount();
    expect(() => logIn(account.bundle, 'my passworD'),
        throwsA(isA<DecryptionFailed>()));
  });

  test('the recovery key opens the data key', () async {
    final account = await emailAccount();
    final typed = account.recoveryKey.format().toLowerCase();
    expect(
        await viaServer(account.bundle)
            .openWithRecoveryKey(RecoveryKey.parse(typed)),
        account.dataKey);
  });

  test('another recovery key does not open it', () async {
    final account = await emailAccount();
    expect(() => account.bundle.openWithRecoveryKey(RecoveryKey.generate()),
        throwsA(isA<DecryptionFailed>()));
  });

  test('Google account: no password, only the recovery key', () async {
    final account = await AccountKeys.create();
    expect(account.authKey, isNull);
    expect(account.bundle.hasPassword, false);
    expect(account.bundle.toJson().containsKey('password'), false);
    expect(
        await viaServer(account.bundle)
            .openWithRecoveryKey(account.recoveryKey),
        account.dataKey);
  });

  test('forgot the password: recovery key, then a new password', () async {
    final account = await emailAccount('old password');
    final dataKey =
        await account.bundle.openWithRecoveryKey(account.recoveryKey);
    final change = await AccountKeys.setPassword(
        account.bundle, dataKey, 'new password',
        params: fast, minimum: fast);

    final bundle = viaServer(change.bundle);
    expect(await logIn(bundle, 'new password'), account.dataKey);
    expect(() => logIn(bundle, 'old password'),
        throwsA(isA<DecryptionFailed>()));
    expect(change.authKey, isNot(account.authKey));
    // The recovery key still works and the data key did not change, so
    // records encrypted before keep opening.
    expect(await bundle.openWithRecoveryKey(account.recoveryKey),
        account.dataKey);
    expect(bundle.salt, isNot(account.bundle.salt));
  });

  test('a new recovery key replaces the old one', () async {
    final account = await emailAccount();
    final change =
        await AccountKeys.replaceRecoveryKey(account.bundle, account.dataKey);
    final bundle = viaServer(change.bundle);
    expect(await bundle.openWithRecoveryKey(change.recoveryKey),
        account.dataKey);
    expect(() => bundle.openWithRecoveryKey(account.recoveryKey),
        throwsA(isA<DecryptionFailed>()));
    expect(await logIn(bundle, 'my password'), account.dataKey);
  });

  test('locked copies from two accounts cannot be swapped', () async {
    final a = await emailAccount();
    final b = await emailAccount();
    final mixed = KeyBundle(
      keyId: a.bundle.keyId,
      byRecovery: b.bundle.byRecovery,
    );
    expect(() => mixed.openWithRecoveryKey(b.recoveryKey),
        throwsA(isA<DecryptionFailed>()));
  });

  test('a changed byte in the bundle is detected', () async {
    final account = await emailAccount();
    final tampered = KeyBundle(
      keyId: account.bundle.keyId,
      byRecovery: account.bundle.byRecovery.sublist(0)..[30] ^= 1,
    );
    expect(() => tampered.openWithRecoveryKey(account.recoveryKey),
        throwsA(isA<DecryptionFailed>()));
  });

  test('a weak setting cannot be used to create an account', () {
    expect(() => AccountKeys.create(password: 'my password', params: fast),
        throwsA(isA<WeakKdfParams>()));
  });

  test('the data key is kept in secure storage and restored', () async {
    final account = await AccountKeys.create();
    final saved = account.dataKey.exportForSecureStorage();
    expect(DataKey.fromBytes(saved), account.dataKey);
    expect(account.dataKey.toString(), 'DataKey(hidden)');
  });

  test('the bundle the server stores holds no key or password in the clear',
      () async {
    final account = await emailAccount('secret words');
    final stored = jsonEncode(account.bundle.toJson());
    final dataKey = toBase64(account.dataKey.exportForSecureStorage());
    expect(stored.contains(dataKey), false);
    expect(stored.contains('secret words'), false);
    expect(stored.contains(account.recoveryKey.format()), false);
    expect(stored.contains(toBase64(account.authKey!)), false);
  });
}
