import 'dart:convert';

import 'package:beaza/data/repositories/account_repository.dart';
import 'package:beaza/data/services/account_store.dart';
import 'package:beaza/data/services/key_work.dart';
import 'package:beaza/data/services/sync_api.dart';
import 'package:beaza/ui/features/account/legal_text.dart';
import 'package:beaza_crypto/beaza_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Cheap Argon2id for tests; the app uses KdfParams.recommended.
const fast = KdfParams(memoryKiB: 64, iterations: 1, parallelism: 1);

final consent = Consent(
  privacyVersion: privacyNotice.version,
  termsVersion: termsOfUse.version,
  adult: true,
);

/// Behaves like server/src/app.ts for the calls the account uses.
class FakeServer {
  final users = <String, Map<String, Object?>>{};
  final sessions = <String, String>{};
  final calls = <String>[];
  final bodies = <String>[];
  Map<String, Object?>? kdfOverride;
  String? failRegisterWith;
  bool offline = false;
  bool rateLimited = false;
  int _tokens = 0;

  http.Client get client => MockClient(_handle);

  Future<http.Response> _handle(http.Request r) async {
    if (offline) throw http.ClientException('offline');
    calls.add('${r.method} ${r.url.path}');
    bodies.add(r.body);
    if (rateLimited) return _error(429, 'rate_limited', retry: 120);
    final body = r.body.isEmpty
        ? <String, Object?>{}
        : jsonDecode(r.body) as Map<String, Object?>;
    final token = r.headers['authorization']?.substring('Bearer '.length);
    final sessionEmail = token == null ? null : sessions[token];

    switch ('${r.method} ${r.url.path}') {
      case 'POST /v1/register':
        if (failRegisterWith != null) return _error(400, failRegisterWith!);
        final email = body['email'] as String;
        final c = body['consent'] as Map<String, Object?>?;
        if (c == null || c['adult'] != true || c['privacy'] == null || c['terms'] == null) {
          return _error(400, 'consent_required');
        }
        if (users.containsKey(email)) return _error(409, 'email_taken');
        users[email] = {
          'authKey': body['authKey'],
          'recoveryAuthKey': body['recoveryAuthKey'],
          'bundle': body['bundle'],
          'consent': c,
        };
        return _ok({'token': _session(email)});
      case 'POST /v1/kdf':
        if (kdfOverride != null) return _ok(kdfOverride!);
        final user = users[body['email']];
        if (user == null) {
          return _ok({'salt': toBase64(List.filled(16, 7)), 'kdf': fast.toJson()});
        }
        final password = (user['bundle'] as Map)['password'] as Map;
        return _ok({'salt': password['salt'], 'kdf': password['kdf']});
      case 'POST /v1/login':
      case 'POST /v1/recover':
        final user = users[body['email']];
        final field = r.url.path.endsWith('login') ? 'authKey' : 'recoveryAuthKey';
        if (user == null || user[field] != body[field]) {
          return _error(401, 'invalid_credentials');
        }
        return _ok({'token': _session(body['email'] as String), 'bundle': user['bundle']});
      case 'POST /v1/password':
        if (sessionEmail == null) return _error(401, 'unauthorized');
        // As the server: a session alone is not enough.
        final u = users[sessionEmail]!;
        if (body['currentAuthKey'] == null &&
            body['currentRecoveryAuthKey'] == null) {
          return _error(400, 'proof_required');
        }
        if ((body['currentAuthKey'] != null &&
                body['currentAuthKey'] != u['authKey']) ||
            (body['currentRecoveryAuthKey'] != null &&
                body['currentRecoveryAuthKey'] != u['recoveryAuthKey'])) {
          return _error(401, 'invalid_credentials');
        }
        users[sessionEmail]!
          ..['authKey'] = body['authKey']
          ..['bundle'] = body['bundle'];
        return _ok({'ok': true});
      case 'GET /v1/account':
        if (sessionEmail == null) return _error(401, 'unauthorized');
        final c = users[sessionEmail]!['consent'] as Map;
        return _ok({
          'email': sessionEmail,
          'createdAt': 1793700000000,
          'consent': {'privacy': c['privacy'], 'terms': c['terms'], 'at': 1793700000000},
          'encryptedRecords': 0,
          'activeSessions': sessions.values.where((e) => e == sessionEmail).length,
        });
      case 'POST /v1/account/delete':
        if (sessionEmail == null) return _error(401, 'unauthorized');
        if (users[sessionEmail]!['authKey'] != body['authKey']) {
          return _error(401, 'invalid_credentials');
        }
        users.remove(sessionEmail);
        sessions.removeWhere((_, e) => e == sessionEmail);
        return _ok({'ok': true});
      case 'POST /v1/logout':
        sessions.remove(token);
        return _ok({'ok': true});
    }
    return _error(404, 'not_found');
  }

  String _session(String email) {
    final token = 'token${_tokens++}'.padRight(43, 'x');
    sessions[token] = email;
    return token;
  }

  http.Response _ok(Map<String, Object?> body) =>
      http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

  http.Response _error(int status, String code, {int? retry}) => http.Response(
        jsonEncode({'error': code, if (retry != null) 'retryAfterSeconds': retry}),
        status,
      );
}

/// One phone: its own secure storage, talking to the shared fake server.
RemoteAccountRepository phone(FakeServer server, [MemoryAccountStore? store]) =>
    RemoteAccountRepository(
      api: SyncApi(client: server.client, baseUrl: 'https://sync.test'),
      store: store ?? MemoryAccountStore(),
      work: const KeyWork.forTests(fast),
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
  test('sign up, then a second phone logs in and gets the same data key', () async {
    final server = FakeServer();
    final storeA = MemoryAccountStore();
    final a = phone(server, storeA);
    final recoveryKey = await a.signUp(
        email: 'Sara@Example.com ', password: 'a long password', consent: consent);
    expect(recoveryKey.format(), hasLength(39));
    expect(a.signedIn, true);
    expect(storeA.saved!.email, 'sara@example.com');

    final storeB = MemoryAccountStore();
    final b = phone(server, storeB);
    await b.logIn(email: 'sara@example.com', password: 'a long password');
    expect(storeB.saved!.dataKey, storeA.saved!.dataKey);
  });

  test('sign-up sends all three agreements and never the password', () async {
    final server = FakeServer();
    await phone(server).signUp(
        email: 'a@b.co', password: 'secret words here', consent: consent);
    final sent = server.bodies.join('\n');
    expect(sent.contains('secret words here'), false);
    final c = server.users['a@b.co']!['consent'] as Map;
    expect(c, {
      'privacy': privacyNotice.version,
      'terms': termsOfUse.version,
      'adult': true,
    });
  });

  test('sign-up refuses without the age statement', () async {
    final server = FakeServer();
    expect(
      () => phone(server).signUp(
        email: 'a@b.co',
        password: 'a long password',
        consent: Consent(
            privacyVersion: privacyNotice.version,
            termsVersion: termsOfUse.version,
            adult: false),
      ),
      throwsArgumentError,
    );
    expect(server.calls, isEmpty);
  });

  test('the same email twice', () async {
    final server = FakeServer();
    await phone(server).signUp(email: 'a@b.co', password: 'a long password', consent: consent);
    expect(
      await problemOf(() => phone(server)
          .signUp(email: 'a@b.co', password: 'other password', consent: consent)),
      AccountProblem.emailTaken,
    );
  });

  test('wrong password: refused, and nothing is saved', () async {
    final server = FakeServer();
    await phone(server).signUp(email: 'a@b.co', password: 'a long password', consent: consent);
    final store = MemoryAccountStore();
    expect(
      await problemOf(() =>
          phone(server, store).logIn(email: 'a@b.co', password: 'wrong password')),
      AccountProblem.wrongCredentials,
    );
    expect(store.saved, isNull);
  });

  test('a weak setting from the server is refused before anything is sent', () async {
    final server = FakeServer()
      ..kdfOverride = {
        'salt': toBase64(List.filled(16, 1)),
        'kdf': {'alg': 'argon2id', 'm': 8, 't': 1, 'p': 1},
      };
    expect(
      await problemOf(() => phone(server).logIn(email: 'a@b.co', password: 'a long password')),
      AccountProblem.weakServerSettings,
    );
    expect(server.calls, ['POST /v1/kdf']);
  });

  test('forgot password: the recovery key sets a new one; the old stops working', () async {
    final server = FakeServer();
    final key = await phone(server)
        .signUp(email: 'a@b.co', password: 'old password 1', consent: consent);
    final store = MemoryAccountStore();
    await phone(server, store).recover(
      email: 'a@b.co',
      recoveryKey: key.format().toLowerCase().replaceAll('-', ' '),
      newPassword: 'new password 2',
    );
    expect(store.saved, isNotNull);

    expect(
      await problemOf(() => phone(server).logIn(email: 'a@b.co', password: 'old password 1')),
      AccountProblem.wrongCredentials,
    );
    final again = MemoryAccountStore();
    await phone(server, again).logIn(email: 'a@b.co', password: 'new password 2');
    expect(again.saved!.dataKey, store.saved!.dataKey);
  });

  test('a typo in the recovery key is caught before any network call', () async {
    final server = FakeServer();
    final key = RecoveryKey.fromSecret(List.generate(18, (i) => i * 11)).format();
    final typo = key.replaceRange(0, 1, key[0] == 'A' ? 'B' : 'A');
    expect(
      await problemOf(() => phone(server)
          .recover(email: 'a@b.co', recoveryKey: typo, newPassword: 'new password 2')),
      AccountProblem.recoveryKeyTypo,
    );
    expect(
      await problemOf(() => phone(server)
          .recover(email: 'a@b.co', recoveryKey: 'ABC', newPassword: 'new password 2')),
      AccountProblem.recoveryKeyFormat,
    );
    expect(server.calls, isEmpty);
  });

  test('another recovery key is refused', () async {
    final server = FakeServer();
    await phone(server).signUp(email: 'a@b.co', password: 'a long password', consent: consent);
    expect(
      await problemOf(() => phone(server).recover(
          email: 'a@b.co',
          recoveryKey: RecoveryKey.generate().format(),
          newPassword: 'new password 2')),
      AccountProblem.wrongRecoveryKey,
    );
  });

  test('offline and rate-limited are told apart', () async {
    final server = FakeServer()..offline = true;
    expect(
      await problemOf(() => phone(server).logIn(email: 'a@b.co', password: 'a long password')),
      AccountProblem.network,
    );
    server
      ..offline = false
      ..rateLimited = true;
    try {
      await phone(server).logIn(email: 'a@b.co', password: 'a long password');
      fail('should be refused');
    } on AccountFailure catch (e) {
      expect(e.problem, AccountProblem.rateLimited);
      expect(e.retryAfterSeconds, 120);
    }
  });

  test('an unexpected server error keeps its code for the screen', () async {
    final server = FakeServer()..failRegisterWith = 'bad_bundle';
    try {
      await phone(server)
          .signUp(email: 'a@b.co', password: 'a long password', consent: consent);
      fail('should be refused');
    } on AccountFailure catch (e) {
      expect(e.problem, AccountProblem.server);
      expect(e.code, 'bad_bundle');
    }
  });

  test('right of access: the server info shows the consent given', () async {
    final server = FakeServer();
    final a = phone(server);
    await a.signUp(email: 'a@b.co', password: 'a long password', consent: consent);
    final info = await a.info();
    expect(info.email, 'a@b.co');
    expect(info.privacyVersion, privacyNotice.version);
    expect(info.termsVersion, termsOfUse.version);
    expect(info.consentAt, isNotNull);
  });

  test('delete account: needs the password, then everything is gone', () async {
    final server = FakeServer();
    final store = MemoryAccountStore();
    final a = phone(server, store);
    await a.signUp(email: 'a@b.co', password: 'a long password', consent: consent);

    expect(await problemOf(() => a.deleteAccount('wrong password')),
        AccountProblem.wrongCredentials);
    expect(a.signedIn, true);

    await a.deleteAccount('a long password');
    expect(a.signedIn, false);
    expect(store.saved, isNull);
    expect(server.users, isEmpty);
  });

  test('log out forgets the account even when offline', () async {
    final server = FakeServer();
    final store = MemoryAccountStore();
    final a = phone(server, store);
    await a.signUp(email: 'a@b.co', password: 'a long password', consent: consent);
    server.offline = true;
    await a.logOut();
    expect(a.signedIn, false);
    expect(store.saved, isNull);
  });

  test('a restart restores the saved account', () async {
    final server = FakeServer();
    final store = MemoryAccountStore();
    await phone(server, store)
        .signUp(email: 'a@b.co', password: 'a long password', consent: consent);
    final again = phone(server, store);
    expect(again.signedIn, false);
    await again.load();
    expect(again.current!.email, 'a@b.co');
  });

  test('the slow key work really runs in a background isolate', () async {
    const work = KeyWork(params: fast, minimum: fast);
    final account = await work.createAccount('a long password');
    expect(await account.bundle.openWithRecoveryKey(account.recoveryKey),
        account.dataKey);
  });
}
