// Two phones, the real server.
//
// Unlike test/sync_test.dart (which uses a pretend server written for the
// test), this talks over HTTP to the real server code (server/scripts/
// serve-local.ts, started by CI), with the real Argon2id and encryption.
// A mismatch between what the phone sends and what the server accepts
// fails here. Run by CI; needs BEAZA_LIVE_SERVER.
import 'dart:io';

import 'package:beaza/data/repositories/account_repository.dart';
import 'package:beaza/data/repositories/drift_ledger_repository.dart';
import 'package:beaza/data/repositories/drift_settings_repository.dart';
import 'package:beaza/data/repositories/preferences_store.dart';
import 'package:beaza/data/repositories/sync_repository.dart';
import 'package:beaza/data/services/account_store.dart';
import 'package:beaza/data/services/database.dart';
import 'package:beaza/data/services/database_opener.dart';
import 'package:beaza/data/services/key_work.dart';
import 'package:beaza/data/services/sync_api.dart';
import 'package:beaza/ui/features/account/legal_text.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter_test/flutter_test.dart';

const server = String.fromEnvironment('BEAZA_LIVE_SERVER');

final email = 'live${DateTime.now().millisecondsSinceEpoch}@example.com';
const password = 'a long password for the test';

final consent = Consent(
  privacyVersion: privacyNotice.version,
  termsVersion: termsOfUse.version,
  adult: true,
);

/// One phone: its own database, account store and preferences.
class Phone {
  Phone(String deviceId) : db = openMemoryDatabase() {
    final api = SyncApi(baseUrl: server);
    account = RemoteAccountRepository(
        api: api, store: MemoryAccountStore(), work: const KeyWork());
    ledger = DriftLedgerRepository(db, deviceId: deviceId);
    settings = DriftSettingsRepository(db);
    sync = SyncRepository(
      api: api,
      account: account,
      collections: [ledger, settings],
      preferences: MemoryPreferencesStore(),
    );
  }

  final AppDatabase db;
  late final RemoteAccountRepository account;
  late final DriftLedgerRepository ledger;
  late final DriftSettingsRepository settings;
  late final SyncRepository sync;

  Future<List<String?>> merchants() async => [
        for (final e in await ledger.entries()) e.result.merchantRaw,
      ]..sort((a, b) => (a ?? '').compareTo(b ?? ''));

  Future<void> close() async {
    sync.dispose();
    await db.close();
  }
}

void main() {
  setUpAll(() {
    // flutter test blocks real network calls unless this is cleared.
    HttpOverrides.global = null;
    expect(server, isNotEmpty, reason: 'pass --dart-define=BEAZA_LIVE_SERVER=...');
  });

  test('sign up on one phone, log in on another, and stay in step',
      () async {
    final a = Phone('phoneA');
    final b = Phone('phoneB');
    addTearDown(() async {
      await a.close();
      await b.close();
    });

    // Phone A makes the account (real Argon2id, real key bundle).
    final recoveryKey =
        await a.account.signUp(email: email, password: password, consent: consent);
    expect(recoveryKey.format(), isNotEmpty);

    // It already holds an expense, so it is asked once; the person agrees.
    await a.ledger.addManual(
        amountFils: 2500, merchant: 'Bakery', at: DateTime.now());
    await a.settings.save(const GuardrailSettings(dailyLimitFils: 11000));
    expect(await a.sync.syncNow(), isFalse);
    expect(a.sync.mergeCount, 1);
    expect(await a.sync.approveMerge(), isTrue, reason: '${a.sync.failure}');

    // Phone B logs in with the password and opens the same data key.
    await b.account.logIn(email: email, password: password);
    expect(b.account.current!.dataKey, a.account.current!.dataKey);
    expect(await b.sync.syncNow(), isTrue, reason: '${b.sync.failure}');
    expect(b.sync.mergeCount, isNull);
    expect(await b.merchants(), ['Bakery']);
    expect((await b.settings.load()).dailyLimitFils, 11000);

    // B adds an expense and changes the limit; A gets both.
    await b.ledger.addManual(
        amountFils: 700, merchant: 'Cafe', at: DateTime.now());
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await b.settings.save(const GuardrailSettings(dailyLimitFils: 9000));
    expect(await b.sync.syncNow(), isTrue, reason: '${b.sync.failure}');
    expect(await a.sync.syncNow(), isTrue, reason: '${a.sync.failure}');
    expect(await a.merchants(), ['Bakery', 'Cafe']);
    expect((await a.settings.load()).dailyLimitFils, 9000);

    // A deletes the bakery expense; B no longer counts it.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final bakery = (await a.db.select(a.db.ledgerRows).get())
        .firstWhere((r) => r.merchantRaw == 'Bakery');
    await a.ledger.delete(bakery.id);
    expect(await a.sync.syncNow(), isTrue);
    expect(await b.sync.syncNow(), isTrue);
    expect(await b.merchants(), ['Cafe']);

    // What the server says it holds: 3 encrypted records (2 expenses and
    // the settings), and the sessions of both phones.
    final info = await a.account.info();
    expect(info.encryptedRecords, 3);
    expect(info.activeSessions, 2);

    // A wrong password does not open anything.
    final intruder = Phone('phoneX');
    addTearDown(intruder.close);
    await expectLater(
      intruder.account.logIn(email: email, password: 'not the password'),
      throwsA(isA<AccountFailure>()
          .having((f) => f.problem, 'problem', AccountProblem.wrongCredentials)),
    );

    // Deleting the account on A ends B's session too.
    await a.account.deleteAccount(password);
    expect(await b.sync.syncNow(), isFalse);
    expect(b.sync.failure!.problem, AccountProblem.sessionExpired);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('a second phone with its own data is asked before anything is mixed',
      () async {
    final mail = 'ask${DateTime.now().millisecondsSinceEpoch}@example.com';
    final a = Phone('phoneA');
    final b = Phone('phoneB');
    addTearDown(() async {
      await a.close();
      await b.close();
    });
    await a.account.signUp(email: mail, password: password, consent: consent);
    await a.ledger.addManual(
        amountFils: 100, merchant: 'Mine', at: DateTime.now());
    await a.sync.approveMerge();

    // B has its own spending and logs in by mistake.
    await b.ledger.addManual(
        amountFils: 999, merchant: 'Private', at: DateTime.now());
    await b.account.logIn(email: mail, password: password);
    expect(await b.sync.syncNow(), isFalse);
    expect(b.sync.mergeCount, 1);
    expect((await a.account.info()).encryptedRecords, 1,
        reason: 'nothing of B reached the server');
    expect(await b.merchants(), ['Private'], reason: 'nothing of A came in');

    await a.account.deleteAccount(password);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
