import 'dart:convert';

import 'package:beaza/app.dart';
import 'package:beaza/data/repositories/account_repository.dart';
import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/data/services/account_store.dart';
import 'package:beaza/data/services/google_auth.dart';
import 'package:beaza/data/services/key_work.dart';
import 'package:beaza/data/services/sync_api.dart';
import 'package:beaza/ui/features/home/view_models/home_view_model.dart';
import 'package:beaza_crypto/beaza_crypto.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'account_repository_test.dart' show consent, fast;
import 'account_view_test.dart' show FakeAccounts;

/// Google's picker: returns a fixed ID token, or null (closed), or throws.
class FakeGoogle implements GoogleAuth {
  String? token = 'id-token-sara';
  bool fail = false;
  int shown = 0;

  @override
  bool get available => true;

  @override
  Future<String?> idToken() async {
    shown++;
    if (fail) throw const GoogleAuthException('noCredential');
    return token;
  }
}

/// The Google calls of server/src/app.ts. ID tokens are trusted by name:
/// `id-token-<person>` belongs to Google account `<person>`.
class GoogleServer {
  final users = <String, Map<String, Object?>>{};
  final sessions = <String, String>{};
  final bodies = <String>[];
  int _tokens = 0;

  http.Client get client => MockClient((r) async {
        bodies.add(r.body);
        final body = r.body.isEmpty
            ? <String, Object?>{}
            : jsonDecode(r.body) as Map<String, Object?>;
        final sub = (body['idToken'] as String?)?.replaceFirst('id-token-', '');
        final token = r.headers['authorization']?.substring('Bearer '.length);
        switch ('${r.method} ${r.url.path}') {
          case 'POST /v1/google/check':
            final user = users[sub];
            return _ok({
              'exists': user != null,
              'email': '$sub@gmail.com',
              'password': user != null &&
                  (user['bundle'] as Map).containsKey('password'),
            });
          case 'POST /v1/kdf':
            final user = users[(body['email'] as String).split('@').first];
            final password = (user!['bundle'] as Map)['password'] as Map;
            return _ok({'salt': password['salt'], 'kdf': password['kdf']});
          case 'POST /v1/google/register':
            if ((body['bundle'] as Map).containsKey('password')) {
              return _error(400, 'bad_bundle');
            }
            if (users.containsKey(sub)) return _error(409, 'email_taken');
            users[sub!] = {
              'recoveryAuthKey': body['recoveryAuthKey'],
              'bundle': body['bundle'],
            };
            return _ok({'token': _session(sub)});
          case 'POST /v1/google/login':
            final user = users[sub];
            if (user == null) return _error(404, 'no_account');
            final field =
                body.containsKey('authKey') ? 'authKey' : 'recoveryAuthKey';
            if (user[field] == null || user[field] != body[field]) {
              return _error(401, 'invalid_credentials');
            }
            return _ok({'token': _session(sub!), 'bundle': user['bundle']});
          case 'POST /v1/account/delete':
            final owner = sessions[token];
            if (owner == null || owner != sub) {
              return _error(401, 'invalid_credentials');
            }
            users.remove(owner);
            return _ok({'ok': true});
        }
        return _error(404, 'not_found');
      });

  String _session(String sub) {
    final token = 'token${_tokens++}'.padRight(43, 'x');
    sessions[token] = sub;
    return token;
  }

  static http.Response _ok(Map<String, Object?> body) => http.Response(
      jsonEncode(body), 200,
      headers: {'content-type': 'application/json'});

  static http.Response _error(int status, String code) =>
      http.Response(jsonEncode({'error': code}), status);
}

RemoteAccountRepository phone(GoogleServer server, FakeGoogle google,
        [MemoryAccountStore? store]) =>
    RemoteAccountRepository(
      api: SyncApi(client: server.client, baseUrl: 'https://sync.test'),
      store: store ?? MemoryAccountStore(),
      work: const KeyWork.forTests(fast),
      google: google,
    );

Future<AccountProblem?> problemOf(Future<void> Function() action) async {
  try {
    await action();
    return null;
  } on AccountFailure catch (e) {
    return e.problem;
  }
}

void main() {
  test('sign up with Google, then log in on another phone with the '
      'recovery key and get the same data key', () async {
    final server = GoogleServer();
    final storeA = MemoryAccountStore();
    final a = phone(server, FakeGoogle(), storeA);
    expect(a.googleAvailable, isTrue);

    final start = (await a.startGoogle())!;
    expect(start.exists, isFalse);
    expect(start.email, 'sara@gmail.com');
    final recoveryKey = await a.signUpWithGoogle(start, consent);
    expect(storeA.saved!.google, isTrue);
    expect(storeA.saved!.email, 'sara@gmail.com');
    final bundle = server.users['sara']!['bundle'] as Map;
    expect(bundle.containsKey('password'), isFalse, reason: 'no password lock');

    final storeB = MemoryAccountStore();
    final b = phone(server, FakeGoogle(), storeB);
    final again = (await b.startGoogle())!;
    expect(again.exists, isTrue);
    await b.logInWithGoogle(again, recoveryKey: recoveryKey.format());
    expect(storeB.saved!.dataKey, storeA.saved!.dataKey);
    expect(storeB.saved!.google, isTrue);
  });

  test('a Gmail that already has an email account logs in with its '
      'password through Google', () async {
    final server = GoogleServer();
    final created = await const KeyWork.forTests(fast)
        .createAccount('a long password');
    server.users['sara'] = {
      'authKey': toBase64(created.authKey!),
      'recoveryAuthKey': toBase64(created.recoveryAuthKey),
      'bundle': created.bundle.toJson(),
    };

    final store = MemoryAccountStore();
    final b = phone(server, FakeGoogle(), store);
    final start = (await b.startGoogle())!;
    expect(start.exists, isTrue);
    expect(start.hasPassword, isTrue);

    expect(
        await problemOf(
            () => b.logInWithGoogle(start, password: 'wrong password!')),
        AccountProblem.wrongCredentials);
    await b.logInWithGoogle(start, password: 'a long password');
    expect(store.saved!.dataKey, created.dataKey);
    expect(store.saved!.google, isTrue);

    // The recovery key works too (forgot the password).
    final other = MemoryAccountStore();
    await phone(server, FakeGoogle(), other).logInWithGoogle(start,
        recoveryKey: created.recoveryKey.format());
    expect(other.saved!.dataKey, created.dataKey);
  });

  test('a wrong recovery key is refused and nothing is saved', () async {
    final server = GoogleServer();
    final a = phone(server, FakeGoogle());
    await a.signUpWithGoogle((await a.startGoogle())!, consent);

    final store = MemoryAccountStore();
    final b = phone(server, FakeGoogle(), store);
    final start = (await b.startGoogle())!;
    final other = RecoveryKey.generate().format();
    expect(await problemOf(() => b.logInWithGoogle(start, recoveryKey: other)),
        AccountProblem.wrongRecoveryKey);
    expect(await problemOf(() => b.logInWithGoogle(start, recoveryKey: 'ABCD')),
        AccountProblem.recoveryKeyFormat);
    expect(store.saved, isNull);
  });

  test('the recovery key never leaves the phone', () async {
    final server = GoogleServer();
    final a = phone(server, FakeGoogle());
    final key = await a.signUpWithGoogle((await a.startGoogle())!, consent);
    final sent = server.bodies.join('\n');
    expect(sent.contains(key.format()), isFalse);
  });

  test('closing Google\'s picker does nothing; a picker error is shown',
      () async {
    final server = GoogleServer();
    final google = FakeGoogle()..token = null;
    final a = phone(server, google);
    expect(await a.startGoogle(), isNull);
    expect(server.bodies, isEmpty);

    google.fail = true;
    expect(await problemOf(a.startGoogle), AccountProblem.google);
  });

  test('deleting a Google account asks Google again', () async {
    final server = GoogleServer();
    final google = FakeGoogle();
    final store = MemoryAccountStore();
    final a = phone(server, google, store);
    await a.signUpWithGoogle((await a.startGoogle())!, consent);

    google.token = null; // closed the picker
    expect(await a.deleteGoogleAccount(), isFalse);
    expect(a.signedIn, isTrue);

    google.token = 'id-token-sara';
    expect(await a.deleteGoogleAccount(), isTrue);
    expect(a.signedIn, isFalse);
    expect(store.saved, isNull);
    expect(server.users, isEmpty);
  });

  test('without a client id there is no Google button', () {
    final repo = RemoteAccountRepository(
      api: SyncApi(client: GoogleServer().client, baseUrl: 'https://sync.test'),
      store: MemoryAccountStore(),
      google: PluginGoogleAuth(clientId: ''),
    );
    expect(repo.googleAvailable, isFalse);
  });

  testWidgets('the Google button leads to sign-up without a password',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final accounts = GoogleFakeAccounts();
    final vm = HomeViewModel(
      ledger: InMemoryLedgerRepository(),
      settings: InMemorySettingsRepository(
          const GuardrailSettings(dailyLimitFils: 10000)),
    );
    await vm.load();
    await tester.pumpWidget(BeazaApp(
        homeViewModel: vm, locale: const Locale('en'), account: accounts));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('accountButton')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('googleButton')));
    await tester.pumpAndSettle();
    expect(find.text('Google account: sara@gmail.com'), findsOneWidget);
    expect(find.byKey(const Key('passwordField')), findsNothing);
    expect(find.byKey(const Key('signUpSubmit')), findsOneWidget);
  });

  testWidgets('without Google set up the button is not shown',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final vm = HomeViewModel(
      ledger: InMemoryLedgerRepository(),
      settings: InMemorySettingsRepository(),
    );
    await vm.load();
    await tester.pumpWidget(BeazaApp(
        homeViewModel: vm, locale: const Locale('en'), account: FakeAccounts()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('accountButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('googleButton')), findsNothing);
  });
}

class GoogleFakeAccounts extends FakeAccounts {
  @override
  bool get googleAvailable => true;

  @override
  Future<GoogleStart?> startGoogle() async => const GoogleStart(
      idToken: 'id-token-sara', email: 'sara@gmail.com', exists: false);
}
