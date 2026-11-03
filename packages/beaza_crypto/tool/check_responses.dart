// Contract test, step 3 of 3: opens what the server sent back, as a second
// phone would, and checks it gives the same data key and the same record.
//   dart run tool/check_responses.dart account.json responses.json
import 'dart:convert';
import 'dart:io';

import 'package:beaza_crypto/beaza_crypto.dart';

Map<String, Object?> _read(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

var _failed = false;

void _check(String name, bool ok) {
  stdout.writeln('${ok ? 'ok  ' : 'FAIL'} $name');
  if (!ok) _failed = true;
}

Future<void> main(List<String> args) async {
  final sample = _read(args[0]);
  final responses = _read(args[1]);
  final secrets = sample['secrets'] as Map<String, Object?>;
  final expectedKey = DataKey.fromBytes(fromBase64(secrets['dataKey'] as String));

  final kdf = responses['kdf'] as Map<String, Object?>;
  final login = responses['login'] as Map<String, Object?>;
  final bundle = KeyBundle.fromJson(login['bundle'] as Map<String, Object?>);

  final keys = await PasswordKeys.derive(
    password: secrets['password'] as String,
    salt: fromBase64(kdf['salt'] as String),
    params: KdfParams.fromJson(kdf['kdf'] as Map<String, Object?>),
  );
  _check('the auth key from the server\'s salt matches the one sent at sign-up',
      toBase64(keys.authKey) == sample['authKey']);
  _check('the password opens the bundle the server returned',
      await bundle.openWithPassword(keys) == expectedKey);
  _check(
      'the recovery key opens it too',
      await bundle.openWithRecoveryKey(
              RecoveryKey.parse(secrets['recoveryKey'] as String)) ==
          expectedKey);

  final pulled = (responses['pull'] as Map<String, Object?>)['records'] as List;
  final record =
      EncryptedRecord.fromJson(pulled.single as Map<String, Object?>);
  final fields = await (await RecordCipher.create(expectedKey)).decrypt(record);
  _check('the pulled record decrypts to what was sent',
      fields['amountFils'] == 1500 && fields['merchant'] == 'SAMPLE BAKERY');

  stdout.writeln(_failed ? 'CONTRACT FAILED' : 'CONTRACT PASSED');
  exit(_failed ? 1 : 0);
}
