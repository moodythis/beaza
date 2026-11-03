// Makes a real account for a tester, exactly as the phone does at sign-up
// (production Argon2id setting). Used by .github/workflows/test-account.yml.
//
//   EMAIL=... PASSWORD=... dart run tool/new_account.dart > account.json
//
// The output holds the recovery key: the workflow never prints it.
import 'dart:convert';
import 'dart:io';

import 'package:beaza_crypto/beaza_crypto.dart';

Future<void> main() async {
  final email = Platform.environment['EMAIL'];
  final password = Platform.environment['PASSWORD'];
  if (email == null || password == null || password.length < 10) {
    stderr.writeln('EMAIL and PASSWORD (10+ characters) are needed');
    exitCode = 2;
    return;
  }
  final account = await AccountKeys.create(password: password);
  stdout.writeln(jsonEncode({
    'email': email.trim().toLowerCase(),
    'authKey': toBase64(account.authKey!),
    'recoveryAuthKey': toBase64(account.recoveryAuthKey),
    'bundle': account.bundle.toJson(),
    'recoveryKey': account.recoveryKey.format(),
  }));
}
