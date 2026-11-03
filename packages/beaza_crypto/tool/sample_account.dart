// Contract test, step 1 of 3 (see .github/workflows/ci.yml, job "contract").
//
// Makes a real account exactly as the phone does, with the production
// Argon2id setting, and prints what the phone would send plus the secrets
// that must never reach the server. server/scripts/contract.ts takes it from
// here; tool/check_responses.dart checks the server's answers.
import 'dart:convert';
import 'dart:io';

import 'package:beaza_crypto/beaza_crypto.dart';

const password = 'contract test password';

Future<void> main() async {
  final account = await AccountKeys.create(password: password);
  final cipher = await RecordCipher.create(account.dataKey);
  final record = await cipher.encrypt(
    collection: 'transactions',
    id: randomId(),
    fields: {'amountFils': 1500, 'merchant': 'SAMPLE BAKERY', 'currency': 'BHD'},
  );
  stdout.writeln(jsonEncode({
    'email': 'contract@example.com',
    'authKey': toBase64(account.authKey!),
    'recoveryAuthKey': toBase64(account.recoveryAuthKey),
    'bundle': account.bundle.toJson(),
    'record': record.toJson(),
    // Never sent by the phone; used to check nothing leaks and to reopen.
    'secrets': {
      'password': password,
      'recoveryKey': account.recoveryKey.format(),
      'dataKey': toBase64(account.dataKey.exportForSecureStorage()),
      'plainTexts': ['SAMPLE BAKERY', 'amountFils', '"merchant"'],
    },
  }));
}
